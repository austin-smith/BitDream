import XCTest
@testable import BitDream

final class TransmissionConnectionSnapshotTests: XCTestCase {
    func testFetchPollingSnapshotUsesSummaryFieldsAndSessionStats() async throws {
        let sender = MethodQueueSender(stepsByMethod: [
            "session-stats": [
                .http(statusCode: 200, body: successStatsBody)
            ],
            "torrent-get": [
                .http(statusCode: 200, body: try loadTransmissionFixture(named: "torrent-get.response.json"))
            ]
        ])
        let connection = TransmissionConnection(
            endpoint: try makeEndpoint(),
            auth: makeAuth(),
            transport: TransmissionTransport(sender: sender)
        )

        let snapshot = try await connection.fetchPollingSnapshot()

        XCTAssertEqual(snapshot.sessionStats.torrentCount, 4)
        XCTAssertFalse(snapshot.torrents.isEmpty)

        let requests = await sender.capturedRequests()
        XCTAssertEqual(requests.count, 2)
        let torrentRequest = try request(named: "torrent-get", in: requests)
        XCTAssertEqual(
            try capturedRequestFields(torrentRequest),
            TransmissionTorrentQuerySpec.torrentSummary.fields
        )
    }

    func testFetchAppRefreshSnapshotIncludesSessionSettings() async throws {
        let sender = MethodQueueSender(stepsByMethod: [
            "session-stats": [
                .http(statusCode: 200, body: successStatsBody)
            ],
            "torrent-get": [
                .http(statusCode: 200, body: try loadTransmissionFixture(named: "torrent-get.response.json"))
            ],
            "session-get": [
                .http(statusCode: 200, body: try loadTransmissionFixture(named: "session-get.response.json"))
            ]
        ])
        let connection = TransmissionConnection(
            endpoint: try makeEndpoint(),
            auth: makeAuth(),
            transport: TransmissionTransport(sender: sender)
        )

        let snapshot = try await connection.fetchAppRefreshSnapshot()

        XCTAssertEqual(snapshot.polling.sessionStats.torrentCount, 4)
        XCTAssertFalse(snapshot.polling.torrents.isEmpty)
        switch snapshot.sessionSettingsResult {
        case .success(let sessionSettings):
            XCTAssertFalse(sessionSettings.downloadDir.isEmpty)
        case .failure(let error):
            XCTFail("Expected session settings success, got \(error)")
        }

        let requests = await sender.capturedRequests()
        XCTAssertEqual(requests.count, 3)
        let sessionRequest = try request(named: "session-get", in: requests)
        XCTAssertEqual(
            try capturedRequestFields(sessionRequest),
            TransmissionSessionQuerySpec.sessionSettings.fields
        )
    }

    func testFetchAppRefreshSnapshotPreservesPollingWhenSessionSettingsFail() async throws {
        let sender = MethodQueueSender(stepsByMethod: [
            "session-stats": [
                .http(statusCode: 200, body: successStatsBody)
            ],
            "torrent-get": [
                .http(statusCode: 200, body: try loadTransmissionFixture(named: "torrent-get.response.json"))
            ],
            "session-get": [
                .error(TestError.offline)
            ]
        ])
        let connection = TransmissionConnection(
            endpoint: try makeEndpoint(),
            auth: makeAuth(),
            transport: TransmissionTransport(sender: sender)
        )

        let snapshot = try await connection.fetchAppRefreshSnapshot()

        XCTAssertEqual(snapshot.polling.sessionStats.torrentCount, 4)
        XCTAssertFalse(snapshot.polling.torrents.isEmpty)

        switch snapshot.sessionSettingsResult {
        case .success:
            XCTFail("Expected session settings failure to be preserved in the snapshot")
        case .failure(let error):
            if case .transport = error {
                break
            }
            XCTFail("Unexpected session settings error: \(error)")
        }
    }

    func testFetchWidgetRefreshSnapshotUsesNamedWidgetFields() async throws {
        let sender = MethodQueueSender(stepsByMethod: [
            "session-stats": [
                .http(statusCode: 200, body: successStatsBody)
            ],
            "torrent-get": [
                .http(statusCode: 200, body: try loadTransmissionFixture(named: "torrent-get.response.json"))
            ]
        ])
        let connection = TransmissionConnection(
            endpoint: try makeEndpoint(),
            auth: makeAuth(),
            transport: TransmissionTransport(sender: sender)
        )

        _ = try await connection.fetchWidgetRefreshSnapshot()

        let requests = await sender.capturedRequests()
        let torrentRequest = try request(named: "torrent-get", in: requests)
        XCTAssertEqual(
            try capturedRequestFields(torrentRequest),
            TransmissionTorrentQuerySpec.widgetSummary.fields
        )
    }

    func testFetchWidgetRefreshSnapshotPreservesStatsWhenTorrentSummaryFails() async throws {
        let sender = MethodQueueSender(stepsByMethod: [
            "session-stats": [
                .http(statusCode: 200, body: successStatsBody)
            ],
            "torrent-get": [
                .error(TestError.offline)
            ]
        ])
        let connection = TransmissionConnection(
            endpoint: try makeEndpoint(),
            auth: makeAuth(),
            transport: TransmissionTransport(sender: sender)
        )

        let snapshot = try await connection.fetchWidgetRefreshSnapshot()

        XCTAssertEqual(snapshot.sessionStats.torrentCount, 4)
        XCTAssertTrue(snapshot.torrents.isEmpty)
        XCTAssertNotNil(snapshot.torrentSummaryError)
    }

    func testSnapshotMethodsPropagateTransmissionErrors() async throws {
        let sender = MethodQueueSender(stepsByMethod: [
            "session-stats": [
                .http(statusCode: 200, body: #"{"result":"server busy","arguments":{}}"#)
            ]
        ])
        let connection = TransmissionConnection(
            endpoint: try makeEndpoint(),
            auth: makeAuth(),
            transport: TransmissionTransport(sender: sender)
        )

        await assertThrowsTransmissionError(.rpcFailure(expectedResult: "server busy")) {
            _ = try await connection.fetchPollingSnapshot()
        }
    }

    func testFetchAppRefreshSnapshotStillThrowsWhenPollingFails() async throws {
        let sender = MethodQueueSender(stepsByMethod: [
            "session-stats": [
                .http(statusCode: 200, body: #"{"result":"server busy","arguments":{}}"#)
            ],
            "session-get": [
                .http(statusCode: 200, body: try loadTransmissionFixture(named: "session-get.response.json"))
            ]
        ])
        let connection = TransmissionConnection(
            endpoint: try makeEndpoint(),
            auth: makeAuth(),
            transport: TransmissionTransport(sender: sender)
        )

        await assertThrowsTransmissionError(.rpcFailure(expectedResult: "server busy")) {
            _ = try await connection.fetchAppRefreshSnapshot()
        }
    }
}

private func request(named expectedMethod: String, in requests: [CapturedRequest]) throws -> CapturedRequest {
    for request in requests where try capturedRequestMethod(request) == expectedMethod {
        return request
    }

    XCTFail("Missing request for method \(expectedMethod)")
    throw TestError.unexpectedRequest
}

private func capturedRequestMethod(_ request: CapturedRequest) throws -> String {
    let body = try XCTUnwrap(request.body)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    return try XCTUnwrap(object["method"] as? String)
}
