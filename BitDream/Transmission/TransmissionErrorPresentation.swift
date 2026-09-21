import Foundation

struct TransmissionErrorPresentation: Equatable, Sendable {
    let title: String?
    let message: String
}

enum TransmissionErrorResolver {
    static func transmissionError(from error: Error) -> TransmissionError {
        if let transmissionError = error as? TransmissionError {
            return transmissionError
        }

        if let transportFailure = error as? TransmissionTransportFailure {
            return transportFailure.transmissionError
        }

        if error is CancellationError {
            return .cancelled
        }

        if let error = error as? TailscaleError { return .tailscale(error) }
        if let error = error as? URLError {
            switch error.code {
            case .cancelled: return .cancelled
            case .timedOut: return .timeout
            default: return .network(error.code)
            }
        }
        return .transport(underlyingDescription: error.localizedDescription)
    }
}

enum TransmissionErrorPresenter {
    static func presentation(for error: TransmissionError) -> TransmissionErrorPresentation {
        switch error {
        case .invalidEndpointConfiguration:
            return connectionError(message: "Connection error. Please check your server settings.")
        case .unauthorized:
            return authenticationFailed(message: "Authentication failed. Please check your server credentials.")
        case .transport:
            return connectionError(message: "Could not connect to the server.")
        case .tailscale(let error):
            return connectionError(message: error.localizedDescription)
        case .network(let code):
            return networkError(code)
        case .timeout:
            return connectionTimedOut(message: "The request timed out.")
        case .cancelled:
            return requestCancelled(message: "The request was cancelled.")
        case .httpStatus(let code, let body):
            return serverError(message: httpStatusMessage(code: code, body: body))
        case .rpcFailure(let result):
            return operationFailed(message: result)
        case .invalidResponse, .decoding:
            return serverError(message: "The server returned an invalid response.")
        }
    }

    private static func networkError(_ code: URLError.Code) -> TransmissionErrorPresentation {
        switch code {
        case .notConnectedToInternet:
            return connectionError(message: "No internet connection.")
        case .secureConnectionFailed, .serverCertificateHasBadDate, .serverCertificateUntrusted,
             .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid,
             .clientCertificateRejected, .clientCertificateRequired:
            return connectionError(message: "Could not establish a secure connection to the server.")
        case .badURL, .unsupportedURL:
            return connectionError(message: "Check the server address and connection settings.")
        default:
            return connectionError(message: "Could not connect to the server.")
        }
    }

    private static func connectionError(message: String) -> TransmissionErrorPresentation {
        TransmissionErrorPresentation(title: "Connection Error", message: message)
    }

    private static func authenticationFailed(message: String) -> TransmissionErrorPresentation {
        TransmissionErrorPresentation(title: "Authentication Failed", message: message)
    }

    private static func connectionTimedOut(message: String) -> TransmissionErrorPresentation {
        TransmissionErrorPresentation(title: "Connection Timed Out", message: message)
    }

    private static func requestCancelled(message: String) -> TransmissionErrorPresentation {
        TransmissionErrorPresentation(title: "Request Cancelled", message: message)
    }

    private static func serverError(message: String) -> TransmissionErrorPresentation {
        TransmissionErrorPresentation(title: "Server Error", message: message)
    }

    private static func operationFailed(message: String) -> TransmissionErrorPresentation {
        TransmissionErrorPresentation(title: "Operation Failed", message: message)
    }

    private static func httpStatusMessage(code: Int, body: String?) -> String {
        if let body, !body.isEmpty {
            return body
        }

        return "Server returned HTTP \(code)."
    }
}

enum TransmissionUserFacingError {
    static func presentation(for error: Error) -> TransmissionErrorPresentation? {
        let transmissionError = TransmissionErrorResolver.transmissionError(from: error)
        if case .cancelled = transmissionError {
            return nil
        }

        return TransmissionErrorPresenter.presentation(for: transmissionError)
    }

    static func message(for error: Error) -> String? {
        presentation(for: error)?.message
    }
}
