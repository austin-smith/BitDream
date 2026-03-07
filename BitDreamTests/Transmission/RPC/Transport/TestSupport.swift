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

func makeConfig() -> TransmissionConfig {
    var config = TransmissionConfig()
    config.scheme = "http"
    config.host = "example.com"
    config.port = 9091
    return config
}

func makeAuth() -> TransmissionAuth {
    TransmissionAuth(username: "demo", password: "secret")
}

func requestOutcome(transport: TransmissionRPCTransport) async -> RequestOutcome {
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

enum ErrorExpectation {
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

extension XCTestCase {
    func assertThrowsTransmissionError<T>(
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
