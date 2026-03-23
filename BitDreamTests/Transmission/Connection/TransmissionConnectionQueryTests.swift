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
        let sampleTorrent = try XCTUnwrap(torrents.first(where: { $0.id == 2 }))
        XCTAssertEqual(sampleTorrent.uploadRatioRaw, 0)
        XCTAssertEqual(sampleTorrent.uploadRatio, .value(0))
        XCTAssertEqual(sampleTorrent.uploadRatio.displayText, "0.00")
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

    func testFetchTorrentSummaryDistinguishesUnavailableAndInfiniteRawRatioValues() async throws {
        let sender = QueueSender(steps: [
            .http(
                statusCode: 200,
                body: """
                {
                  "arguments": {
                    "torrents": [
                      {
                        "activityDate": 0,
                        "addedDate": 0,
                        "desiredAvailable": 0,
                        "error": 0,
                        "errorString": "",
                        "eta": 0,
                        "haveUnchecked": 0,
                        "haveValid": 0,
                        "id": 1,
                        "isFinished": false,
                        "isStalled": false,
                        "labels": [],
                        "leftUntilDone": 0,
                        "magnetLink": "",
                        "metadataPercentComplete": 1,
                        "name": "Unavailable",
                        "peersConnected": 0,
                        "peersGettingFromUs": 0,
                        "peersSendingToUs": 0,
                        "percentDone": 0,
                        "primary-mime-type": null,
                        "downloadDir": "/downloads",
                        "queuePosition": 0,
                        "rateDownload": 0,
                        "rateUpload": 0,
                        "sizeWhenDone": 0,
                        "status": 0,
                        "totalSize": 0,
                        "uploadRatio": -1,
                        "uploadedEver": 0,
                        "downloadedEver": 0
                      },
                      {
                        "activityDate": 0,
                        "addedDate": 0,
                        "desiredAvailable": 0,
                        "error": 0,
                        "errorString": "",
                        "eta": 0,
                        "haveUnchecked": 0,
                        "haveValid": 0,
                        "id": 2,
                        "isFinished": false,
                        "isStalled": false,
                        "labels": [],
                        "leftUntilDone": 0,
                        "magnetLink": "",
                        "metadataPercentComplete": 1,
                        "name": "Infinite",
                        "peersConnected": 0,
                        "peersGettingFromUs": 0,
                        "peersSendingToUs": 0,
                        "percentDone": 0,
                        "primary-mime-type": null,
                        "downloadDir": "/downloads",
                        "queuePosition": 0,
                        "rateDownload": 0,
                        "rateUpload": 0,
                        "sizeWhenDone": 0,
                        "status": 0,
                        "totalSize": 0,
                        "uploadRatio": -2,
                        "uploadedEver": 1,
                        "downloadedEver": 0
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

        let torrents = try await connection.fetchTorrentSummary()

        let unavailableTorrent = try XCTUnwrap(torrents.first(where: { $0.id == 1 }))
        XCTAssertEqual(unavailableTorrent.uploadRatioRaw, -1)
        XCTAssertEqual(unavailableTorrent.uploadRatio, .unavailable)
        XCTAssertEqual(unavailableTorrent.uploadRatio.displayText, "None")
        XCTAssertEqual(unavailableTorrent.uploadRatio.ringProgressValue, 0)
        XCTAssertFalse(unavailableTorrent.uploadRatio.usesCompletionColor)

        let infiniteTorrent = try XCTUnwrap(torrents.first(where: { $0.id == 2 }))
        XCTAssertEqual(infiniteTorrent.uploadRatioRaw, -2)
        XCTAssertEqual(infiniteTorrent.uploadRatio, .infinite)
        XCTAssertEqual(infiniteTorrent.uploadRatio.displayText, "1.00+")
        XCTAssertEqual(infiniteTorrent.uploadRatio.ringProgressValue, 1)
        XCTAssertTrue(infiniteTorrent.uploadRatio.usesCompletionColor)
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

    func testFetchTorrentDetailSnapshotUsesNamedQueriesAndDecodesResponse() async throws {
        let sender = MethodQueueSender(stepsByMethod: [
            "torrent-get": [
                .http(statusCode: 200, body: makeTorrentDetailSuccessBody()),
                .http(statusCode: 200, body: makeTorrentDetailSuccessBody()),
                .http(statusCode: 200, body: makeTorrentDetailSuccessBody())
            ]
        ])
        let connection = TransmissionConnection(
            endpoint: try makeEndpoint(),
            auth: makeAuth(),
            transport: TransmissionTransport(sender: sender)
        )

        let snapshot = try await connection.fetchTorrentDetailSnapshot(id: 42)

        XCTAssertEqual(snapshot.files.first?.name, "Ubuntu.iso")
        XCTAssertEqual(snapshot.fileStats.first?.wanted, true)
        XCTAssertEqual(snapshot.peers.first?.clientName, "Transmission")
        XCTAssertEqual(snapshot.pieceCount, 2)
        XCTAssertEqual(snapshot.piecesBitfieldBase64, "Zm9v")

        let requests = await sender.capturedRequests()
        XCTAssertEqual(requests.count, 3)
        let fields = try requests.map(capturedRequestFields)
        XCTAssertTrue(fields.contains(TransmissionTorrentQuerySpec.torrentFiles(id: 42).fields))
        XCTAssertTrue(fields.contains(TransmissionTorrentQuerySpec.torrentPeers(id: 42).fields))
        XCTAssertTrue(fields.contains(TransmissionTorrentQuerySpec.torrentPieces(id: 42).fields))
    }

    func testFetchTorrentDetailSnapshotPropagatesErrors() async throws {
        let sender = MethodQueueSender(stepsByMethod: [
            "torrent-get": [
                .http(statusCode: 200, body: #"{"result":"server busy","arguments":{}}"#),
                .http(statusCode: 200, body: #"{"result":"server busy","arguments":{}}"#),
                .http(statusCode: 200, body: #"{"result":"server busy","arguments":{}}"#)
            ]
        ])
        let connection = TransmissionConnection(
            endpoint: try makeEndpoint(),
            auth: makeAuth(),
            transport: TransmissionTransport(sender: sender)
        )

        await assertThrowsTransmissionError(.rpcFailure(expectedResult: "server busy")) {
            _ = try await connection.fetchTorrentDetailSnapshot(id: 42)
        }
    }
}

final class TransmissionConnectionSessionQueryTests: XCTestCase {
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

    func testSetSessionUsesSessionSetMethodAndPayload() async throws {
        let sender = QueueSender(steps: [
            .http(statusCode: 200, body: successEmptyBody)
        ])
        let connection = TransmissionConnection(
            endpoint: try makeEndpoint(),
            auth: makeAuth(),
            transport: TransmissionTransport(sender: sender)
        )
        var args = TransmissionSessionSetRequestArgs()
        args.downloadDir = "/downloads/updated"
        args.speedLimitDownEnabled = true

        try await connection.setSession(args)

        let requests = await sender.capturedRequests()
        XCTAssertEqual(try requestMethod(from: requests[0].asURLRequest()), "session-set")
        let arguments = try requestArguments(from: requests[0])
        XCTAssertEqual(arguments["download-dir"] as? String, "/downloads/updated")
        XCTAssertEqual(arguments["speed-limit-down-enabled"] as? Bool, true)
    }

    func testCheckFreeSpaceDecodesResponse() async throws {
        let sender = QueueSender(steps: [
            .http(
                statusCode: 200,
                body: #"{"result":"success","arguments":{"path":"/downloads","size-bytes":1024,"total_size":2048}}"#
            )
        ])
        let connection = TransmissionConnection(
            endpoint: try makeEndpoint(),
            auth: makeAuth(),
            transport: TransmissionTransport(sender: sender)
        )

        let response = try await connection.checkFreeSpace(path: "/downloads")

        XCTAssertEqual(response.path, "/downloads")
        XCTAssertEqual(response.sizeBytes, 1024)
        XCTAssertEqual(response.totalSize, 2048)
        let requests = await sender.capturedRequests()
        XCTAssertEqual(try requestMethod(from: requests[0].asURLRequest()), "free-space")
    }

    func testTestPortDecodesResponse() async throws {
        let sender = QueueSender(steps: [
            .http(
                statusCode: 200,
                body: #"{"result":"success","arguments":{"port-is-open":true,"ip_protocol":"ipv6"}}"#
            )
        ])
        let connection = TransmissionConnection(
            endpoint: try makeEndpoint(),
            auth: makeAuth(),
            transport: TransmissionTransport(sender: sender)
        )

        let response = try await connection.testPort(ipProtocol: "ipv6")

        XCTAssertEqual(response.portIsOpen, true)
        XCTAssertEqual(response.ipProtocol, "ipv6")
        let requests = await sender.capturedRequests()
        XCTAssertEqual(try requestMethod(from: requests[0].asURLRequest()), "port-test")
    }

    func testUpdateBlocklistDecodesResponse() async throws {
        let sender = QueueSender(steps: [
            .http(
                statusCode: 200,
                body: #"{"result":"success","arguments":{"blocklist-size":42}}"#
            )
        ])
        let connection = TransmissionConnection(
            endpoint: try makeEndpoint(),
            auth: makeAuth(),
            transport: TransmissionTransport(sender: sender)
        )

        let response = try await connection.updateBlocklist()

        XCTAssertEqual(response.blocklistSize, 42)
        let requests = await sender.capturedRequests()
        XCTAssertEqual(try requestMethod(from: requests[0].asURLRequest()), "blocklist-update")
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

    func testSessionOperationsPropagateTransmissionErrors() async throws {
        let sender = QueueSender(steps: [
            .http(statusCode: 401, body: "")
        ])
        let connection = TransmissionConnection(
            endpoint: try makeEndpoint(),
            auth: makeAuth(),
            transport: TransmissionTransport(sender: sender)
        )

        await assertThrowsTransmissionError(.unauthorized) {
            _ = try await connection.testPort()
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

private func makeTorrentDetailSuccessBody() -> String {
    """
    {
      "arguments": {
        "torrents": [
          {
            "files": [
              { "bytesCompleted": 1, "length": 2, "name": "Ubuntu.iso" }
            ],
            "fileStats": [
              { "bytesCompleted": 1, "wanted": true, "priority": 0 }
            ],
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
            },
            "pieceCount": 2,
            "pieceSize": 16384,
            "pieces": "Zm9v"
          }
        ]
      },
      "result": "success"
    }
    """
}
