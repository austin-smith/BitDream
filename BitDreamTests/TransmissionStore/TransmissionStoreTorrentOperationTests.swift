import Foundation
import XCTest
@testable import BitDream

@MainActor
final class TransmissionStoreTorrentOperationTests: XCTestCase {
    func testAddTorrentWaitsForActivationInFlight() async throws {
        let sender = MethodQueueSender(stepsByMethod: [
            "session-stats": [
                .http(statusCode: 200, body: successStatsBody),
                .http(statusCode: 200, body: successStatsBody)
            ],
            "torrent-get": [
                .http(statusCode: 200, body: try loadTransmissionFixture(named: "torrent-get.response.json")),
                .http(statusCode: 200, body: try loadTransmissionFixture(named: "torrent-get.response.json"))
            ],
            "session-get": [
                .http(statusCode: 200, body: try sessionSettingsBody(downloadDir: "/downloads/initial", version: "4.0.0")),
                .http(statusCode: 200, body: try sessionSettingsBody(downloadDir: "/downloads/initial", version: "4.0.0"))
            ],
            "torrent-add": [
                .http(statusCode: 200, body: makeTorrentAddSuccessBody())
            ]
        ])
        let store = makeStore(sender: sender)

        store.setHost(host: makeHost(serverID: "server-1", server: "example.com"))
        let outcome = try await store.addTorrent(
            magnetLink: "magnet:?xt=urn:btih:1234567890abcdef",
            saveLocation: "/downloads/initial"
        )

        guard case .added(let torrent) = outcome else {
            return XCTFail("Expected added torrent outcome")
        }

        XCTAssertEqual(torrent.name, "Ubuntu.iso")

        let didRefresh = await waitUntil {
            let requests = await sender.capturedRequests()
            return requests.count == 7 && store.connectionStatus == .connected
        }
        XCTAssertTrue(didRefresh)

        let methods = try await sender.capturedRequests().map { try requestMethod(from: $0.asURLRequest()) }
        XCTAssertEqual(methods.filter { $0 == "torrent-add" }.count, 1)
        XCTAssertEqual(methods.filter { $0 == "session-stats" }.count, 2)
        XCTAssertEqual(methods.filter { $0 == "torrent-get" }.count, 2)
        XCTAssertEqual(methods.filter { $0 == "session-get" }.count, 2)
    }

    func testRemoveTorrentsSchedulesRefreshAfterSuccess() async throws {
        let sender = MethodQueueSender(stepsByMethod: [
            "session-stats": [
                .http(statusCode: 200, body: successStatsBody),
                .http(statusCode: 200, body: successStatsBody)
            ],
            "torrent-get": [
                .http(statusCode: 200, body: try loadTransmissionFixture(named: "torrent-get.response.json")),
                .http(statusCode: 200, body: try loadTransmissionFixture(named: "torrent-get.response.json"))
            ],
            "session-get": [
                .http(statusCode: 200, body: try sessionSettingsBody(downloadDir: "/downloads/initial", version: "4.0.0")),
                .http(statusCode: 200, body: try sessionSettingsBody(downloadDir: "/downloads/initial", version: "4.0.0"))
            ],
            "torrent-remove": [
                .http(statusCode: 200, body: successEmptyBody)
            ]
        ])
        let store = makeStore(sender: sender)

        store.setHost(host: makeHost(serverID: "server-1", server: "example.com"))
        let didConnect = await waitUntil { store.connectionStatus == .connected }
        XCTAssertTrue(didConnect)

        try await store.removeTorrents(ids: [1], deleteLocalData: false)

        let didRefresh = await waitUntil {
            let requests = await sender.capturedRequests()
            return requests.count == 7
        }
        XCTAssertTrue(didRefresh)

        let methods = try await sender.capturedRequests().map { try requestMethod(from: $0.asURLRequest()) }
        XCTAssertEqual(methods.filter { $0 == "torrent-remove" }.count, 1)
        XCTAssertEqual(methods.filter { $0 == "session-stats" }.count, 2)
        XCTAssertEqual(methods.filter { $0 == "torrent-get" }.count, 2)
        XCTAssertEqual(methods.filter { $0 == "session-get" }.count, 2)
    }

    func testSupersededMutationDoesNotRefreshOldHostAfterHostSwitch() async throws {
        let sender = try makeSupersededMutationSender()
        let store = makeStore(sender: sender)

        store.setHost(host: makeHost(serverID: "server-1", server: "old.example.com"))
        let didConnectOldHost = await waitUntil { store.defaultDownloadDir == "/downloads/old" }
        XCTAssertTrue(didConnectOldHost)

        let removeTask = Task {
            try? await store.removeTorrents(ids: [1], deleteLocalData: true)
        }

        let didStartOldRemove = await waitUntil {
            let requests = await sender.capturedRequests()
            return requests.count == 4
        }
        XCTAssertTrue(didStartOldRemove)

        store.setHost(host: makeHost(serverID: "server-2", server: "new.example.com"))
        let didConnectNewHost = await waitUntil {
            store.host?.serverID == "server-2" && store.defaultDownloadDir == "/downloads/new"
        }
        XCTAssertTrue(didConnectNewHost)

        await sender.resume(id: "old-remove")
        _ = await removeTask.result

        let requests = await sender.capturedRequests()
        let oldHostRequests = requests.filter { $0.url?.host == "old.example.com" }
        let newHostRequests = requests.filter { $0.url?.host == "new.example.com" }
        XCTAssertEqual(oldHostRequests.count, 4)
        XCTAssertEqual(newHostRequests.count, 3)
        XCTAssertEqual(store.host?.serverID, "server-2")
        XCTAssertEqual(store.defaultDownloadDir, "/downloads/new")
    }

    func testLoadTorrentDetailRejectsSupersededResultsAfterHostSwitch() async throws {
        let sender = HostMethodScriptedSender(stepsByHostAndMethod: [
            "old.example.com": [
                "session-stats": [
                    .http(statusCode: 200, body: successStatsBody)
                ],
                "torrent-get": [
                    .http(statusCode: 200, body: try loadTransmissionFixture(named: "torrent-get.response.json")),
                    .blocked(id: "old-detail", statusCode: 200, body: makeTorrentDetailSuccessBody()),
                    .http(statusCode: 200, body: makeTorrentDetailSuccessBody()),
                    .http(statusCode: 200, body: makeTorrentDetailSuccessBody())
                ],
                "session-get": [
                    .http(statusCode: 200, body: try sessionSettingsBody(downloadDir: "/downloads/old", version: "4.0.0"))
                ]
            ],
            "new.example.com": [
                "session-stats": [
                    .http(statusCode: 200, body: successStatsBody)
                ],
                "torrent-get": [
                    .http(statusCode: 200, body: try loadTransmissionFixture(named: "torrent-get.response.json"))
                ],
                "session-get": [
                    .http(statusCode: 200, body: try sessionSettingsBody(downloadDir: "/downloads/new", version: "5.0.0"))
                ]
            ]
        ])
        let store = makeStore(sender: sender)

        store.setHost(host: makeHost(serverID: "server-1", server: "old.example.com"))
        let didConnectOldHost = await waitUntil { store.connectionStatus == .connected }
        XCTAssertTrue(didConnectOldHost)

        let detailTask = Task { try await store.loadTorrentDetail(id: 42) }

        let didStartOldDetailLoad = await waitUntil {
            let requests = await sender.capturedRequests()
            return requests.filter { $0.url?.host == "old.example.com" && ($0.url?.absoluteString.contains("/transmission/rpc") ?? false) }.count >= 4
        }
        XCTAssertTrue(didStartOldDetailLoad)

        store.setHost(host: makeHost(serverID: "server-2", server: "new.example.com"))
        let didConnectNewHost = await waitUntil { store.defaultDownloadDir == "/downloads/new" }
        XCTAssertTrue(didConnectNewHost)

        await sender.resume(id: "old-detail")

        do {
            _ = try await detailTask.value
            XCTFail("Expected superseded detail load to fail")
        } catch {
            XCTAssertNil(TransmissionUserFacingError.presentation(for: error))
        }
    }

    func testUpdateTorrentLabelsSchedulesRefreshAfterPartialFailure() async throws {
        let sender = MethodQueueSender(stepsByMethod: [
            "session-stats": [
                .http(statusCode: 200, body: successStatsBody),
                .http(statusCode: 200, body: successStatsBody)
            ],
            "torrent-get": [
                .http(statusCode: 200, body: try loadTransmissionFixture(named: "torrent-get.response.json")),
                .http(statusCode: 200, body: try loadTransmissionFixture(named: "torrent-get.response.json"))
            ],
            "session-get": [
                .http(statusCode: 200, body: try sessionSettingsBody(downloadDir: "/downloads/initial", version: "4.0.0")),
                .http(statusCode: 200, body: try sessionSettingsBody(downloadDir: "/downloads/initial", version: "4.0.0"))
            ],
            "torrent-set": [
                .http(statusCode: 200, body: successEmptyBody),
                .http(statusCode: 200, body: rpcFailureBody(result: "labels failed"))
            ]
        ])
        let store = makeStore(sender: sender)

        store.setHost(host: makeHost(serverID: "server-1", server: "example.com"))
        let didConnect = await waitUntil { store.connectionStatus == .connected }
        XCTAssertTrue(didConnect)

        await assertLabelUpdateFails(store)

        let didRefresh = await waitUntil {
            let requests = await sender.capturedRequests()
            return requests.count == 8
        }
        XCTAssertTrue(didRefresh)

        let methods = try await sender.capturedRequests().map { try requestMethod(from: $0.asURLRequest()) }
        XCTAssertEqual(methods.filter { $0 == "torrent-set" }.count, 2)
        XCTAssertEqual(methods.filter { $0 == "session-stats" }.count, 2)
        XCTAssertEqual(methods.filter { $0 == "torrent-get" }.count, 2)
        XCTAssertEqual(methods.filter { $0 == "session-get" }.count, 2)
    }

    func testUpdateTorrentLabelsDoesNotScheduleRefreshWhenFirstUpdateFails() async throws {
        let sender = MethodQueueSender(stepsByMethod: [
            "session-stats": [
                .http(statusCode: 200, body: successStatsBody)
            ],
            "torrent-get": [
                .http(statusCode: 200, body: try loadTransmissionFixture(named: "torrent-get.response.json"))
            ],
            "session-get": [
                .http(statusCode: 200, body: try sessionSettingsBody(downloadDir: "/downloads/initial", version: "4.0.0"))
            ],
            "torrent-set": [
                .http(statusCode: 200, body: rpcFailureBody(result: "labels failed"))
            ]
        ])
        let store = makeStore(sender: sender)

        store.setHost(host: makeHost(serverID: "server-1", server: "example.com"))
        let didConnect = await waitUntil { store.connectionStatus == .connected }
        XCTAssertTrue(didConnect)

        await assertLabelUpdateFails(store)

        let didUnexpectedRefresh = await waitUntil(timeout: 0.2) {
            let requests = await sender.capturedRequests()
            return requests.count > 4
        }
        XCTAssertFalse(didUnexpectedRefresh)
    }

    func testSupersededPartialLabelUpdateDoesNotRefreshNewHostAfterHostSwitch() async throws {
        let sender = try makeSupersededPartialLabelUpdateSender()
        let store = makeStore(sender: sender)

        store.setHost(host: makeHost(serverID: "server-1", server: "old.example.com"))
        let didConnectOldHost = await waitUntil { store.defaultDownloadDir == "/downloads/old" }
        XCTAssertTrue(didConnectOldHost)

        let labelTask = Task {
            try? await store.updateTorrentLabels([
                TransmissionTorrentLabelsUpdate(ids: [1], labels: ["alpha"]),
                TransmissionTorrentLabelsUpdate(ids: [2], labels: ["beta"])
            ])
        }

        let didStartOldLabelUpdate = await waitUntil {
            let requests = await sender.capturedRequests()
            return requests.filter { $0.url?.host == "old.example.com" }.count == 5
        }
        XCTAssertTrue(didStartOldLabelUpdate)

        store.setHost(host: makeHost(serverID: "server-2", server: "new.example.com"))
        let didConnectNewHost = await waitUntil {
            store.host?.serverID == "server-2" && store.defaultDownloadDir == "/downloads/new"
        }
        XCTAssertTrue(didConnectNewHost)

        await sender.resume(id: "old-label-failure")
        _ = await labelTask.result

        let requests = await sender.capturedRequests()
        let oldHostRequests = requests.filter { $0.url?.host == "old.example.com" }
        let newHostRequests = requests.filter { $0.url?.host == "new.example.com" }
        XCTAssertEqual(oldHostRequests.count, 5)
        XCTAssertEqual(newHostRequests.count, 3)
        XCTAssertEqual(store.host?.serverID, "server-2")
        XCTAssertEqual(store.defaultDownloadDir, "/downloads/new")
    }
}

private extension TransmissionStoreTorrentOperationTests {
    func makeStore(sender: some TransmissionRPCRequestSending) -> TransmissionStore {
        let factory = TransmissionConnectionFactory(
            transport: TransmissionTransport(sender: sender),
            credentialResolver: TransmissionCredentialResolver(resolvePassword: { source in
                switch source {
                case .resolvedPassword(let password):
                    return password
                case .keychainCredential(let key):
                    return key == "test-key" ? "secret" : ""
                }
            })
        )

        return TransmissionStore(
            connectionFactory: factory,
            snapshotWriter: WidgetSnapshotWriter(
                writeServerIndex: { _ in },
                writeSessionSnapshot: { _, _, _, _, _ in },
                reloadTimelines: { }
            ),
            sleep: { _ in
                try await Task.sleep(nanoseconds: .max)
            },
            persistVersion: { _, _ in }
        )
    }

    func makeSupersededMutationSender() throws -> HostMethodScriptedSender {
        HostMethodScriptedSender(stepsByHostAndMethod: [
            "old.example.com": [
                "session-stats": [
                    .http(statusCode: 200, body: successStatsBody)
                ],
                "torrent-get": [
                    .http(statusCode: 200, body: try loadTransmissionFixture(named: "torrent-get.response.json"))
                ],
                "session-get": [
                    .http(statusCode: 200, body: try sessionSettingsBody(downloadDir: "/downloads/old", version: "4.0.0"))
                ],
                "torrent-remove": [
                    .blocked(id: "old-remove", statusCode: 200, body: successEmptyBody)
                ]
            ],
            "new.example.com": [
                "session-stats": [
                    .http(statusCode: 200, body: successStatsBody)
                ],
                "torrent-get": [
                    .http(statusCode: 200, body: try loadTransmissionFixture(named: "torrent-get.response.json"))
                ],
                "session-get": [
                    .http(statusCode: 200, body: try sessionSettingsBody(downloadDir: "/downloads/new", version: "5.0.0"))
                ]
            ]
        ])
    }

    func makeSupersededPartialLabelUpdateSender() throws -> HostMethodScriptedSender {
        HostMethodScriptedSender(stepsByHostAndMethod: [
            "old.example.com": [
                "session-stats": [
                    .http(statusCode: 200, body: successStatsBody)
                ],
                "torrent-get": [
                    .http(statusCode: 200, body: try loadTransmissionFixture(named: "torrent-get.response.json"))
                ],
                "session-get": [
                    .http(statusCode: 200, body: try sessionSettingsBody(downloadDir: "/downloads/old", version: "4.0.0"))
                ],
                "torrent-set": [
                    .http(statusCode: 200, body: successEmptyBody),
                    .blocked(id: "old-label-failure", statusCode: 200, body: rpcFailureBody(result: "labels failed"))
                ]
            ],
            "new.example.com": [
                "session-stats": [
                    .http(statusCode: 200, body: successStatsBody)
                ],
                "torrent-get": [
                    .http(statusCode: 200, body: try loadTransmissionFixture(named: "torrent-get.response.json"))
                ],
                "session-get": [
                    .http(statusCode: 200, body: try sessionSettingsBody(downloadDir: "/downloads/new", version: "5.0.0"))
                ]
            ]
        ])
    }

    func makeHost(serverID: String, server: String) -> BitDream.Host {
        BitDream.Host(
            serverID: serverID,
            isDefault: false,
            isSSL: false,
            credentialKey: "test-key",
            name: serverID,
            port: 9091,
            server: server,
            username: "demo",
            version: nil
        )
    }

    func waitUntil(
        timeout: TimeInterval = 1,
        _ predicate: @escaping @MainActor () async -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await predicate() {
                return true
            }
            await Task.yield()
        }
        return false
    }
}

private extension CapturedRequest {
    func asURLRequest() -> URLRequest {
        var request = URLRequest(url: url ?? URL(string: "https://example.com")!)
        request.httpMethod = httpMethod
        request.httpBody = body
        return request
    }
}

private func sessionSettingsBody(downloadDir: String, version: String) throws -> String {
    let data = Data(try loadTransmissionFixture(named: "session-get.response.json").utf8)
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    var arguments = try XCTUnwrap(object["arguments"] as? [String: Any])
    arguments["download-dir"] = downloadDir
    arguments["version"] = version
    arguments["blocklist-size"] = 0
    object["arguments"] = arguments
    let encoded = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    return try XCTUnwrap(String(bytes: encoded, encoding: .utf8))
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

private func makeTorrentAddSuccessBody() -> String {
    """
    {
      "arguments": {
        "torrent-added": {
          "hashString": "abcdef1234567890",
          "id": 99,
          "name": "Ubuntu.iso"
        }
      },
      "result": "success"
    }
    """
}

private func rpcFailureBody(result: String) -> String {
    """
    {
      "arguments": {},
      "result": "\(result)"
    }
    """
}

@MainActor
private func assertLabelUpdateFails(_ store: TransmissionStore) async {
    do {
        try await store.updateTorrentLabels([
            TransmissionTorrentLabelsUpdate(ids: [1], labels: ["alpha"]),
            TransmissionTorrentLabelsUpdate(ids: [2], labels: ["beta"])
        ])
        XCTFail("Expected TransmissionError")
    } catch let error as TransmissionTransportFailure {
        ErrorExpectation.rpcFailure(expectedResult: "labels failed").assertMatches(
            error.transmissionError,
            file: #filePath,
            line: #line
        )
    } catch let error as TransmissionError {
        ErrorExpectation.rpcFailure(expectedResult: "labels failed").assertMatches(
            error,
            file: #filePath,
            line: #line
        )
    } catch {
        XCTFail("Expected TransmissionError, got \(error)", file: #filePath, line: #line)
    }
}
