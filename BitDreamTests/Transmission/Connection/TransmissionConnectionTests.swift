import XCTest
@testable import BitDream

final class TransmissionConnectionTests: XCTestCase {
    func testConcurrentRequestsRetryWithSharedRefreshedToken() async throws {
        let sender = ConcurrentRefreshSender()
        let connection = TransmissionConnection(
            endpoint: try makeEndpoint(),
            auth: makeAuth(),
            transport: TransmissionTransport(sender: sender)
        )

        async let first: TransmissionRPCEnvelope<SessionStats> = connection.sendEnvelope(
            method: "session-stats",
            arguments: EmptyArguments(),
            responseType: SessionStats.self
        )
        async let second: TransmissionRPCEnvelope<SessionStats> = connection.sendEnvelope(
            method: "session-stats",
            arguments: EmptyArguments(),
            responseType: SessionStats.self
        )

        _ = try await (first, second)
        let sharedToken = await connection.currentSessionToken()
        XCTAssertEqual(sharedToken, "shared-token")

        let requests = await sender.capturedRequests()
        XCTAssertTrue((3...4).contains(requests.count))
        XCTAssertTrue((1...2).contains(requests.filter { $0.sessionToken == nil }.count))
        XCTAssertEqual(requests.filter { $0.sessionToken == "shared-token" }.count, 2)
        XCTAssertEqual(
            requests.filter { $0.sessionToken == nil || $0.sessionToken == "shared-token" }.count,
            requests.count
        )
    }

    func testConcurrentUnauthorizedDoesNotLeaveStaleTokenBehind() async throws {
        let sender = ConcurrentUnauthorizedRefreshSender()
        let connection = TransmissionConnection(
            endpoint: try makeEndpoint(),
            auth: makeAuth(),
            transport: TransmissionTransport(sender: sender)
        )
        await connection.setSessionTokenForTesting("stale-token")

        async let unauthorizedAttempt = requestOutcome(connection: connection)
        async let refreshedAttempt = requestOutcome(connection: connection)

        let outcomes = await [unauthorizedAttempt, refreshedAttempt]
        XCTAssertEqual(outcomes.filter { $0 == .success }.count, 1)
        XCTAssertEqual(outcomes.filter { $0 == .unauthorized }.count, 1)

        _ = try await connection.sendEnvelope(
            method: "session-stats",
            arguments: EmptyArguments(),
            responseType: SessionStats.self
        )
        let refreshedToken = await connection.currentSessionToken()
        XCTAssertEqual(refreshedToken, "new-token")

        let requests = await sender.capturedRequests()
        XCTAssertEqual(requests.filter { $0.sessionToken == "stale-token" }.count, 2)
        XCTAssertEqual(requests.filter { $0.sessionToken == "new-token" }.count, 2)
    }

    func testUnauthorizedClearsMatchingCachedTokenBeforeNextRequest() async throws {
        let sender = QueueSender(steps: [
            .http(statusCode: 401, body: ""),
            .http(statusCode: 200, body: successStatsBody)
        ])
        let connection = TransmissionConnection(
            endpoint: try makeEndpoint(),
            auth: makeAuth(),
            transport: TransmissionTransport(sender: sender)
        )
        await connection.setSessionTokenForTesting("stale-token")

        await assertThrowsTransmissionError(.unauthorized) {
            _ = try await connection.sendEnvelope(
                method: "session-stats",
                arguments: EmptyArguments(),
                responseType: SessionStats.self
            )
        }

        _ = try await connection.sendEnvelope(
            method: "session-stats",
            arguments: EmptyArguments(),
            responseType: SessionStats.self
        )

        let requests = await sender.capturedRequests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].sessionToken, "stale-token")
        XCTAssertNil(requests[1].sessionToken)
        let currentToken = await connection.currentSessionToken()
        XCTAssertNil(currentToken)
    }

    func testTorrentAddUsesTypedOutcomeThroughConnection() async throws {
        let sender = QueueSender(steps: [
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
        let connection = TransmissionConnection(
            endpoint: try makeEndpoint(),
            auth: makeAuth(),
            transport: TransmissionTransport(sender: sender)
        )

        let outcome = try await connection.sendTorrentAdd(arguments: ["filename": "magnet:?xt=urn:btih:test"])

        guard case .duplicate(let torrent) = outcome else {
            return XCTFail("Expected duplicate outcome")
        }

        XCTAssertEqual(torrent.id, 14)
        XCTAssertEqual(torrent.name, "Ubuntu.iso")
    }
}
