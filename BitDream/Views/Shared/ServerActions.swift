import Foundation
import SwiftUI
import Combine

/// Only saved catalog mutations cross window boundaries, never presentation state.
@MainActor
enum ServerChanges {
    enum Mutation {
        case updated(Host)
        case deleted(String, remainingHosts: [Host])
    }

    struct Change {
        let source: TransmissionStore
        let mutation: Mutation
    }

    static let publisher = PassthroughSubject<Change, Never>()
}

/// Shared persistence actions for server management, used by the iOS and macOS server views.

func userFacingHostPersistenceMessage(_ error: Error) -> String {
    if let persistenceError = error as? HostPersistenceError {
        return persistenceError.userMessage
    }
    return error.localizedDescription
}

/// Saves a new server through the host repository.
@MainActor
func saveNewServer(
    draft: HostDraft,
    store: TransmissionStore,
    hostRepository: any HostPersisting = HostRepository.shared
) async throws -> Host {
    let host = try await hostRepository.create(draft: draft)
    if store.host == nil {
        store.setHost(host: host)
    }
    return host
}

/// Updates an existing server through the host repository
@MainActor
func updateExistingServer(
    host: Host,
    draft: HostDraft,
    store: TransmissionStore,
    hostRepository: any HostPersisting = HostRepository.shared
) async throws -> Host {
    do {
        let updatedHost = try await hostRepository.update(serverID: host.serverID, draft: draft)
        store.applyPersistedHostUpdate(updatedHost)
        ServerChanges.publisher.send(.init(source: store, mutation: .updated(updatedHost)))
        return updatedHost
    } catch {
        if let persistenceError = error as? HostPersistenceError,
           case .catalogSyncFailure = persistenceError {
            store.applyPersistedHostUpdate(host)
            ServerChanges.publisher.send(.init(source: store, mutation: .updated(host)))
            return host
        }
        throw error
    }
}

/// Deletes a server through the host repository and moves the connection to another server if needed.
@MainActor
func deleteServer(
    host: Host,
    store: TransmissionStore,
    hosts: [Host],
    hostRepository: any HostPersisting = HostRepository.shared
) async throws {
    do {
        try await hostRepository.delete(serverID: host.serverID)
    } catch {
        if let persistenceError = error as? HostPersistenceError,
           case .catalogSyncFailure = persistenceError {
            completeServerDeletion(host: host, store: store, hosts: hosts)
            return
        }
        throw error
    }

    completeServerDeletion(host: host, store: store, hosts: hosts)
}

@MainActor
private func completeServerDeletion(host: Host, store: TransmissionStore, hosts: [Host]) {
    let serverID = host.serverID
    let remainingHosts = hosts.filter { $0.serverID != serverID }
    completeServerDeletion(serverID: serverID, store: store, remainingHosts: remainingHosts)
    ServerChanges.publisher.send(.init(source: store, mutation: .deleted(serverID, remainingHosts: remainingHosts)))
}

@MainActor
func completeServerDeletion(serverID: String, store: TransmissionStore, remainingHosts: [Host]) {
    guard serverID == store.host?.serverID else { return }

    if let nextHost = remainingHosts.first {
        store.setHost(host: nextHost)
    } else {
        store.clearPersistedSelectedHost()
        store.clearSelectedHost()
    }
}

/// Confirmation message for server deletion.
@MainActor
@ViewBuilder
func deleteConfirmationMessage(for host: Host, store: TransmissionStore) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        Text("Are you sure you want to delete \(host.displayName)?")

        if host.serverID == store.host?.serverID {
            Text("This is your currently connected server. You will be disconnected and connected to another server if available.")
                .font(.caption)
                .foregroundStyle(.orange)
        }

        Text("This action cannot be undone.")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }
}
