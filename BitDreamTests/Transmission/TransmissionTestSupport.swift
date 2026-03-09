import Foundation
import XCTest
@testable import BitDream

let successStatsBody = """
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

let successEmptyBody = """
{
  "arguments": {},
  "result": "success"
}
"""

func makeEndpoint() throws -> TransmissionEndpoint {
    try TransmissionEndpoint(scheme: "http", host: "example.com", port: 9091)
}

func makeAuth() -> TransmissionAuth {
    TransmissionAuth(username: "demo", password: "secret")
}

func requestOutcome(connection: TransmissionConnection) async -> RequestOutcome {
    do {
        _ = try await connection.sendEnvelope(
            method: "session-stats",
            arguments: EmptyArguments(),
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

enum ErrorExpectation {
    case invalidEndpointConfiguration
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
        case (.invalidEndpointConfiguration, .invalidEndpointConfiguration),
             (.invalidResponse, .invalidResponse),
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

enum RequestOutcome: Equatable {
    case success
    case unauthorized
    case otherFailure(String)
}

actor QueueSender: TransmissionRPCRequestSending {
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

actor MethodQueueSender: TransmissionRPCRequestSending {
    enum Step {
        case http(statusCode: Int, body: String, headers: [String: String] = [:])
        case error(any Error)
    }

    private var stepsByMethod: [String: [Step]]
    private var requests: [CapturedRequest] = []

    init(stepsByMethod: [String: [Step]]) {
        self.stepsByMethod = stepsByMethod
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(CapturedRequest(request))

        guard
            let url = request.url,
            let method = try? requestMethod(from: request),
            var methodSteps = stepsByMethod[method],
            !methodSteps.isEmpty
        else {
            throw TestError.unexpectedRequest
        }

        let step = methodSteps.removeFirst()
        stepsByMethod[method] = methodSteps

        switch step {
        case let .http(statusCode, body, headers):
            return (
                Data(body.utf8),
                makeHTTPResponse(for: url, statusCode: statusCode, headers: headers)
            )
        case let .error(error):
            throw error
        }
    }

    func capturedRequests() -> [CapturedRequest] {
        requests
    }
}

actor HostMethodScriptedSender: TransmissionRPCRequestSending {
    enum Step {
        case http(statusCode: Int, body: String, headers: [String: String] = [:])
        case blocked(id: String, statusCode: Int, body: String, headers: [String: String] = [:])
        case error(any Error)
    }

    private var stepsByHostAndMethod: [String: [String: [Step]]]
    private var continuations: [String: CheckedContinuation<Void, Never>] = [:]
    private var requests: [CapturedRequest] = []

    init(stepsByHostAndMethod: [String: [String: [Step]]]) {
        self.stepsByHostAndMethod = stepsByHostAndMethod
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(CapturedRequest(request))

        guard
            let url = request.url,
            let host = url.host,
            let method = try? requestMethod(from: request),
            var hostSteps = stepsByHostAndMethod[host],
            var methodSteps = hostSteps[method],
            !methodSteps.isEmpty
        else {
            throw TestError.unexpectedRequest
        }

        let step = methodSteps.removeFirst()
        hostSteps[method] = methodSteps
        stepsByHostAndMethod[host] = hostSteps

        switch step {
        case let .http(statusCode, body, headers):
            return (
                Data(body.utf8),
                makeHTTPResponse(for: url, statusCode: statusCode, headers: headers)
            )
        case let .blocked(id, statusCode, body, headers):
            await withCheckedContinuation { continuation in
                continuations[id] = continuation
            }
            return (
                Data(body.utf8),
                makeHTTPResponse(for: url, statusCode: statusCode, headers: headers)
            )
        case let .error(error):
            throw error
        }
    }

    func resume(id: String) {
        continuations.removeValue(forKey: id)?.resume()
    }

    func capturedRequests() -> [CapturedRequest] {
        requests
    }
}

actor ConcurrentRefreshSender: TransmissionRPCRequestSending {
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

actor ConcurrentUnauthorizedRefreshSender: TransmissionRPCRequestSending {
    private var requests: [CapturedRequest] = []
    private var staleTokenResponses = 0
    private var staleRequestContinuations: [CheckedContinuation<Void, Never>] = []

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(CapturedRequest(request))

        switch request.value(forHTTPHeaderField: transmissionSessionTokenHeader) {
        case "stale-token":
            staleTokenResponses += 1
            let responseNumber = staleTokenResponses

            if responseNumber == 1 {
                await withCheckedContinuation { continuation in
                    staleRequestContinuations.append(continuation)
                }
                return (Data(), makeHTTPResponse(for: request.url!, statusCode: 401))
            }

            let continuations = staleRequestContinuations
            staleRequestContinuations.removeAll()
            for continuation in continuations {
                continuation.resume()
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

struct CapturedRequest: Sendable {
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

func capturedRequestFields(_ request: CapturedRequest) throws -> [String] {
    let body = try XCTUnwrap(request.body)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    let arguments = try XCTUnwrap(object["arguments"] as? [String: Any])
    return try XCTUnwrap(arguments["fields"] as? [String])
}

func requestMethod(from request: URLRequest) throws -> String {
    let body = try XCTUnwrap(request.httpBody)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    return try XCTUnwrap(object["method"] as? String)
}

func loadTransmissionFixture(named fileName: String) throws -> String {
    let testFileURL = URL(fileURLWithPath: #filePath)
    let fixturesURL = testFileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("BitDream")
        .appendingPathComponent("Transmission")
        .appendingPathComponent("TransmissionRPC")
        .appendingPathComponent("Examples")
        .appendingPathComponent(fileName)

    return try String(contentsOf: fixturesURL, encoding: .utf8)
}

enum TestError: Error {
    case offline
    case unexpectedRequest
}

func makeHTTPResponse(
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

extension CapturedRequest {
    func asURLRequest() -> URLRequest {
        var request = URLRequest(url: url ?? URL(string: "https://example.com")!)
        request.httpMethod = httpMethod
        request.httpBody = body
        return request
    }
}

func requestArguments(from request: CapturedRequest) throws -> [String: Any] {
    let body = try XCTUnwrap(request.body)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    return try XCTUnwrap(object["arguments"] as? [String: Any])
}

func sessionSettingsBody(downloadDir: String, version: String) throws -> String {
    let data = Data(try loadTransmissionFixture(named: "session-get.response.json").utf8)
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    var arguments = try XCTUnwrap(object["arguments"] as? [String: Any])
    arguments["download-dir"] = downloadDir
    arguments["version"] = version
    arguments["blocklist-size"] = 0
    object["arguments"] = arguments
    let encoded = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    return try XCTUnwrap(String(bytes: encoded, encoding: .utf8))
}

@MainActor
func makeStore(sender: some TransmissionRPCRequestSending) -> TransmissionStore {
    let factory = TransmissionConnectionFactory(
        transport: TransmissionTransport(sender: sender),
        credentialResolver: TransmissionCredentialResolver(resolvePassword: { source in
            switch source {
            case .resolvedPassword(let password):
                return password
            case .keychainCredential(let key):
                return key == "test-key" ? "secret" : ""
            }
        })
    )

    return TransmissionStore(
        connectionFactory: factory,
        snapshotWriter: WidgetSnapshotWriter(
            writeServerIndex: { _ in },
            writeSessionSnapshot: { _, _, _, _, _ in },
            reloadTimelines: { }
        ),
        sleep: { _ in
            try await Task.sleep(nanoseconds: .max)
        },
        persistVersion: { _, _ in }
    )
}

func makeHost(serverID: String, server: String) -> BitDream.Host {
    BitDream.Host(
        serverID: serverID,
        isDefault: false,
        isSSL: false,
        credentialKey: "test-key",
        name: serverID,
        port: 9091,
        server: server,
        username: "demo",
        version: nil
    )
}

func waitUntil(
    timeout: TimeInterval = 1,
    _ predicate: @escaping @MainActor () async -> Bool
) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await predicate() {
            return true
        }
        await Task.yield()
    }
    return false
}

extension XCTestCase {
    func assertThrowsTransmissionError<T>(
        _ expectation: ErrorExpectation,
        operation: () async throws -> T
    ) async {
        do {
            _ = try await operation()
            XCTFail("Expected TransmissionError")
        } catch let error as TransmissionTransportFailure {
            expectation.assertMatches(error.transmissionError, file: #filePath, line: #line)
        } catch let error as TransmissionError {
            expectation.assertMatches(error, file: #filePath, line: #line)
        } catch {
            XCTFail("Expected TransmissionError, got \(error)", file: #filePath, line: #line)
        }
    }
}
