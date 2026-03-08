import Foundation

// TODO: Remove this file in phases 4/5 once write-side callers stop depending on
// `makeConfig(store:)` and `TransmissionStore.currentServerInfo`.
struct LegacyTransmissionContext {
    var config: TransmissionConfig
    var auth: TransmissionAuth
}

/// Temporary compatibility helper for legacy write-side call sites.
/// Phase 3 removes the read-side dependency on this helper, but phases 4-5 still use it.
@MainActor
func makeConfig(store: TransmissionStore) -> (config: TransmissionConfig, auth: TransmissionAuth) {
    guard let serverInfo = store.currentServerInfo else {
        return (TransmissionConfig(), TransmissionAuth(username: "", password: ""))
    }

    return serverInfo
}
