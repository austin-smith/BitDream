import Foundation
import SwiftUI
import SwiftData

/// Platform-agnostic wrapper for ServerDetail view
/// This view simply delegates to the appropriate platform-specific implementation
struct ServerDetail: View {
    @ObservedObject var store: TransmissionStore
    let modelContext: ModelContext
    let hosts: [Host]
    @State var host: Host?
    var isAddNew: Bool

    static let defaultPort = 9091

    // Validation messages
    static let hostRequiredMessage = "Hostname is required"
    static let invalidPortMessage = "Port number is required"

    var body: some View {
        #if os(iOS)
        iOSServerDetail(
            store: store,
            modelContext: modelContext,
            hosts: hosts,
            host: host,
            isAddNew: isAddNew
        )
        #elseif os(macOS)
        macOSServerDetail(
            store: store,
            modelContext: modelContext,
            hosts: hosts,
            host: host,
            isAddNew: isAddNew
        )
        #endif
    }
}

// MARK: - Shared Helper Functions

private func userFacingHostPersistenceMessage(_ error: Error) -> String {
    if let persistenceError = error as? HostPersistenceError {
        return persistenceError.userMessage
    }
    return error.localizedDescription
}

/// Saves a new server through the host repository
@MainActor
func saveNewServer(
    draft: HostDraft,
    modelContext: ModelContext,
    store: TransmissionStore,
    completion: @MainActor @escaping () -> Void,
    onError: @MainActor @escaping (String) -> Void = { _ in }
) {
    // Validate required fields
    guard !draft.server.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    guard draft.port >= 1 && draft.port <= 65535 else { return }

    Task { @MainActor in
        do {
            let host = try await HostRepository.shared.create(draft: draft)
            if store.host == nil {
                store.setHost(host: host)
            }
            completion()
        } catch {
            if let persistenceError = error as? HostPersistenceError,
               case .catalogSyncFailure = persistenceError {
                if store.host == nil {
                    ensureStartupConnectionBehaviorApplied(store: store, modelContext: modelContext)
                }
                completion()
                return
            }
            onError(userFacingHostPersistenceMessage(error))
        }
    }
}

/// Updates an existing server through the host repository
@MainActor
func updateExistingServer(
    host: Host,
    draft: HostDraft,
    completion: @MainActor @escaping () -> Void,
    onError: @MainActor @escaping (String) -> Void = { _ in }
) {
    Task { @MainActor in
        do {
            _ = try await HostRepository.shared.update(serverID: host.serverID, draft: draft)
            completion()
        } catch {
            if let persistenceError = error as? HostPersistenceError,
               case .catalogSyncFailure = persistenceError {
                completion()
                return
            }
            onError(userFacingHostPersistenceMessage(error))
        }
    }
}

/// Loads server data into state variables
@MainActor
func loadServerData(
    host: Host,
    onLoad: @escaping (String, Bool, String, Int, Bool, String, String) -> Void
) {
    let nameInput = host.name ?? ""
    let isDefault = host.isDefault
    let hostInput = host.server ?? ""
    let portInput = Int(host.port)
    let isSSL = host.isSSL
    let userInput = host.username ?? ""
    let passInput: String
    if let credentialKey = KeychainService.credentialKeyIfPresent(for: host) {
        passInput = KeychainService.readPassword(credentialKey: credentialKey)
    } else {
        passInput = ""
    }

    onLoad(nameInput, isDefault, hostInput, portInput, isSSL, userInput, passInput)
}

/// Deletes a server through the host repository
@MainActor
func deleteServerFromDetail(
    host: Host,
    store: TransmissionStore,
    hosts: [Host],
    modelContext _: ModelContext,
    completion: @MainActor @escaping () -> Void,
    onError: @MainActor @escaping (String) -> Void = { _ in }
) {
    let completeDeletion = {
        if host.serverID == store.host?.serverID {
            if let nextHost = hosts.first(where: { $0.serverID != host.serverID }) {
                store.setHost(host: nextHost)
                UserDefaults.standard.set(nextHost.serverID, forKey: UserDefaultsKeys.selectedHost)
            } else {
                UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.selectedHost)
                store.clearSelectedHost()
            }
        }

        completion()
    }

    Task { @MainActor in
        do {
            try await HostRepository.shared.delete(serverID: host.serverID)
            completeDeletion()
        } catch {
            if let persistenceError = error as? HostPersistenceError,
               case .catalogSyncFailure = persistenceError {
                completeDeletion()
                return
            }
            onError(userFacingHostPersistenceMessage(error))
        }
    }
}
