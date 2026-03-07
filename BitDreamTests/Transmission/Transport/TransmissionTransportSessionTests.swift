import XCTest
@testable import BitDream

final class TransmissionTransportSessionTests: XCTestCase {
    func testSendEnvelopeRetriesOnceAfter409AndPreservesRequestDetails() async throws {
        let sender = QueueSender(steps: [
            .http(statusCode: 409, body: "", headers: [transmissionSessionTokenHeader: "fresh-token"]),
            .http(statusCode: 200, body: successStatsBody)
        ])
        let transport = TransmissionTransport(sender: sender)

        _ = try await transport.sendEnvelope(
            method: "session-stats",
            arguments: EmptyArguments(),
            endpoint: try makeEndpoint(),
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
            .http(statusCode: 409, body: "")
        ])
        let transport = TransmissionTransport(sender: sender)

        await assertThrowsTransmissionError(.invalidResponse) {
            _ = try await transport.sendEnvelope(
                method: "session-stats",
                arguments: EmptyArguments(),
                endpoint: try makeEndpoint(),
                auth: makeAuth(),
                responseType: SessionStats.self
            )
        }
    }

    func testSendEnvelopeMapsRepeated409AfterRetryToHTTPStatus() async {
        let sender = QueueSender(steps: [
            .http(statusCode: 409, body: "", headers: [transmissionSessionTokenHeader: "fresh-token"]),
            .http(statusCode: 409, body: "still-conflicting")
        ])
        let transport = TransmissionTransport(sender: sender)

        await assertThrowsTransmissionError(.httpStatus(expectedCode: 409, expectedBody: "still-conflicting")) {
            _ = try await transport.sendEnvelope(
                method: "session-stats",
                arguments: EmptyArguments(),
                endpoint: try makeEndpoint(),
                auth: makeAuth(),
                responseType: SessionStats.self
            )
        }
    }
}
