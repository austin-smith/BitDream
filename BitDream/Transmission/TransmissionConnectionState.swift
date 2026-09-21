import Foundation

/// One source of truth for an attempt, a scheduled retry, or required intervention.
enum TransmissionConnectionState {
    case connecting
    case connected
    case failed(TransmissionError, retryAt: Date?)
    case retrying(TransmissionError)
    case requiresAction(TransmissionError)

    var failure: TransmissionError? {
        switch self {
        case .failed(let error, _), .retrying(let error), .requiresAction(let error): error
        case .connecting, .connected: nil
        }
    }

    var retryAt: Date? {
        if case .failed(_, let date) = self { return date }
        return nil
    }

    var isAttempting: Bool {
        switch self {
        case .connecting, .retrying: true
        case .connected, .failed, .requiresAction: false
        }
    }
}

extension TransmissionError {
    /// Only connection attempts use this policy. Mutating RPCs are never replayed.
    var permitsAutomaticRetry: Bool {
        switch self {
        case .invalidEndpointConfiguration, .unauthorized, .cancelled,
             .rpcFailure, .invalidResponse, .decoding:
            return false
        case .tailscale(let error):
            switch error {
            case .unavailable, .connectionChanged, .peerUnavailable, .connectionFailed: return true
            case .signInRequired, .approvalRequired, .accountMismatch, .ambiguousPeer,
                 .invalidRoute, .untrustedRedirect: return false
            }
        case .network(let code):
            switch code {
            case .badURL, .unsupportedURL, .appTransportSecurityRequiresSecureConnection,
                 .secureConnectionFailed, .serverCertificateHasBadDate, .serverCertificateUntrusted,
                 .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid,
                 .clientCertificateRejected, .clientCertificateRequired: return false
            default: return true
            }
        case .httpStatus(let code, _):
            // Transmission uses 409 to refresh its session token; a later read can recover.
            return code == 408 || code == 409 || code == 429 || (500...599).contains(code)
        case .transport, .timeout: return true
        }
    }
}

// Safe for diagnostics: no URLs, response bodies, account identifiers, or credentials.
extension TransmissionError {
    var diagnosticCode: String {
        switch self {
        case .invalidEndpointConfiguration: "invalid_endpoint"
        case .unauthorized: "unauthorized"
        case .transport: "transport"
        case .tailscale(let error): "tailscale.\(error)"
        case .network(let code): "url_session.\(code.rawValue)"
        case .timeout: "timeout"
        case .cancelled: "cancelled"
        case .httpStatus(let code, _): "http.\(code)"
        case .rpcFailure: "rpc_failure"
        case .invalidResponse: "invalid_response"
        case .decoding: "decoding"
        }
    }
}
