import XCTest
@testable import BitDream

final class TransmissionErrorPresentationTests: XCTestCase {
    func testPresentationMapsEveryTransmissionErrorCase() {
        XCTAssertEqual(
            TransmissionErrorPresenter.presentation(for: .invalidEndpointConfiguration),
            TransmissionErrorPresentation(
                title: "Connection Error",
                message: "Connection error. Please check your server settings."
            )
        )
        XCTAssertEqual(
            TransmissionErrorPresenter.presentation(for: .unauthorized),
            TransmissionErrorPresentation(
                title: "Authentication Failed",
                message: "Authentication failed. Please check your server credentials."
            )
        )
        XCTAssertEqual(
            TransmissionErrorPresenter.presentation(for: .transport(underlyingDescription: "Offline")),
            TransmissionErrorPresentation(title: "Connection Error", message: "Offline")
        )
        XCTAssertEqual(
            TransmissionErrorPresenter.presentation(for: .timeout),
            TransmissionErrorPresentation(title: "Connection Timed Out", message: "The request timed out.")
        )
        XCTAssertEqual(
            TransmissionErrorPresenter.presentation(for: .cancelled),
            TransmissionErrorPresentation(title: "Request Cancelled", message: "The request was cancelled.")
        )
        XCTAssertEqual(
            TransmissionErrorPresenter.presentation(for: .httpStatus(code: 500, body: nil)),
            TransmissionErrorPresentation(title: "Server Error", message: "Server returned HTTP 500.")
        )
        XCTAssertEqual(
            TransmissionErrorPresenter.presentation(for: .rpcFailure(result: "busy")),
            TransmissionErrorPresentation(title: "Operation Failed", message: "busy")
        )
        XCTAssertEqual(
            TransmissionErrorPresenter.presentation(for: .invalidResponse),
            TransmissionErrorPresentation(title: "Server Error", message: "The server returned an invalid response.")
        )
        XCTAssertEqual(
            TransmissionErrorPresenter.presentation(for: .decoding(underlyingDescription: "bad json")),
            TransmissionErrorPresentation(title: "Server Error", message: "Failed to decode the server response.")
        )
    }

    func testLegacyResponseMappingMatchesCompatibilityContract() {
        XCTAssertEqual(TransmissionLegacyCompatibility.response(from: .unauthorized), .unauthorized)
        XCTAssertEqual(TransmissionLegacyCompatibility.response(from: .invalidEndpointConfiguration), .configError)
        XCTAssertEqual(TransmissionLegacyCompatibility.response(from: .timeout), .configError)
        XCTAssertEqual(TransmissionLegacyCompatibility.response(from: .rpcFailure(result: "busy")), .failed)
        XCTAssertEqual(TransmissionLegacyCompatibility.response(from: .httpStatus(code: 500, body: nil)), .failed)
        XCTAssertEqual(TransmissionLegacyCompatibility.response(from: .invalidResponse), .failed)
        XCTAssertEqual(TransmissionLegacyCompatibility.response(from: .decoding(underlyingDescription: "bad json")), .failed)
    }

    func testLegacyLocalizedErrorUsesPresentationMessage() {
        let error = TransmissionLegacyCompatibility.localizedError(
            from: TransmissionError.rpcFailure(result: "server busy")
        )

        XCTAssertTrue(error is TransmissionLegacyCompatibilityError)
        XCTAssertEqual(error.localizedDescription, "server busy")
    }

    func testLegacyResponsePresentationRemainsStable() {
        XCTAssertNil(TransmissionLegacyCompatibility.presentation(for: .success))
        XCTAssertEqual(
            TransmissionLegacyCompatibility.presentation(for: .unauthorized),
            TransmissionErrorPresentation(
                title: "Authentication Failed",
                message: "Authentication failed. Please check your server credentials."
            )
        )
        XCTAssertEqual(
            TransmissionLegacyCompatibility.presentation(for: .configError),
            TransmissionErrorPresentation(
                title: "Connection Error",
                message: "Connection error. Please check your server settings."
            )
        )
        XCTAssertEqual(
            TransmissionLegacyCompatibility.presentation(for: .failed),
            TransmissionErrorPresentation(
                title: "Operation Failed",
                message: "Operation failed. Please try again."
            )
        )
    }
}
