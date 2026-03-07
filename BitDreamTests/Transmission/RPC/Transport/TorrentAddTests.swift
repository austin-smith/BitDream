import XCTest
@testable import BitDream

final class TransportTorrentAddTests: XCTestCase {
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
            )
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
            )
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
}
