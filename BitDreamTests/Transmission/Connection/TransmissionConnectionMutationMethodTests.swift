import XCTest
@testable import BitDream

final class TransmissionConnectionMutationTests: XCTestCase {
    func testPauseTorrentsUsesStopMethod() async throws {
        let sender = QueueSender(steps: [
            .http(statusCode: 200, body: successEmptyBody)
        ])
        let connection = try makeConnection(sender: sender)

        try await connection.pauseTorrents(ids: [7, 8])

        try await assertCapturedRequest(
            sender: sender,
            method: "torrent-stop",
            expectedArguments: ["ids": [7, 8]]
        )
    }

    func testResumeTorrentsUsesStartMethod() async throws {
        let sender = QueueSender(steps: [
            .http(statusCode: 200, body: successEmptyBody)
        ])
        let connection = try makeConnection(sender: sender)

        try await connection.resumeTorrents(ids: [9])

        try await assertCapturedRequest(
            sender: sender,
            method: "torrent-start",
            expectedArguments: ["ids": [9]]
        )
    }

    func testPauseAllTorrentsUsesStopMethodWithoutArguments() async throws {
        let sender = QueueSender(steps: [
            .http(statusCode: 200, body: successEmptyBody)
        ])
        let connection = try makeConnection(sender: sender)

        try await connection.pauseAllTorrents()

        try await assertCapturedRequest(
            sender: sender,
            method: "torrent-stop",
            expectedArguments: [:]
        )
    }

    func testResumeAllTorrentsUsesStartMethodWithoutArguments() async throws {
        let sender = QueueSender(steps: [
            .http(statusCode: 200, body: successEmptyBody)
        ])
        let connection = try makeConnection(sender: sender)

        try await connection.resumeAllTorrents()

        try await assertCapturedRequest(
            sender: sender,
            method: "torrent-start",
            expectedArguments: [:]
        )
    }

    func testStartTorrentsNowUsesStartNowMethod() async throws {
        let sender = QueueSender(steps: [
            .http(statusCode: 200, body: successEmptyBody)
        ])
        let connection = try makeConnection(sender: sender)

        try await connection.startTorrentsNow(ids: [3, 4])

        try await assertCapturedRequest(
            sender: sender,
            method: "torrent-start-now",
            expectedArguments: ["ids": [3, 4]]
        )
    }

    func testReannounceTorrentsUsesReannounceMethod() async throws {
        let sender = QueueSender(steps: [
            .http(statusCode: 200, body: successEmptyBody)
        ])
        let connection = try makeConnection(sender: sender)

        try await connection.reannounceTorrents(ids: [12])

        try await assertCapturedRequest(
            sender: sender,
            method: "torrent-reannounce",
            expectedArguments: ["ids": [12]]
        )
    }

    func testVerifyTorrentsUsesVerifyMethod() async throws {
        let sender = QueueSender(steps: [
            .http(statusCode: 200, body: successEmptyBody)
        ])
        let connection = try makeConnection(sender: sender)

        try await connection.verifyTorrents(ids: [14, 15])

        try await assertCapturedRequest(
            sender: sender,
            method: "torrent-verify",
            expectedArguments: ["ids": [14, 15]]
        )
    }

    func testSetTorrentLocationUsesLocationPayload() async throws {
        let sender = QueueSender(steps: [
            .http(statusCode: 200, body: successEmptyBody)
        ])
        let connection = try makeConnection(sender: sender)

        try await connection.setTorrentLocation(ids: [5, 6], location: "/new/path", move: true)

        try await assertCapturedRequest(
            sender: sender,
            method: "torrent-set-location",
            expectedArguments: [
                "ids": [5, 6],
                "location": "/new/path",
                "move": true
            ]
        )
    }

    func testSetFileWantedStatusUsesWantedAndUnwantedKeys() async throws {
        let sender = QueueSender(steps: [
            .http(statusCode: 200, body: successEmptyBody),
            .http(statusCode: 200, body: successEmptyBody)
        ])
        let connection = try makeConnection(sender: sender)

        try await connection.setFileWantedStatus(torrentID: 42, fileIndices: [1, 3], wanted: true)
        try await connection.setFileWantedStatus(torrentID: 42, fileIndices: [2], wanted: false)

        let requests = await sender.capturedRequests()
        XCTAssertEqual(requests.count, 2)

        let wantedArguments = try requestArguments(from: requests[0])
        XCTAssertEqual(try requestMethod(from: requests[0].asURLRequest()), "torrent-set")
        XCTAssertEqual(wantedArguments["ids"] as? [Int], [42])
        XCTAssertEqual(wantedArguments["files-wanted"] as? [Int], [1, 3])
        XCTAssertNil(wantedArguments["files-unwanted"])

        let unwantedArguments = try requestArguments(from: requests[1])
        XCTAssertEqual(try requestMethod(from: requests[1].asURLRequest()), "torrent-set")
        XCTAssertEqual(unwantedArguments["ids"] as? [Int], [42])
        XCTAssertEqual(unwantedArguments["files-unwanted"] as? [Int], [2])
        XCTAssertNil(unwantedArguments["files-wanted"])
    }

    func testSetFilePriorityUsesExpectedPriorityKeys() async throws {
        let sender = QueueSender(steps: [
            .http(statusCode: 200, body: successEmptyBody),
            .http(statusCode: 200, body: successEmptyBody),
            .http(statusCode: 200, body: successEmptyBody)
        ])
        let connection = try makeConnection(sender: sender)

        try await connection.setFilePriority(torrentID: 11, fileIndices: [0], priority: .low)
        try await connection.setFilePriority(torrentID: 11, fileIndices: [1], priority: .normal)
        try await connection.setFilePriority(torrentID: 11, fileIndices: [2, 3], priority: .high)

        let requests = await sender.capturedRequests()
        XCTAssertEqual(requests.count, 3)

        let lowArguments = try requestArguments(from: requests[0])
        XCTAssertEqual(try requestMethod(from: requests[0].asURLRequest()), "torrent-set")
        XCTAssertEqual(lowArguments["ids"] as? [Int], [11])
        XCTAssertEqual(lowArguments["priority-low"] as? [Int], [0])

        let normalArguments = try requestArguments(from: requests[1])
        XCTAssertEqual(try requestMethod(from: requests[1].asURLRequest()), "torrent-set")
        XCTAssertEqual(normalArguments["ids"] as? [Int], [11])
        XCTAssertEqual(normalArguments["priority-normal"] as? [Int], [1])

        let highArguments = try requestArguments(from: requests[2])
        XCTAssertEqual(try requestMethod(from: requests[2].asURLRequest()), "torrent-set")
        XCTAssertEqual(highArguments["ids"] as? [Int], [11])
        XCTAssertEqual(highArguments["priority-high"] as? [Int], [2, 3])
    }
}

private extension TransmissionConnectionMutationTests {
    func makeConnection(sender: QueueSender) throws -> TransmissionConnection {
        TransmissionConnection(
            endpoint: try makeEndpoint(),
            auth: makeAuth(),
            transport: TransmissionTransport(sender: sender)
        )
    }

    func assertCapturedRequest(
        sender: QueueSender,
        method: String,
        expectedArguments: [String: Any],
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let requests = await sender.capturedRequests()
        XCTAssertEqual(requests.count, 1, file: file, line: line)
        XCTAssertEqual(try requestMethod(from: requests[0].asURLRequest()), method, file: file, line: line)

        let arguments = try requestArguments(from: requests[0])
        XCTAssertEqual(arguments as NSDictionary, expectedArguments as NSDictionary, file: file, line: line)
    }
}
