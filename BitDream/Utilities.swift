import Foundation
import SwiftUI
import WidgetKit
import UniformTypeIdentifiers

// MARK: - Generic Sorting

struct SortDescriptor<Value> {
    var comparator: (Value, Value) -> ComparisonResult
}

extension SortDescriptor {
    static func keyPath<T: Comparable>(_ keyPath: KeyPath<Value, T>) -> Self {
        Self { rootA, rootB in
            let valueA = rootA[keyPath: keyPath]
            let valueB = rootB[keyPath: keyPath]

            guard valueA != valueB else {
                return .orderedSame
            }

            return valueA < valueB ? .orderedAscending : .orderedDescending
        }
    }
}

enum SortOrder {
    case ascending
    case descending
}

extension Sequence {
    func sorted(using descriptors: [SortDescriptor<Element>],
                order: SortOrder) -> [Element] {
        sorted { valueA, valueB in
            for descriptor in descriptors {
                let result = descriptor.comparator(valueA, valueB)

                switch result {
                case .orderedSame:
                    // Keep iterating if the two elements are equal,
                    // since that'll let the next descriptor determine
                    // the sort order:
                    break
                case .orderedAscending:
                    return order == .ascending
                case .orderedDescending:
                    return order == .descending
                }
            }

            // If no descriptor was able to determine the sort
            // order, we'll default to false (similar to when
            // using the '<' operator with the built-in API):
            return false
        }
    }
}

extension Sequence {
    func sortedAscending(using descriptors: SortDescriptor<Element>...) -> [Element] {
        sorted(using: descriptors, order: .ascending)
    }
}

extension Sequence {
    func sortedDescending(using descriptors: SortDescriptor<Element>...) -> [Element] {
        sorted(using: descriptors, order: .descending)
    }
}

// MARK: - Formatting

/// Shared byte formatting helper using modern format style
/// Round up 1 to 999 bytes to 1 kB
public func formatByteCount(_ bytes: Int64) -> String {
    if bytes == 0 {
        return "0 kB"
    }
    if bytes > 0 && bytes < 1_000 {
        return "1 kB"
    }
    return bytes.formatted(
        ByteCountFormatStyle(
            style: .file,
            allowedUnits: [.kb, .mb, .gb, .tb],
            spellsOutZero: false,
            includesActualByteCount: false
        )
    )
}

/// Shared speed formatting helper (Bytes per second -> human-readable short string)
func formatSpeed(_ bytesPerSecond: Int64) -> String {
    let base = formatByteCount(bytesPerSecond)
    return "\(base)/s"
}

// MARK: - Transmission Refresh

/// Updates the list of torrents when called
@MainActor
func updateList(store: AppStore, update: @escaping ([Torrent]) -> Void, retry: Int = 0) {
    let info = makeConfig(store: store)
    getTorrents(config: info.config, auth: info.auth, onReceived: { torrents, err in
        if let err = err {
            store.handleConnectionError(message: err)
            return
        }

        guard let torrents = torrents else {
            store.handleConnectionError(message: "No data returned from server.")
            return
        }

        update(torrents)
    })
}

/// Updates the list of torrents when called
@MainActor
func updateSessionStats(store: AppStore, update: @escaping (SessionStats) -> Void, retry: Int = 0) {
    let info = makeConfig(store: store)
    getSessionStats(config: info.config, auth: info.auth, onReceived: { sessions, err in
        if let err = err {
            store.handleConnectionError(message: err)
            return
        }

        guard let stats = sessions else {
            store.handleConnectionError(message: "No data returned from server.")
            return
        }

        update(stats)
        // Write widget snapshot; non-blocking and non-fatal on failure
        if let host = store.host {
            let serverName = host.name ?? host.server ?? "Server"
            writeSessionSnapshot(
                serverID: host.serverID,
                serverName: serverName,
                stats: stats,
                torrents: store.torrents
            )
        }
    })
}

/// Updates the session configuration (download directory, version, settings) with retry logic
@MainActor
func updateSessionInfo(store: AppStore, update: @escaping (TransmissionSessionResponseArguments) -> Void, retry: Int = 0) {
    let info = makeConfig(store: store)
    getSession(config: info.config, auth: info.auth, onResponse: { sessionInfo in
        update(sessionInfo)
    }, onError: { err in
        store.handleConnectionError(message: err)
    })
}

@MainActor
func pollTransmissionData(store: AppStore) {
    let info = makeConfig(store: store)
    getSessionStats(config: info.config, auth: info.auth, onReceived: { sessions, err in
        if let err = err {
            store.handleConnectionError(message: err)
            return
        }

        guard let stats = sessions else {
            store.handleConnectionError(message: "No data returned from server.")
            return
        }

        store.markConnected()
        store.sessionStats = stats
        if let host = store.host {
            let serverName = host.name ?? host.server ?? "Server"
            writeSessionSnapshot(
                serverID: host.serverID,
                serverName: serverName,
                stats: stats,
                torrents: store.torrents
            )
        }

        updateList(store: store, update: { vals in
            store.torrents = vals
        })

        updateSessionInfo(store: store, update: { sessionInfo in
            store.sessionConfiguration = sessionInfo
            store.defaultDownloadDir = sessionInfo.downloadDir

            if let serverID = store.host?.serverID {
                let version = sessionInfo.version
                Task { @MainActor in
                    await HostRepository.shared.persistVersionIfNeeded(serverID: serverID, version: version)
                }
            }
        })
    })
}

// updates all Transmission data based on current host
@MainActor
func refreshTransmissionData(store: AppStore) {
    pollTransmissionData(store: store)
}

// MARK: - Helpers

/// Function for generating config and auth for API calls
/// - Parameter store: The current `AppStore` containing session information needed for creating the config.
/// - Returns a tuple containing the requested `config` and `auth`
@MainActor
func makeConfig(store: AppStore) -> (config: TransmissionConfig, auth: TransmissionAuth) {
    // Build config and auth safely without force unwraps
    var config = TransmissionConfig()
    guard let host = store.host else {
        return (config: config, auth: TransmissionAuth(username: "", password: ""))
    }
    config.host = host.server
    config.port = Int(host.port)
    config.scheme = host.isSSL ? "https" : "http"

    let username = host.username ?? ""
    let password: String
    if let credentialKey = KeychainService.credentialKeyIfPresent(for: host) {
        password = KeychainService.readPassword(credentialKey: credentialKey)
    } else {
        password = ""
    }
    let auth = TransmissionAuth(username: username, password: password)

    return (config: config, auth: auth)
}

// MARK: - Transmission Response Handling

/// Handles TransmissionResponse with proper error handling and user feedback
/// - Parameters:
///   - response: The TransmissionResponse from the API call
///   - onSuccess: Callback executed on successful response
///   - onError: Callback executed on error with user-friendly error message
func handleTransmissionResponse(
    _ response: TransmissionResponse,
    onSuccess: @escaping () -> Void,
    onError: @escaping (String) -> Void
) {
    guard let presentation = TransmissionLegacyCompatibility.presentation(for: response) else {
        onSuccess()
        return
    }

    onError(presentation.message)
}

/// SwiftUI View modifier for displaying transmission error alerts
struct TransmissionErrorAlert: ViewModifier {
    @Binding var isPresented: Bool
    let message: String

    func body(content: Content) -> some View {
        content
            .alert("Error", isPresented: $isPresented) {
                Button("OK") { }
            } message: {
                Text(message)
            }
    }
}

extension View {
    /// Adds a standardized error alert for transmission operations
    func transmissionErrorAlert(isPresented: Binding<Bool>, message: String) -> some View {
        modifier(TransmissionErrorAlert(isPresented: isPresented, message: message))
    }
}
