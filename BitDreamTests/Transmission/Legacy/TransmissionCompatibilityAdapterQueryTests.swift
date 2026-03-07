import XCTest
@testable import BitDream

final class TransmissionAdapterQueryTests: XCTestCase {
    func testFetchTorrentSummaryReturnsTorrents() async throws {
        let adapter = makeLegacyAdapter(steps: [
            .http(statusCode: 200, body: try loadTransmissionFixture(named: "torrent-get.response.json"))
        ])

        let result = await adapter.fetchTorrentSummary(config: makeConfig(), auth: makeAuth())

        switch result {
        case .success(let torrents):
            XCTAssertFalse(torrents.isEmpty)
        case .failure(let error):
            XCTFail("Expected success, got \(error)")
        }
    }

    func testFetchWidgetSummaryReturnsTorrents() async throws {
        let adapter = makeLegacyAdapter(steps: [
            .http(statusCode: 200, body: try loadTransmissionFixture(named: "torrent-get.response.json"))
        ])

        let result = await adapter.fetchWidgetSummary(config: makeConfig(), auth: makeAuth())

        switch result {
        case .success(let torrents):
            XCTAssertFalse(torrents.isEmpty)
        case .failure(let error):
            XCTFail("Expected success, got \(error)")
        }
    }

    func testFetchTorrentFilesReturnsFirstTorrentPayload() async {
        let adapter = makeLegacyAdapter(steps: [
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

        let result = await adapter.fetchTorrentFiles(
            transferID: 42,
            config: makeConfig(),
            auth: makeAuth()
        )

        switch result {
        case .success(let response):
            XCTAssertEqual(response.files.first?.name, "Ubuntu.iso")
        case .failure(let error):
            XCTFail("Expected success, got \(error)")
        }
    }

    func testFetchTorrentPeersReturnsFirstTorrentPayload() async {
        let adapter = makeLegacyAdapter(steps: [
            .http(statusCode: 200, body: makeCompatibilityTorrentPeersSuccessBody())
        ])

        let result = await adapter.fetchTorrentPeers(
            transferID: 42,
            config: makeConfig(),
            auth: makeAuth()
        )

        switch result {
        case .success(let response):
            XCTAssertEqual(response.peers.first?.clientName, "Transmission")
        case .failure(let error):
            XCTFail("Expected success, got \(error)")
        }
    }

    func testFetchTorrentPiecesReturnsFirstTorrentPayload() async {
        let adapter = makeLegacyAdapter(steps: [
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

        let result = await adapter.fetchTorrentPieces(
            transferID: 42,
            config: makeConfig(),
            auth: makeAuth()
        )

        switch result {
        case .success(let response):
            XCTAssertEqual(response.pieces, "Zm9v")
        case .failure(let error):
            XCTFail("Expected success, got \(error)")
        }
    }

    func testFetchSessionStatsReturnsStats() async {
        let adapter = makeLegacyAdapter(steps: [
            .http(statusCode: 200, body: successStatsBody)
        ])

        let result = await adapter.fetchSessionStats(config: makeConfig(), auth: makeAuth())

        switch result {
        case .success(let stats):
            XCTAssertEqual(stats.torrentCount, 4)
        case .failure(let error):
            XCTFail("Expected success, got \(error)")
        }
    }

    func testFetchSessionSettingsReturnsSettings() async throws {
        let adapter = makeLegacyAdapter(steps: [
            .http(statusCode: 200, body: try loadTransmissionFixture(named: "session-get.response.json"))
        ])

        let result = await adapter.fetchSessionSettings(config: makeConfig(), auth: makeAuth())

        switch result {
        case .success(let settings):
            XCTAssertFalse(settings.downloadDir.isEmpty)
        case .failure(let error):
            XCTFail("Expected success, got \(error)")
        }
    }
}

private func makeCompatibilityTorrentPeersSuccessBody() -> String {
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
