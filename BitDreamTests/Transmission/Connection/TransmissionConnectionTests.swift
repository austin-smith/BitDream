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

    func testRemoveTorrentsUsesSingleBatchPayload() async throws {
        let sender = QueueSender(steps: [
            .http(statusCode: 200, body: successEmptyBody)
        ])
        let connection = TransmissionConnection(
            endpoint: try makeEndpoint(),
            auth: makeAuth(),
            transport: TransmissionTransport(sender: sender)
        )

        try await connection.removeTorrents(ids: [11, 12], deleteLocalData: true)

        let requests = await sender.capturedRequests()
        XCTAssertEqual(try requestMethod(from: requests[0].asURLRequest()), "torrent-remove")
        let arguments = try requestArguments(from: requests[0])
        XCTAssertEqual(arguments["ids"] as? [Int], [11, 12])
        XCTAssertEqual(arguments["delete-local-data"] as? Bool, true)
    }

    func testSetTorrentPriorityUsesBandwidthPriority() async throws {
        let sender = QueueSender(steps: [
            .http(statusCode: 200, body: successEmptyBody)
        ])
        let connection = TransmissionConnection(
            endpoint: try makeEndpoint(),
            auth: makeAuth(),
            transport: TransmissionTransport(sender: sender)
        )

        try await connection.setTorrentPriority(ids: [42], priority: .high)

        let requests = await sender.capturedRequests()
        XCTAssertEqual(try requestMethod(from: requests[0].asURLRequest()), "torrent-set")
        let arguments = try requestArguments(from: requests[0])
        XCTAssertEqual(arguments["ids"] as? [Int], [42])
        XCTAssertEqual(arguments["bandwidthPriority"] as? Int, TorrentPriority.high.rawValue)
    }

    func testQueueMoveUsesSingleBatchRequest() async throws {
        let sender = QueueSender(steps: [
            .http(statusCode: 200, body: successEmptyBody)
        ])
        let connection = TransmissionConnection(
            endpoint: try makeEndpoint(),
            auth: makeAuth(),
            transport: TransmissionTransport(sender: sender)
        )

        try await connection.queueMove(.bottom, ids: [3, 4, 5])

        let requests = await sender.capturedRequests()
        XCTAssertEqual(try requestMethod(from: requests[0].asURLRequest()), "queue-move-bottom")
        let arguments = try requestArguments(from: requests[0])
        XCTAssertEqual(arguments["ids"] as? [Int], [3, 4, 5])
    }

    func testRenameTorrentPathDecodesArguments() async throws {
        let sender = QueueSender(steps: [
            .http(
                statusCode: 200,
                body: #"{"result":"success","arguments":{"path":"Old Name","name":"New Name","id":42}}"#
            )
        ])
        let connection = TransmissionConnection(
            endpoint: try makeEndpoint(),
            auth: makeAuth(),
            transport: TransmissionTransport(sender: sender)
        )

        let response = try await connection.renameTorrentPath(
            torrentID: 42,
            path: "Old Name",
            newName: "New Name"
        )

        XCTAssertEqual(response.id, 42)
        XCTAssertEqual(response.path, "Old Name")
        XCTAssertEqual(response.name, "New Name")
    }

    func testMutationMethodsPropagateTransmissionErrors() async throws {
        let sender = QueueSender(steps: [
            .http(statusCode: 200, body: #"{"result":"queue move failed","arguments":{}}"#)
        ])
        let connection = TransmissionConnection(
            endpoint: try makeEndpoint(),
            auth: makeAuth(),
            transport: TransmissionTransport(sender: sender)
        )

        await assertThrowsTransmissionError(.rpcFailure(expectedResult: "queue move failed")) {
            try await connection.queueMove(.top, ids: [1, 2])
        }
    }
}

private extension CapturedRequest {
    func asURLRequest() -> URLRequest {
        var request = URLRequest(url: url ?? URL(string: "https://example.com")!)
        request.httpMethod = httpMethod
        request.httpBody = body
        return request
    }
}

private func requestArguments(from request: CapturedRequest) throws -> [String: Any] {
    let body = try XCTUnwrap(request.body)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    return try XCTUnwrap(object["arguments"] as? [String: Any])
}
