import Foundation

// TODO: Remove this file in phase 5 once write-side callers stop depending on
// `makeConfig(store:)`.
/// Temporary compatibility helper for legacy write-side call sites.
/// Phase 4 removes settings/session use of this helper, but torrent actions still depend on it.
@MainActor
func makeConfig(store: TransmissionStore) -> (config: TransmissionConfig, auth: TransmissionAuth) {
    guard let host = store.host else {
        return (TransmissionConfig(), TransmissionAuth(username: "", password: ""))
    }

    var config = TransmissionConfig()
    config.host = host.server
    config.port = Int(host.port)
    config.scheme = host.isSSL ? "https" : "http"

    let auth = TransmissionAuth(
        username: host.username ?? "",
        password: store.readPassword(for: host)
    )
    return (config, auth)
}
