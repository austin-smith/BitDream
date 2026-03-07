import XCTest
@testable import BitDream

final class TransportEnvelopeTests: XCTestCase {
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
            .http(statusCode: 200, body: #"{"result":"duplicate torrent","arguments":{}}"#)
        ])
        let transport = TransmissionRPCTransport(sender: sender, tokenStore: TransmissionSessionTokenStore())

        await assertThrowsTransmissionError(.rpcFailure(expectedResult: "duplicate torrent")) {
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
            .http(statusCode: 200, body: #"{"arguments":{"torrentCount":4}}"#)
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
            )
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
            .http(statusCode: 200, body: #"{"result":"success"}"#)
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
}
