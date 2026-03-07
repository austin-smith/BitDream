import XCTest
@testable import BitDream

final class TransmissionTransportEnvelopeTests: XCTestCase {
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
            )
        ])
        let transport = TransmissionTransport(sender: sender)

        let envelope = try await transport.sendEnvelope(
            method: "session-stats",
            arguments: EmptyArguments(),
            endpoint: try makeEndpoint(),
            auth: makeAuth(),
            responseType: SessionStats.self
        ).envelope

        XCTAssertEqual(envelope.tag, 42)
        XCTAssertEqual(try envelope.requireArguments().torrentCount, 4)
    }

    func testSendEnvelopeMapsRPCFailureResultToTransmissionError() async {
        let sender = QueueSender(steps: [
            .http(statusCode: 200, body: #"{"result":"duplicate torrent","arguments":{}}"#)
        ])
        let transport = TransmissionTransport(sender: sender)

        await assertThrowsTransmissionError(.rpcFailure(expectedResult: "duplicate torrent")) {
            _ = try await transport.sendEnvelope(
                method: "torrent-add",
                arguments: ["filename": "magnet:?xt=urn:btih:test"] as StringArguments,
                endpoint: try makeEndpoint(),
                auth: makeAuth(),
                responseType: [String: TorrentAddResponseArgs].self
            )
        }
    }

    func testSendEnvelopeMapsRPCFailureBeforeDecodingSuccessArguments() async {
        let sender = QueueSender(steps: [
            .http(statusCode: 200, body: #"{"result":"server busy","arguments":{}}"#)
        ])
        let transport = TransmissionTransport(sender: sender)

        await assertThrowsTransmissionError(.rpcFailure(expectedResult: "server busy")) {
            _ = try await transport.sendEnvelope(
                method: "session-stats",
                arguments: EmptyArguments(),
                endpoint: try makeEndpoint(),
                auth: makeAuth(),
                responseType: SessionStats.self
            )
        }
    }

    func testSendEnvelopeMapsMissingResultToInvalidResponse() async {
        let sender = QueueSender(steps: [
            .http(statusCode: 200, body: #"{"arguments":{"torrentCount":4}}"#)
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
            )
        ])
        let transport = TransmissionTransport(sender: sender)

        await assertThrowsTransmissionError(.decoding) {
            _ = try await transport.sendEnvelope(
                method: "session-stats",
                arguments: EmptyArguments(),
                endpoint: try makeEndpoint(),
                auth: makeAuth(),
                responseType: SessionStats.self
            )
        }
    }

    func testSendRequiredArgumentsMapsMissingArgumentsToInvalidResponse() async {
        let sender = QueueSender(steps: [
            .http(statusCode: 200, body: #"{"result":"success"}"#)
        ])
        let transport = TransmissionTransport(sender: sender)

        await assertThrowsTransmissionError(.invalidResponse) {
            _ = try await transport.sendRequiredArguments(
                method: "session-stats",
                arguments: EmptyArguments(),
                endpoint: try makeEndpoint(),
                auth: makeAuth(),
                responseType: SessionStats.self
            )
        }
    }
}
