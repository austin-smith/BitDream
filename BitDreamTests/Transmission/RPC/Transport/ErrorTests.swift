import XCTest
@testable import BitDream

final class TransportErrorTests: XCTestCase {
    func testTransportFailureMapsToTransportError() async {
        let sender = QueueSender(steps: [
            .error(TestError.offline)
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
            .error(URLError(.timedOut))
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
            .error(CancellationError())
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
            .http(statusCode: 500, body: "server exploded")
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
}
