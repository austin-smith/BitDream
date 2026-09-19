import Foundation
import Network

/// Saved routes are explicit. Missing legacy values mean system networking;
/// unrecognized values must fail validation rather than fall back to that route.
enum ServerConnectionRoute: String, Codable, CaseIterable, Sendable {
    case system
    case tailscale
}

struct TailscalePeer: Decodable, Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let address: String
    let online: Bool
    var ips: [String]?

    func matches(host: String) -> Bool {
        let normalized = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".[]"))
        let name = address.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        if normalized == name || (name.contains(".ts.net") && normalized == name.split(separator: ".").first.map(String.init)) {
            return true
        }
        return (ips ?? []).contains { candidate in
            if let lhs = IPv6Address(normalized), let rhs = IPv6Address(candidate) { return lhs.rawValue == rhs.rawValue }
            if let lhs = IPv4Address(normalized), let rhs = IPv4Address(candidate) { return lhs.rawValue == rhs.rawValue }
            return false
        }
    }
}

struct TailscaleSnapshot: Decodable, Sendable {
    let generation: UInt64
    let state: String
    let authURL: String?
    let accountID: String?
    let accountName: String?
    let peers: [TailscalePeer]
    let proxyPort: UInt16?
    let proxyPassword: String?
    let error: String?

    var isReady: Bool { state == "Running" && accountID != nil && proxyPort != nil }

    /// Authentication and network readiness are separate. NeedsLogin can still
    /// include a cached account after expiry, so account metadata alone is insufficient.
    var isSignedIn: Bool {
        switch state {
        case "NeedsMachineAuth", "Starting", "Running": true
        case "Stopped": accountID?.isEmpty == false
        default: false
        }
    }

    var authorizationURL: URL? {
        guard let authURL, let url = URL(string: authURL),
              url.scheme == "https", url.user == nil, url.password == nil,
              let host = url.host(), host == "login.tailscale.com" || host == "controlplane.tailscale.com" else {
            return nil
        }
        return url
    }

    var statusDescription: String {
        switch state {
        case "Running": "Connected to Tailscale"
        case "NeedsLogin": "Sign in to Tailscale"
        case "NeedsMachineAuth": "Waiting for device approval in Tailscale"
        case "Starting": "Connecting to Tailscale…"
        case "Stopped": "Tailscale is disconnected"
        default: "Tailscale is unavailable"
        }
    }
}

struct TailscaleNativeRequest: Encodable, Sendable {
    let action: String
    var directory: String?
    var hostname: String?
}

enum TailscaleError: LocalizedError, Sendable {
    case unavailable
    case signInRequired
    case approvalRequired
    case accountMismatch
    case connectionChanged
    case peerUnavailable
    case invalidRoute
    case untrustedRedirect

    var errorDescription: String? {
        switch self {
        case .unavailable: "Tailscale could not connect. Check your network and try again."
        case .signInRequired: "Sign in to Tailscale in this server’s connection settings."
        case .approvalRequired: "Approve this BitDream device in your Tailscale admin console."
        case .accountMismatch: "This server belongs to a different Tailscale identity. Edit the server to select the current account."
        case .connectionChanged: "The Tailscale connection changed. Reconnect to the server and try again."
        case .peerUnavailable: "This address does not match a machine visible to your Tailscale account. Select a machine or enter its full Tailscale hostname or IP address."
        case .invalidRoute: "This server’s connection method is not supported. Edit its connection settings."
        case .untrustedRedirect: "The RPC endpoint redirected to another address. Enter the final server address in connection settings."
        }
    }
}
