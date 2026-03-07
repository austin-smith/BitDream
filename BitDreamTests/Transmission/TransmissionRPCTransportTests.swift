import XCTest
@testable import BitDream

final class TransmissionRPCTransportTests: XCTestCase {
    func testSendEnvelopeDecodesSuccessfulResponseAndPreservesTag() async throws {
        let sender = QueueSender(steps: [
            .http(
                statusCode: 200,
                body: """
                {
                  "arguments": {
                    "activeTorrentCount": 1,
                    "downloadSpeed": 2,
                    "pausedTorrentCount": 3,
                    "torrentCount": 4,
                    "uploadSpeed": 5
                  },
                  "result": "success",
                  "tag": 42
                }
                """
            ),
        ])
        let transport = TransmissionRPCTransport(sender: sender, tokenStore: TransmissionSessionTokenStore())

        let envelope = try await transport.sendEnvelope(
            method: "session-stats",
            arguments: EmptyArguments(),
            config: makeConfig(),
            auth: makeAuth(),
            responseType: SessionStats.self
        )

        XCTAssertEqual(envelope.tag, 42)
        XCTAssertEqual(try envelope.requireArguments().torrentCount, 4)
    }

    func testSendEnvelopeMapsRPCFailureResultToTransmissionError() async {
        let sender = QueueSender(steps: [
            .http(statusCode: 200, body: #"{"result":"duplicate torrent","arguments":{}}"#),
        ])
        let transport = TransmissionRPCTransport(sender: sender, tokenStore: TransmissionSessionTokenStore())

        await assertThrowsTransmissionError(
            .rpcFailure(expectedResult: "duplicate torrent")
        ) {
            _ = try await transport.sendEnvelope(
                method: "torrent-add",
                arguments: ["filename": "magnet:?xt=urn:btih:test"] as StringArguments,
                config: makeConfig(),
                auth: makeAuth(),
                responseType: [String: TorrentAddResponseArgs].self
            )
        }
    }

    func testSendEnvelopeMapsMissingResultToInvalidResponse() async {
        let sender = QueueSender(steps: [
            .http(statusCode: 200, body: #"{"arguments":{"torrentCount":4}}"#),
        ])
        let transport = TransmissionRPCTransport(sender: sender, tokenStore: TransmissionSessionTokenStore())

        await assertThrowsTransmissionError(.invalidResponse) {
            _ = try await transport.sendEnvelope(
                method: "session-stats",
                arguments: EmptyArguments(),
                config: makeConfig(),
                auth: makeAuth(),
                responseType: SessionStats.self
            )
        }
    }

    func testSendEnvelopeMapsMalformedArgumentsToDecodingError() async {
        let sender = QueueSender(steps: [
            .http(
                statusCode: 200,
                body: """
                {
                  "arguments": {
                    "activeTorrentCount": "wrong"
                  },
                  "result": "success"
                }
                """
            ),
        ])
        let transport = TransmissionRPCTransport(sender: sender, tokenStore: TransmissionSessionTokenStore())

        await assertThrowsTransmissionError(.decoding) {
            _ = try await transport.sendEnvelope(
                method: "session-stats",
                arguments: EmptyArguments(),
                config: makeConfig(),
                auth: makeAuth(),
                responseType: SessionStats.self
            )
        }
    }

    func testSendRequiredArgumentsMapsMissingArgumentsToInvalidResponse() async {
        let sender = QueueSender(steps: [
            .http(statusCode: 200, body: #"{"result":"success"}"#),
        ])
        let transport = TransmissionRPCTransport(sender: sender, tokenStore: TransmissionSessionTokenStore())

        await assertThrowsTransmissionError(.invalidResponse) {
            _ = try await transport.sendRequiredArguments(
                method: "session-stats",
                arguments: EmptyArguments(),
                config: makeConfig(),
                auth: makeAuth(),
                responseType: SessionStats.self
            )
        }
    }

    func testSendEnvelopeRetriesOnceAfter409AndPreservesRequestDetails() async throws {
        let sender = QueueSender(steps: [
            .http(statusCode: 409, body: "", headers: [transmissionSessionTokenHeader: "fresh-token"]),
            .http(statusCode: 200, body: successStatsBody),
        ])
        let transport = TransmissionRPCTransport(sender: sender, tokenStore: TransmissionSessionTokenStore())

        _ = try await transport.sendEnvelope(
            method: "session-stats",
            arguments: EmptyArguments(),
            config: makeConfig(),
            auth: makeAuth(),
            responseType: SessionStats.self
        )

        let requests = await sender.capturedRequests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].httpMethod, "POST")
        XCTAssertEqual(requests[0].url?.absoluteString, "http://example.com:9091/transmission/rpc")
        XCTAssertEqual(requests[0].body, requests[1].body)
        XCTAssertEqual(requests[0].authorizationHeader, requests[1].authorizationHeader)
        XCTAssertNil(requests[0].sessionToken)
        XCTAssertEqual(requests[1].sessionToken, "fresh-token")
        XCTAssertEqual(requests[1].contentType, "application/json")
    }

    func testSendEnvelopeMaps409WithoutTokenToInvalidResponse() async {
        let sender = QueueSender(steps: [
            .http(statusCode: 409, body: ""),
        ])
        let transport = TransmissionRPCTransport(sender: sender, tokenStore: TransmissionSessionTokenStore())

        await assertThrowsTransmissionError(.invalidResponse) {
            _ = try await transport.sendEnvelope(
                method: "session-stats",
                arguments: EmptyArguments(),
                config: makeConfig(),
                auth: makeAuth(),
                responseType: SessionStats.self
            )
        }
    }

    func testSendEnvelopeMapsRepeated409AfterRetryToHTTPStatus() async {
        let sender = QueueSender(steps: [
            .http(statusCode: 409, body: "", headers: [transmissionSessionTokenHeader: "fresh-token"]),
            .http(statusCode: 409, body: "still-conflicting"),
        ])
        let transport = TransmissionRPCTransport(sender: sender, tokenStore: TransmissionSessionTokenStore())

        await assertThrowsTransmissionError(.httpStatus(expectedCode: 409, expectedBody: "still-conflicting")) {
            _ = try await transport.sendEnvelope(
                method: "session-stats",
                arguments: EmptyArguments(),
                config: makeConfig(),
                auth: makeAuth(),
                responseType: SessionStats.self
            )
        }
    }

    func testUnauthorizedResponseClearsCachedTokenBeforeNextRequest() async throws {
        let tokenStore = TransmissionSessionTokenStore()
        await tokenStore.setToken("stale-token", for: "http://example.com:9091/transmission/rpc")

        let sender = QueueSender(steps: [
            .http(statusCode: 401, body: ""),
            .http(statusCode: 200, body: successStatsBody),
        ])
        let transport = TransmissionRPCTransport(sender: sender, tokenStore: tokenStore)

        await assertThrowsTransmissionError(.unauthorized) {
            _ = try await transport.sendEnvelope(
                method: "session-stats",
                arguments: EmptyArguments(),
                config: makeConfig(),
                auth: makeAuth(),
                responseType: SessionStats.self
            )
        }

        _ = try await transport.sendEnvelope(
            method: "session-stats",
            arguments: EmptyArguments(),
            config: makeConfig(),
            auth: makeAuth(),
            responseType: SessionStats.self
        )

        let requests = await sender.capturedRequests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].sessionToken, "stale-token")
        XCTAssertNil(requests[1].sessionToken)
    }

    func testTorrentAddAddedOutcomeIsSuccessful() async throws {
        let sender = QueueSender(steps: [
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
            ),
        ])
        let transport = TransmissionRPCTransport(sender: sender, tokenStore: TransmissionSessionTokenStore())

        let arguments = try await transport.sendRequiredArguments(
            method: "torrent-add",
            arguments: ["filename": "magnet:?xt=urn:btih:test"] as StringArguments,
            config: makeConfig(),
            auth: makeAuth(),
            responseType: [String: TorrentAddResponseArgs].self
        )
        let outcome = try TransmissionTorrentAddOutcome(arguments: arguments)

        guard case .added(let torrent) = outcome else {
            return XCTFail("Expected added outcome")
        }

        XCTAssertEqual(torrent.id, 12)
        XCTAssertEqual(torrent.name, "Ubuntu.iso")
    }

    func testTorrentAddDuplicateOutcomeIsSuccessful() async throws {
        let sender = QueueSender(steps: [
            .http(
                statusCode: 200,
                body: """
                {
                  "arguments": {
                    "torrent-duplicate": {
                      "hashString": "abc",
                      "id": 12,
                      "name": "Ubuntu.iso"
                    }
                  },
                  "result": "success"
                }
                """
            ),
        ])
        let transport = TransmissionRPCTransport(sender: sender, tokenStore: TransmissionSessionTokenStore())

        let arguments = try await transport.sendRequiredArguments(
            method: "torrent-add",
            arguments: ["filename": "magnet:?xt=urn:btih:test"] as StringArguments,
            config: makeConfig(),
            auth: makeAuth(),
            responseType: [String: TorrentAddResponseArgs].self
        )
        let outcome = try TransmissionTorrentAddOutcome(arguments: arguments)

        guard case .duplicate(let torrent) = outcome else {
            return XCTFail("Expected duplicate outcome")
        }

        XCTAssertEqual(torrent.id, 12)
        XCTAssertEqual(torrent.hashString, "abc")
    }

    func testTransportFailureMapsToTransportError() async {
        let sender = QueueSender(steps: [
            .error(TestError.offline),
        ])
        let transport = TransmissionRPCTransport(sender: sender, tokenStore: TransmissionSessionTokenStore())

        await assertThrowsTransmissionError(.transport) {
            _ = try await transport.sendEnvelope(
                method: "session-stats",
                arguments: EmptyArguments(),
                config: makeConfig(),
                auth: makeAuth(),
                responseType: SessionStats.self
            )
        }
    }

    func testTimedOutTransportFailureMapsToTimeout() async {
        let sender = QueueSender(steps: [
            .error(URLError(.timedOut)),
        ])
        let transport = TransmissionRPCTransport(sender: sender, tokenStore: TransmissionSessionTokenStore())

        await assertThrowsTransmissionError(.timeout) {
            _ = try await transport.sendEnvelope(
                method: "session-stats",
                arguments: EmptyArguments(),
                config: makeConfig(),
                auth: makeAuth(),
                responseType: SessionStats.self
            )
        }
    }

    func testCancelledTransportFailureMapsToCancelled() async {
        let sender = QueueSender(steps: [
            .error(CancellationError()),
        ])
        let transport = TransmissionRPCTransport(sender: sender, tokenStore: TransmissionSessionTokenStore())

        await assertThrowsTransmissionError(.cancelled) {
            _ = try await transport.sendEnvelope(
                method: "session-stats",
                arguments: EmptyArguments(),
                config: makeConfig(),
                auth: makeAuth(),
                responseType: SessionStats.self
            )
        }
    }

    func testHTTP500MapsToHTTPStatusError() async {
        let sender = QueueSender(steps: [
            .http(statusCode: 500, body: "server exploded"),
        ])
        let transport = TransmissionRPCTransport(sender: sender, tokenStore: TransmissionSessionTokenStore())

        await assertThrowsTransmissionError(.httpStatus(expectedCode: 500, expectedBody: "server exploded")) {
            _ = try await transport.sendEnvelope(
                method: "session-stats",
                arguments: EmptyArguments(),
                config: makeConfig(),
                auth: makeAuth(),
                responseType: SessionStats.self
            )
        }
    }

    func testConcurrentRequestsRetryWithSharedRefreshedToken() async throws {
        let sender = ConcurrentRefreshSender()
        let transport = TransmissionRPCTransport(sender: sender, tokenStore: TransmissionSessionTokenStore())

        async let first: TransmissionRPCEnvelope<SessionStats> = transport.sendEnvelope(
            method: "session-stats",
            arguments: EmptyArguments(),
            config: makeConfig(),
            auth: makeAuth(),
            responseType: SessionStats.self
        )
        async let second: TransmissionRPCEnvelope<SessionStats> = transport.sendEnvelope(
            method: "session-stats",
            arguments: EmptyArguments(),
            config: makeConfig(),
            auth: makeAuth(),
            responseType: SessionStats.self
        )

        _ = try await (first, second)

        let requests = await sender.capturedRequests()
        XCTAssertEqual(requests.count, 4)
        XCTAssertEqual(requests.filter { $0.sessionToken == nil }.count, 2)
        XCTAssertEqual(requests.filter { $0.sessionToken == "shared-token" }.count, 2)
    }

    func testConcurrentUnauthorizedDoesNotLeaveStaleTokenBehind() async throws {
        let tokenStore = TransmissionSessionTokenStore()
        await tokenStore.setToken("stale-token", for: "http://example.com:9091/transmission/rpc")

        let sender = ConcurrentUnauthorizedRefreshSender()
        let transport = TransmissionRPCTransport(sender: sender, tokenStore: tokenStore)

        async let unauthorizedAttempt = requestOutcome(transport: transport)
        async let refreshedAttempt = requestOutcome(transport: transport)

        let outcomes = await [unauthorizedAttempt, refreshedAttempt]
        XCTAssertEqual(outcomes.filter { $0 == .success }.count, 1)
        XCTAssertEqual(outcomes.filter { $0 == .unauthorized }.count, 1)

        _ = try await transport.sendEnvelope(
            method: "session-stats",
            arguments: EmptyArguments(),
            config: makeConfig(),
            auth: makeAuth(),
            responseType: SessionStats.self
        )

        let requests = await sender.capturedRequests()
        XCTAssertEqual(requests.filter { $0.sessionToken == "stale-token" }.count, 2)
        XCTAssertEqual(requests.filter { $0.sessionToken == "new-token" }.count, 2)
    }

    private func assertThrowsTransmissionError<T>(
        _ expectation: ErrorExpectation,
        operation: () async throws -> T
    ) async {
        do {
            _ = try await operation()
            XCTFail("Expected TransmissionError")
        } catch let error as TransmissionError {
            expectation.assertMatches(error, file: #filePath, line: #line)
        } catch {
            XCTFail("Expected TransmissionError, got \(error)", file: #filePath, line: #line)
        }
    }
}

private let successStatsBody = """
{
  "arguments": {
    "activeTorrentCount": 1,
    "downloadSpeed": 2,
    "pausedTorrentCount": 3,
    "torrentCount": 4,
    "uploadSpeed": 5
  },
  "result": "success"
}
"""

private func makeConfig() -> TransmissionConfig {
    var config = TransmissionConfig()
    config.scheme = "http"
    config.host = "example.com"
    config.port = 9091
    return config
}

private func makeAuth() -> TransmissionAuth {
    TransmissionAuth(username: "demo", password: "secret")
}

private func requestOutcome(transport: TransmissionRPCTransport) async -> RequestOutcome {
    do {
        _ = try await transport.sendEnvelope(
            method: "session-stats",
            arguments: EmptyArguments(),
            config: makeConfig(),
            auth: makeAuth(),
            responseType: SessionStats.self
        )
        return .success
    } catch let error as TransmissionError {
        if case .unauthorized = error {
            return .unauthorized
        }

        return .otherFailure(String(describing: error))
    } catch {
        return .otherFailure(error.localizedDescription)
    }
}

private enum ErrorExpectation {
    case invalidResponse
    case unauthorized
    case timeout
    case cancelled
    case decoding
    case transport
    case rpcFailure(expectedResult: String)
    case httpStatus(expectedCode: Int, expectedBody: String?)

    func assertMatches(_ error: TransmissionError, file: StaticString, line: UInt) {
        switch (self, error) {
        case (.invalidResponse, .invalidResponse),
             (.unauthorized, .unauthorized),
             (.timeout, .timeout),
             (.cancelled, .cancelled):
            break
        case (.decoding, .decoding(let description)):
            XCTAssertFalse(description.isEmpty, file: file, line: line)
        case (.transport, .transport(let description)):
            XCTAssertFalse(description.isEmpty, file: file, line: line)
        case let (.rpcFailure(expectedResult), .rpcFailure(result)):
            XCTAssertEqual(result, expectedResult, file: file, line: line)
        case let (.httpStatus(expectedCode, expectedBody), .httpStatus(code, body)):
            XCTAssertEqual(code, expectedCode, file: file, line: line)
            XCTAssertEqual(body, expectedBody, file: file, line: line)
        default:
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }
}

private enum RequestOutcome: Equatable {
    case success
    case unauthorized
    case otherFailure(String)
}

private actor QueueSender: TransmissionRPCRequestSending {
    enum Step {
        case http(statusCode: Int, body: String, headers: [String: String] = [:])
        case error(any Error)
    }

    private var steps: [Step]
    private var requests: [CapturedRequest] = []

    init(steps: [Step]) {
        self.steps = steps
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(CapturedRequest(request))

        guard !steps.isEmpty else {
            throw TestError.unexpectedRequest
        }

        let step = steps.removeFirst()
        switch step {
        case let .http(statusCode, body, headers):
            return (
                Data(body.utf8),
                makeHTTPResponse(for: request.url!, statusCode: statusCode, headers: headers)
            )
        case let .error(error):
            throw error
        }
    }

    func capturedRequests() -> [CapturedRequest] {
        requests
    }
}

private actor ConcurrentRefreshSender: TransmissionRPCRequestSending {
    private var requests: [CapturedRequest] = []

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(CapturedRequest(request))

        if request.value(forHTTPHeaderField: transmissionSessionTokenHeader) == "shared-token" {
            return (Data(successStatsBody.utf8), makeHTTPResponse(for: request.url!, statusCode: 200))
        }

        return (
            Data(),
            makeHTTPResponse(
                for: request.url!,
                statusCode: 409,
                headers: [transmissionSessionTokenHeader: "shared-token"]
            )
        )
    }

    func capturedRequests() -> [CapturedRequest] {
        requests
    }
}

private actor ConcurrentUnauthorizedRefreshSender: TransmissionRPCRequestSending {
    private var requests: [CapturedRequest] = []
    private var staleTokenResponses = 0

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(CapturedRequest(request))

        switch request.value(forHTTPHeaderField: transmissionSessionTokenHeader) {
        case "stale-token":
            staleTokenResponses += 1
            if staleTokenResponses == 1 {
                return (Data(), makeHTTPResponse(for: request.url!, statusCode: 401))
            }

            return (
                Data(),
                makeHTTPResponse(
                    for: request.url!,
                    statusCode: 409,
                    headers: [transmissionSessionTokenHeader: "new-token"]
                )
            )
        case "new-token":
            return (Data(successStatsBody.utf8), makeHTTPResponse(for: request.url!, statusCode: 200))
        default:
            throw TestError.unexpectedRequest
        }
    }

    func capturedRequests() -> [CapturedRequest] {
        requests
    }
}

private struct CapturedRequest: Sendable {
    let url: URL?
    let httpMethod: String?
    let body: Data?
    let authorizationHeader: String?
    let sessionToken: String?
    let contentType: String?

    init(_ request: URLRequest) {
        url = request.url
        httpMethod = request.httpMethod
        body = request.httpBody
        authorizationHeader = request.value(forHTTPHeaderField: "Authorization")
        sessionToken = request.value(forHTTPHeaderField: transmissionSessionTokenHeader)
        contentType = request.value(forHTTPHeaderField: "Content-Type")
    }
}

private enum TestError: Error {
    case offline
    case unexpectedRequest
}

private func makeHTTPResponse(
    for url: URL,
    statusCode: Int,
    headers: [String: String] = [:]
) -> HTTPURLResponse {
    guard let response = HTTPURLResponse(
        url: url,
        statusCode: statusCode,
        httpVersion: nil,
        headerFields: headers
    ) else {
        fatalError("Failed to build HTTPURLResponse for test")
    }

    return response
}
