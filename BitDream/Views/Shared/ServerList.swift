import SwiftUI
import SwiftData

/// Platform-agnostic wrapper for ServerList view
/// This view simply delegates to the appropriate platform-specific implementation
struct ServerList: View {
    @ObservedObject var store: Store
    let modelContext: ModelContext
    let hosts: [Host]

    var body: some View {
        // Use NavigationStack for iOS to handle navigation properly
        // This ensures the navigation context is established at this level
        #if os(iOS)
        NavigationStack {
            iOSServerList(
                modelContext: modelContext,
                hosts: hosts,
                store: store
            )
        }
        #else
        // No navigation container needed for macOS
        macOSServerList(
            modelContext: modelContext,
            hosts: hosts,
            store: store
        )
        #endif
        // Ensure no toolbar modifiers are applied at this level
    }
}

// MARK: - Shared Helper Functions

private func userFacingServerListPersistenceMessage(_ error: Error) -> String {
    if let persistenceError = error as? HostPersistenceError {
        return persistenceError.userMessage
    }
    return error.localizedDescription
}

/// Deletes a server through the host repository and handles disconnection if needed
func deleteServer(
    host: Host,
    store: Store,
    hosts: [Host],
    modelContext _: ModelContext,
    completion: @escaping () -> Void,
    onError: @escaping (String) -> Void = { _ in }
) {
    let currentStore = store
    Task { @MainActor in
        do {
            try await HostRepository.shared.delete(serverID: host.serverID)

            if host.serverID == currentStore.host?.serverID {
                let otherServers = hosts.filter { $0.serverID != host.serverID }
                if let newServer = otherServers.first {
                    currentStore.setHost(host: newServer)
                    UserDefaults.standard.set(newServer.serverID, forKey: UserDefaultsKeys.selectedHost)
                } else {
                    currentStore.host = nil
                    UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.selectedHost)
                    currentStore.torrents = []
                    currentStore.sessionStats = nil
                    currentStore.timer.invalidate()
                }
            }

            completion()
        } catch {
            onError(userFacingServerListPersistenceMessage(error))
        }
    }
}

/// Creates a confirmation message for server deletion
@ViewBuilder
func deleteConfirmationMessage(for host: Host, store: Store) -> some View {
    let currentStore = store // Create a local reference to avoid wrapper issues
    VStack(alignment: .leading, spacing: 8) {
        Text("Are you sure you want to delete \(host.name ?? "Unnamed Server")?")

        if host.serverID == currentStore.host?.serverID {
            Text("This is your currently connected server. You will be disconnected and connected to another server if available.")
                .font(.caption)
                .foregroundColor(.orange)
        }

        Text("This action cannot be undone.")
            .font(.caption2)
            .foregroundColor(.secondary)
    }
}

// MARK: - Shared UI Components

/// Button style for hover effects
struct HoverButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverButton(configuration: configuration)
    }

    struct HoverButton: View {
        let configuration: Configuration
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .padding(6)
                .background(isHovered ? Color.gray.opacity(0.2) : Color.clear)
                .cornerRadius(6)
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isHovered = hovering
                    }
                }
        }
    }
}
