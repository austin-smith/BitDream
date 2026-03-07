import XCTest
@testable import BitDream

final class TransmissionConnectionQueryTests: XCTestCase {
    func testFetchTorrentSummaryUsesNamedSummaryFieldsAndDecodesTorrents() async throws {
        let sender = QueueSender(steps: [
            .http(statusCode: 200, body: try loadTransmissionFixture(named: "torrent-get.response.json"))
        ])
        let connection = TransmissionConnection(
            endpoint: try makeEndpoint(),
            auth: makeAuth(),
            transport: TransmissionTransport(sender: sender)
        )

        let torrents = try await connection.fetchTorrentSummary()

        XCTAssertFalse(torrents.isEmpty)
        let requests = await sender.capturedRequests()
        XCTAssertEqual(try capturedRequestFields(requests[0]), TransmissionTorrentQuerySpec.torrentSummary.fields)
    }

    func testFetchWidgetSummaryUsesNamedWidgetFields() async throws {
        let sender = QueueSender(steps: [
            .http(statusCode: 200, body: try loadTransmissionFixture(named: "torrent-get.response.json"))
        ])
        let connection = TransmissionConnection(
            endpoint: try makeEndpoint(),
            auth: makeAuth(),
            transport: TransmissionTransport(sender: sender)
        )

        _ = try await connection.fetchWidgetSummary()

        let requests = await sender.capturedRequests()
        XCTAssertEqual(try capturedRequestFields(requests[0]), TransmissionTorrentQuerySpec.widgetSummary.fields)
    }

    func testFetchTorrentFilesUsesNamedFieldsAndDecodesFirstTorrent() async throws {
        let sender = QueueSender(steps: [
            .http(
                statusCode: 200,
                body: """
                {
                  "arguments": {
                    "torrents": [
                      {
                        "files": [
                          { "bytesCompleted": 1, "length": 2, "name": "Ubuntu.iso" }
                        ],
                        "fileStats": [
                          { "bytesCompleted": 1, "wanted": true, "priority": 0 }
                        ]
                      }
                    ]
                  },
                  "result": "success"
                }
                """
            )
        ])
        let connection = TransmissionConnection(
            endpoint: try makeEndpoint(),
            auth: makeAuth(),
            transport: TransmissionTransport(sender: sender)
        )

        let response = try await connection.fetchTorrentFiles(id: 42)

        XCTAssertEqual(response.files.first?.name, "Ubuntu.iso")
        let requests = await sender.capturedRequests()
        XCTAssertEqual(try capturedRequestFields(requests[0]), TransmissionTorrentQuerySpec.torrentFiles(id: 42).fields)
    }

    func testFetchTorrentPeersUsesNamedFieldsAndDecodesFirstTorrent() async throws {
        let sender = QueueSender(steps: [
            .http(
                statusCode: 200,
                body: makeTorrentPeersSuccessBody()
            )
        ])
        let connection = TransmissionConnection(
            endpoint: try makeEndpoint(),
            auth: makeAuth(),
            transport: TransmissionTransport(sender: sender)
        )

        let response = try await connection.fetchTorrentPeers(id: 42)

        XCTAssertEqual(response.peers.first?.clientName, "Transmission")
        let requests = await sender.capturedRequests()
        XCTAssertEqual(try capturedRequestFields(requests[0]), TransmissionTorrentQuerySpec.torrentPeers(id: 42).fields)
    }

    func testFetchTorrentPiecesUsesNamedFieldsAndDecodesFirstTorrent() async throws {
        let sender = QueueSender(steps: [
            .http(
                statusCode: 200,
                body: """
                {
                  "arguments": {
                    "torrents": [
                      {
                        "pieceCount": 2,
                        "pieceSize": 16384,
                        "pieces": "Zm9v"
                      }
                    ]
                  },
                  "result": "success"
                }
                """
            )
        ])
        let connection = TransmissionConnection(
            endpoint: try makeEndpoint(),
            auth: makeAuth(),
            transport: TransmissionTransport(sender: sender)
        )

        let response = try await connection.fetchTorrentPieces(id: 42)

        XCTAssertEqual(response.pieces, "Zm9v")
        let requests = await sender.capturedRequests()
        XCTAssertEqual(try capturedRequestFields(requests[0]), TransmissionTorrentQuerySpec.torrentPieces(id: 42).fields)
    }

    func testFetchSessionStatsDecodesResponse() async throws {
        let sender = QueueSender(steps: [
            .http(statusCode: 200, body: successStatsBody)
        ])
        let connection = TransmissionConnection(
            endpoint: try makeEndpoint(),
            auth: makeAuth(),
            transport: TransmissionTransport(sender: sender)
        )

        let stats = try await connection.fetchSessionStats()

        XCTAssertEqual(stats.torrentCount, 4)
    }

    func testFetchSessionSettingsUsesNamedFieldsAndDecodesArguments() async throws {
        let sender = QueueSender(steps: [
            .http(statusCode: 200, body: try loadTransmissionFixture(named: "session-get.response.json"))
        ])
        let connection = TransmissionConnection(
            endpoint: try makeEndpoint(),
            auth: makeAuth(),
            transport: TransmissionTransport(sender: sender)
        )

        let settings = try await connection.fetchSessionSettings()

        XCTAssertFalse(settings.downloadDir.isEmpty)
        let requests = await sender.capturedRequests()
        XCTAssertEqual(try capturedRequestFields(requests[0]), TransmissionSessionQuerySpec.sessionSettings.fields)
    }

    func testQueryMethodsPropagateTransmissionErrors() async throws {
        let sender = QueueSender(steps: [
            .http(statusCode: 200, body: #"{"result":"server busy","arguments":{}}"#)
        ])
        let connection = TransmissionConnection(
            endpoint: try makeEndpoint(),
            auth: makeAuth(),
            transport: TransmissionTransport(sender: sender)
        )

        await assertThrowsTransmissionError(.rpcFailure(expectedResult: "server busy")) {
            _ = try await connection.fetchTorrentSummary()
        }
    }
}

private func makeTorrentPeersSuccessBody() -> String {
    """
    {
      "arguments": {
        "torrents": [
          {
            "peers": [
              {
                "address": "127.0.0.1",
                "clientName": "Transmission",
                "clientIsChoked": false,
                "clientIsInterested": true,
                "flagStr": "D",
                "isDownloadingFrom": true,
                "isEncrypted": false,
                "isIncoming": false,
                "isUploadingTo": false,
                "isUTP": false,
                "peerIsChoked": false,
                "peerIsInterested": true,
                "port": 51413,
                "progress": 0.5,
                "rateToClient": 100,
                "rateToPeer": 200
              }
            ],
            "peersFrom": {
              "fromCache": 0,
              "fromDht": 1,
              "fromIncoming": 0,
              "fromLpd": 0,
              "fromLtep": 0,
              "fromPex": 0,
              "fromTracker": 1
            }
          }
        ]
      },
      "result": "success"
    }
    """
}
