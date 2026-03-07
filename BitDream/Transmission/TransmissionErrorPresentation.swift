import Foundation

struct TransmissionErrorPresentation: Equatable, Sendable {
    let title: String?
    let message: String
}

enum TransmissionErrorPresenter {
    static func presentation(for error: TransmissionError) -> TransmissionErrorPresentation {
        switch error {
        case .invalidEndpointConfiguration:
            return connectionError(message: "Connection error. Please check your server settings.")
        case .unauthorized:
            return authenticationFailed(message: "Authentication failed. Please check your server credentials.")
        case .transport(let underlyingDescription):
            return connectionError(message: underlyingDescription)
        case .timeout:
            return connectionTimedOut(message: "The request timed out.")
        case .cancelled:
            return requestCancelled(message: "The request was cancelled.")
        case .httpStatus(let code, let body):
            return serverError(message: httpStatusMessage(code: code, body: body))
        case .rpcFailure(let result):
            return operationFailed(message: result)
        case .invalidResponse:
            return serverError(message: "The server returned an invalid response.")
        case .decoding:
            return serverError(message: "Failed to decode the server response.")
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

struct TransmissionLegacyCompatibilityError: LocalizedError, Sendable {
    let transmissionError: TransmissionError

    var errorDescription: String? {
        TransmissionErrorPresenter.presentation(for: transmissionError).message
    }
}

enum TransmissionLegacyCompatibility {
    static func response(from error: Error) -> TransmissionResponse {
        response(from: transmissionError(from: error))
    }

    static func response(from error: TransmissionError) -> TransmissionResponse {
        switch error {
        case .unauthorized:
            return .unauthorized
        case .invalidEndpointConfiguration, .transport, .timeout:
            return .configError
        case .rpcFailure, .httpStatus, .invalidResponse, .decoding, .cancelled:
            return .failed
        }
    }

    static func localizedError(from error: Error) -> Error {
        TransmissionLegacyCompatibilityError(transmissionError: transmissionError(from: error))
    }

    static func presentation(for response: TransmissionResponse) -> TransmissionErrorPresentation? {
        switch response {
        case .success:
            return nil
        case .unauthorized:
            return TransmissionErrorPresenter.presentation(for: .unauthorized)
        case .configError:
            return TransmissionErrorPresenter.presentation(for: .invalidEndpointConfiguration)
        case .failed:
            return TransmissionErrorPresentation(
                title: "Operation Failed",
                message: "Operation failed. Please try again."
            )
        }
    }

    static func transmissionError(from error: Error) -> TransmissionError {
        if let compatibilityError = error as? TransmissionLegacyCompatibilityError {
            return compatibilityError.transmissionError
        }

        if let transmissionError = error as? TransmissionError {
            return transmissionError
        }

        if let transportFailure = error as? TransmissionTransportFailure {
            return transportFailure.transmissionError
        }

        return .transport(underlyingDescription: error.localizedDescription)
    }
}
