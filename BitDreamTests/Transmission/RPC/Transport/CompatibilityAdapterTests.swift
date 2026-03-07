import XCTest
@testable import BitDream

// TODO: Remove this suite when the temporary compatibility adapter is deleted.
final class CompatibilityAdapterTests: XCTestCase {
    func testStatusRequestMapsRPCFailureToFailed() async {
        let adapter = makeAdapter(steps: [
            .http(statusCode: 200, body: #"{"result":"queue move failed","arguments":{}}"#)
        ])

        let response = await adapter.performStatusRequest(
            method: "queue-move-top",
            args: EmptyArguments(),
            config: makeConfig(),
            auth: makeAuth()
        )

        XCTAssertEqual(response, .failed)
    }

    func testStatusRequestMapsUnauthorizedToUnauthorized() async {
        let adapter = makeAdapter(steps: [
            .http(statusCode: 401, body: "")
        ])

        let response = await adapter.performStatusRequest(
            method: "torrent-stop",
            args: EmptyArguments(),
            config: makeConfig(),
            auth: makeAuth()
        )

        XCTAssertEqual(response, .unauthorized)
    }

    func testStatusRequestMapsInvalidEndpointToConfigError() async {
        var config = makeConfig()
        config.host = "bad host"

        let adapter = makeAdapter(steps: [])
        let response = await adapter.performStatusRequest(
            method: "torrent-stop",
            args: EmptyArguments(),
            config: config,
            auth: makeAuth()
        )

        XCTAssertEqual(response, .configError)
    }

    func testStatusRequestMapsTimeoutToConfigError() async {
        let adapter = makeAdapter(steps: [
            .error(URLError(.timedOut))
        ])

        let response = await adapter.performStatusRequest(
            method: "torrent-stop",
            args: EmptyArguments(),
            config: makeConfig(),
            auth: makeAuth()
        )

        XCTAssertEqual(response, .configError)
    }

    func testStatusRequestInherits409RetryBehaviorFromTransport() async {
        let adapter = makeAdapter(steps: [
            .http(statusCode: 409, body: "", headers: [transmissionSessionTokenHeader: "fresh-token"]),
            .http(statusCode: 200, body: successEmptyBody)
        ])

        let response = await adapter.performStatusRequest(
            method: "torrent-stop",
            args: EmptyArguments(),
            config: makeConfig(),
            auth: makeAuth()
        )

        XCTAssertEqual(response, .success)
    }

    func testTorrentAddAddedOutcomeReturnsSuccessAndID() async {
        let adapter = makeAdapter(steps: [
            .http(
                statusCode: 200,
                body: """
                {
                  "arguments": {
                    "torrent-added": {
                      "hashString": "abc",
                      "id": 12,
                      "name": "Ubuntu.iso"
                    }
                  },
                  "result": "success"
                }
                """
            )
        ])

        let result = await adapter.performTorrentAddRequest(
            args: ["filename": "magnet:?xt=urn:btih:test"],
            config: makeConfig(),
            auth: makeAuth()
        )

        XCTAssertEqual(result.response, .success)
        XCTAssertEqual(result.transferId, 12)
    }

    func testTorrentAddDuplicateOutcomeReturnsSuccessAndID() async {
        let adapter = makeAdapter(steps: [
            .http(
                statusCode: 200,
                body: """
                {
                  "arguments": {
                    "torrent-duplicate": {
                      "hashString": "abc",
                      "id": 14,
                      "name": "Ubuntu.iso"
                    }
                  },
                  "result": "success"
                }
                """
            )
        ])

        let result = await adapter.performTorrentAddRequest(
            args: ["filename": "magnet:?xt=urn:btih:test"],
            config: makeConfig(),
            auth: makeAuth()
        )

        XCTAssertEqual(result.response, .success)
        XCTAssertEqual(result.transferId, 14)
    }

    func testTorrentAddMalformedSuccessPayloadFails() async {
        let adapter = makeAdapter(steps: [
            .http(statusCode: 200, body: #"{"result":"success","arguments":{}}"#)
        ])

        let result = await adapter.performTorrentAddRequest(
            args: ["filename": "magnet:?xt=urn:btih:test"],
            config: makeConfig(),
            auth: makeAuth()
        )

        XCTAssertEqual(result.response, .failed)
        XCTAssertEqual(result.transferId, 0)
    }

    func testDataRequestReturnsDecodedArguments() async throws {
        let adapter = makeAdapter(steps: [
            .http(statusCode: 200, body: successStatsBody)
        ])

        let result = await adapter.performDataRequest(
            method: "session-stats",
            args: EmptyArguments(),
            config: makeConfig(),
            auth: makeAuth(),
            responseType: SessionStats.self
        )

        switch result {
        case .success(let stats):
            XCTAssertEqual(stats.torrentCount, 4)
        case .failure(let error):
            XCTFail("Expected success, got \(error)")
        }
    }

    func testDataRequestWrapsFailuresInCompatibilityError() async {
        let adapter = makeAdapter(steps: [
            .http(statusCode: 200, body: #"{"result":"server busy","arguments":{}}"#)
        ])

        let result = await adapter.performDataRequest(
            method: "session-stats",
            args: EmptyArguments(),
            config: makeConfig(),
            auth: makeAuth(),
            responseType: SessionStats.self
        )

        switch result {
        case .success:
            XCTFail("Expected failure")
        case .failure(let error):
            XCTAssertTrue(error is TransmissionLegacyCompatibilityError)
            XCTAssertFalse(error is TransmissionError)
            XCTAssertEqual(error.localizedDescription, "server busy")
        }
    }

    private func makeAdapter(steps: [QueueSender.Step]) -> TransmissionLegacyAdapter {
        TransmissionLegacyAdapter(
            transport: TransmissionRPCTransport(
                sender: QueueSender(steps: steps),
                tokenStore: TransmissionSessionTokenStore()
            )
        )
    }
}

private let successEmptyBody = #"{"result":"success","arguments":{}}"#
