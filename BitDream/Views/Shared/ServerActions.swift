import Foundation
import SwiftUI

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
        return updatedHost
    } catch {
        if let persistenceError = error as? HostPersistenceError,
           case .catalogSyncFailure = persistenceError {
            store.applyPersistedHostUpdate(host)
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
    guard host.serverID == store.host?.serverID else { return }

    if let nextHost = hosts.first(where: { $0.serverID != host.serverID }) {
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
