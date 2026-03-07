import XCTest
@testable import BitDream

final class TransmissionTransportErrorTests: XCTestCase {
    func testInvalidEndpointConfigurationMapsToInvalidEndpointConfiguration() async {
        let transport = TransmissionTransport(sender: QueueSender(steps: []))

        await assertThrowsTransmissionError(.invalidEndpointConfiguration) {
            let endpoint = try TransmissionEndpoint(scheme: "http", host: "bad host", port: 9091)
            _ = try await transport.sendEnvelope(
                method: "session-stats",
                arguments: EmptyArguments(),
                endpoint: endpoint,
                auth: makeAuth(),
                responseType: SessionStats.self
            )
        }
    }

    func testTransportFailureMapsToTransportError() async {
        let sender = QueueSender(steps: [
            .error(TestError.offline)
        ])
        let transport = TransmissionTransport(sender: sender)

        await assertThrowsTransmissionError(.transport) {
            _ = try await transport.sendEnvelope(
                method: "session-stats",
                arguments: EmptyArguments(),
                endpoint: try makeEndpoint(),
                auth: makeAuth(),
                responseType: SessionStats.self
            )
        }
    }

    func testTimedOutTransportFailureMapsToTimeout() async {
        let sender = QueueSender(steps: [
            .error(URLError(.timedOut))
        ])
        let transport = TransmissionTransport(sender: sender)

        await assertThrowsTransmissionError(.timeout) {
            _ = try await transport.sendEnvelope(
                method: "session-stats",
                arguments: EmptyArguments(),
                endpoint: try makeEndpoint(),
                auth: makeAuth(),
                responseType: SessionStats.self
            )
        }
    }

    func testCancelledTransportFailureMapsToCancelled() async {
        let sender = QueueSender(steps: [
            .error(CancellationError())
        ])
        let transport = TransmissionTransport(sender: sender)

        await assertThrowsTransmissionError(.cancelled) {
            _ = try await transport.sendEnvelope(
                method: "session-stats",
                arguments: EmptyArguments(),
                endpoint: try makeEndpoint(),
                auth: makeAuth(),
                responseType: SessionStats.self
            )
        }
    }

    func testHTTP500MapsToHTTPStatusError() async {
        let sender = QueueSender(steps: [
            .http(statusCode: 500, body: "server exploded")
        ])
        let transport = TransmissionTransport(sender: sender)

        await assertThrowsTransmissionError(.httpStatus(expectedCode: 500, expectedBody: "server exploded")) {
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
