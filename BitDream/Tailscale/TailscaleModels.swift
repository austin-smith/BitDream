import Foundation
import Network

/// Saved routes are explicit. Missing legacy values mean system networking;
/// unrecognized values must fail validation rather than fall back to that route.
enum ServerConnectionRoute: String, Codable, CaseIterable, Sendable {
    case system
    case tailscale
}

enum TailscaleAccountID {
    /// Earlier builds stored DNS suffix / user ID / node ID. Match those saved
    /// servers by user ID too, without requiring a save or a new registration.
    /// This namespace is for the hosted Tailscale control plane used by the app.
    static func canonical(_ value: String) -> String {
        let parts = value.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].hasSuffix(".ts.net"), !parts[2].isEmpty,
              !parts[1].isEmpty, parts[1].utf8.allSatisfy({ (48...57).contains($0) }),
              let userID = Int64(parts[1]), userID > 0 else { return value }
        return "tailscale-user/\(userID)"
    }

    static func matches(_ saved: String, _ current: String) -> Bool {
        !saved.isEmpty && !current.isEmpty && canonical(saved) == canonical(current)
    }
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
    var errorCode: String?

    var isReady: Bool { state == "Running" && accountID?.isEmpty == false && proxyPort != nil }

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
        case "Running": "Connected"
        case "NeedsLogin": "Not signed in"
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
    var waitingState: String?
    var peerAddress: String?
}

enum TailscaleError: LocalizedError, Sendable, Equatable {
    case unavailable
    case signInRequired
    case approvalRequired
    case accountMismatch
    case connectionChanged
    case peerUnavailable
    case ambiguousPeer
    case connectionFailed
    case invalidRoute
    case untrustedRedirect

    var errorDescription: String? {
        switch self {
        case .unavailable: "Tailscale could not connect. Check your network and try again."
        case .signInRequired: "Sign in to Tailscale in this server’s connection settings."
        case .approvalRequired: "Approve this BitDream device in your Tailscale admin console."
        case .accountMismatch: "This server was saved with a different Tailscale account or tailnet. Sign out and sign in with the account and tailnet you used to add it."
        case .connectionChanged: "The Tailscale connection changed. Reconnect to the server and try again."
        case .peerUnavailable: "This machine is currently unavailable through Tailscale."
        case .ambiguousPeer: "More than one Tailscale machine matches this address. Enter its full hostname or IP address."
        case .connectionFailed: "Could not connect to the server through Tailscale."
        case .invalidRoute: "This server’s connection method is not supported. Edit its connection settings."
        case .untrustedRedirect: "The RPC endpoint redirected to another address. Enter the final server address in connection settings."
        }
    }
}
