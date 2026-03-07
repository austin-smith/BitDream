import XCTest
@testable import BitDream

final class TransportErrorTests: XCTestCase {
    func testInvalidEndpointConfigurationMapsToInvalidEndpointConfiguration() async {
        var config = makeConfig()
        config.host = "bad host"

        let transport = TransmissionRPCTransport(
            sender: QueueSender(steps: []),
            tokenStore: TransmissionSessionTokenStore()
        )

        await assertThrowsTransmissionError(.invalidEndpointConfiguration) {
            _ = try await transport.sendEnvelope(
                method: "session-stats",
                arguments: EmptyArguments(),
                config: config,
                auth: makeAuth(),
                responseType: SessionStats.self
            )
        }
    }

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
