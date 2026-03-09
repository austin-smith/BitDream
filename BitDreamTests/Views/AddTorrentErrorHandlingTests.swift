import XCTest
@testable import BitDream

final class AddTorrentErrorHandlingTests: XCTestCase {
    func testBatchFailureReturnsNilForCancellation() {
        XCTAssertNil(addTorrentBatchFailure(fileName: "Example.torrent", error: TransmissionError.cancelled))
    }

    func testBatchFailureUsesSharedTransmissionMessage() {
        let failure = addTorrentBatchFailure(fileName: "Example.torrent", error: TransmissionError.unauthorized)

        XCTAssertEqual(
            failure,
            AddTorrentBatchFailure(
                fileName: "Example.torrent",
                message: "Authentication failed. Please check your server credentials."
            )
        )
    }

    func testBatchFailureSummaryFormatsSingleFailure() {
        let summary = addTorrentBatchFailureSummary([
            AddTorrentBatchFailure(fileName: "Example.torrent", message: "Authentication failed. Please check your server credentials.")
        ])

        XCTAssertEqual(
            summary,
            "Failed to add 'Example.torrent': Authentication failed. Please check your server credentials."
        )
    }
}
