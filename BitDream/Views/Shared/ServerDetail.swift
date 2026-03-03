import Foundation
import SwiftUI
import SwiftData

/// Platform-agnostic wrapper for ServerDetail view
/// This view simply delegates to the appropriate platform-specific implementation
struct ServerDetail: View {
    @ObservedObject var store: Store
    let modelContext: ModelContext
    let hosts: [Host]
    @State var host: Host?
    var isAddNew: Bool

    static let defaultPort = 9091

    // Validation messages
    static let hostRequiredMessage = "Hostname is required"
    static let invalidPortMessage = "Port number is required"

    static let portFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.minimum = 1
        formatter.maximum = 65535  // Maximum valid port number
        return formatter
    }()

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

/// Saves a new server to Core Data and Keychain
func saveNewServer(
    nameInput: String,
    hostInput: String,
    portInput: Int,
    userInput: String,
    passInput: String,
    isDefault: Bool,
    isSSL: Bool,
    modelContext: ModelContext,
    hosts: [Host],
    store: Store,
    completion: @escaping () -> Void
) {
    // Validate required fields
    guard !hostInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    guard portInput >= 1 && portInput <= 65535 else { return }

    // If friendly name is empty, use hostname
    let finalNameInput = nameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?
        hostInput : nameInput

    if isDefault {
        hosts.forEach { host in
            if host.isDefault {
                host.isDefault = false
            }
        }
    }

    // Save host
    let newHost = Host(
        isDefault: isDefault,
        isSSL: isSSL,
        name: finalNameInput,
        port: Int16(portInput),
        server: hostInput,
        username: userInput
    )
    _ = newHost.ensureCredentialKey()
    modelContext.insert(newHost)

    try? modelContext.save()

    // Save password to keychain
    KeychainPasswordStore.savePassword(passInput, for: newHost)

    // if there is no host currently set, then set it to the one being created
    if (store.host == nil) {
        store.setHost(host: newHost)
    }

    completion()
}

/// Updates an existing server in Core Data and Keychain
func updateExistingServer(
    host: Host,
    nameInput: String,
    hostInput: String,
    portInput: Int,
    userInput: String,
    passInput: String,
    isDefault: Bool,
    isSSL: Bool,
    modelContext: ModelContext,
    hosts: [Host],
    completion: @escaping () -> Void
) {
    // Save host
    host.name = nameInput
    host.isDefault = isDefault
    host.server = hostInput
    host.port = Int16(portInput)
    host.username = userInput
    host.isSSL = isSSL
    _ = host.ensureCredentialKey()

    // If default is being enabled then ensure to disable it on any current default server
    if (isDefault) {
        hosts.forEach { h in
            if h.isDefault && h.serverID != host.serverID {
                h.isDefault = false
            }
        }
    }

    try? modelContext.save()

    // Save password to keychain
    KeychainPasswordStore.savePassword(passInput, for: host)

    completion()
}

/// Loads server data into state variables
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
    let passInput = KeychainPasswordStore.readPassword(for: host)

    onLoad(nameInput, isDefault, hostInput, portInput, isSSL, userInput, passInput)
}

/// Deletes a server from Core Data
func deleteServer(
    host: Host,
    modelContext: ModelContext,
    completion: @escaping () -> Void
) {
    KeychainPasswordStore.deletePassword(for: host)
    modelContext.delete(host)
    try? modelContext.save()
    completion()
}
