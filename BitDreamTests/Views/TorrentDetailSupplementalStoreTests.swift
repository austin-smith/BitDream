import XCTest
@testable import BitDream

@MainActor
final class TorrentDetailSupplementalStoreTests: XCTestCase {
    func testConcurrentLoadIfIdleCallsLoadOnlyOnceFromIdle() async throws {
        let sender = MethodQueueSender(stepsByMethod: [
            "session-stats": [
                .http(statusCode: 200, body: successStatsBody)
            ],
            "torrent-get": [
                .http(statusCode: 200, body: try loadTransmissionFixture(named: "torrent-get.response.json")),
                .http(statusCode: 200, body: makeTorrentDetailSuccessBody())
            ],
            "session-get": [
                .http(statusCode: 200, body: try sessionSettingsBody(downloadDir: "/downloads/initial", version: "4.0.0"))
            ]
        ])
        let transmissionStore = makeStore(sender: sender)
        let supplementalStore = TorrentDetailSupplementalStore()
        var errors: [String] = []

        transmissionStore.setHost(host: makeHost(serverID: "server-1", server: "example.com"))
        let didConnect = await waitUntil { transmissionStore.connectionStatus == .connected }
        XCTAssertTrue(didConnect)
        let identity = makeIdentity(torrentID: 42, store: transmissionStore)

        let firstLoad = Task { @MainActor in
            await supplementalStore.loadIfIdle(
                for: identity,
                using: transmissionStore
            ) { errors.append($0) }
        }
        let secondLoad = Task { @MainActor in
            await supplementalStore.loadIfIdle(
                for: identity,
                using: transmissionStore
            ) { errors.append($0) }
        }
        await firstLoad.value
        await secondLoad.value

        let methods = try await sender.capturedRequests().map { try requestMethod(from: $0.asURLRequest()) }
        XCTAssertEqual(methods.filter { $0 == "torrent-get" }.count, 2)
        XCTAssertEqual(errors, [])
        XCTAssertEqual(supplementalStore.status, .loaded)
        XCTAssertTrue(supplementalStore.shouldDisplayPayload(for: identity))
    }

    func testLoadIfIdleDoesNotRetryFromFailedStateWithoutPayload() async throws {
        let sender = MethodQueueSender(stepsByMethod: [
            "session-stats": [
                .http(statusCode: 200, body: successStatsBody)
            ],
            "torrent-get": [
                .http(statusCode: 200, body: try loadTransmissionFixture(named: "torrent-get.response.json")),
                .http(statusCode: 200, body: rpcFailureBody(result: "detail load failed"))
            ],
            "session-get": [
                .http(statusCode: 200, body: try sessionSettingsBody(downloadDir: "/downloads/initial", version: "4.0.0"))
            ]
        ])
        let transmissionStore = makeStore(sender: sender)
        let supplementalStore = TorrentDetailSupplementalStore()
        var errors: [String] = []

        transmissionStore.setHost(host: makeHost(serverID: "server-1", server: "example.com"))
        let didConnect = await waitUntil { transmissionStore.connectionStatus == .connected }
        XCTAssertTrue(didConnect)
        let identity = makeIdentity(torrentID: 42, store: transmissionStore)

        await supplementalStore.loadIfIdle(for: identity, using: transmissionStore) { errors.append($0) }
        await supplementalStore.loadIfIdle(for: identity, using: transmissionStore) { errors.append($0) }

        let methods = try await sender.capturedRequests().map { try requestMethod(from: $0.asURLRequest()) }
        XCTAssertEqual(methods.filter { $0 == "torrent-get" }.count, 2)
        XCTAssertEqual(errors, ["detail load failed"])
        XCTAssertEqual(supplementalStore.status, .failed)
        XCTAssertEqual(supplementalStore.payload(for: identity), .empty)
        XCTAssertFalse(supplementalStore.shouldDisplayPayload(for: identity))
    }

    func testExplicitLoadRetriesAfterFailedIdleLoadAndRecovers() async throws {
        let sender = MethodQueueSender(stepsByMethod: [
            "session-stats": [
                .http(statusCode: 200, body: successStatsBody)
            ],
            "torrent-get": [
                .http(statusCode: 200, body: try loadTransmissionFixture(named: "torrent-get.response.json")),
                .http(statusCode: 200, body: rpcFailureBody(result: "detail load failed")),
                .http(statusCode: 200, body: makeTorrentDetailSuccessBody())
            ],
            "session-get": [
                .http(statusCode: 200, body: try sessionSettingsBody(downloadDir: "/downloads/initial", version: "4.0.0"))
            ]
        ])
        let transmissionStore = makeStore(sender: sender)
        let supplementalStore = TorrentDetailSupplementalStore()
        var errors: [String] = []

        transmissionStore.setHost(host: makeHost(serverID: "server-1", server: "example.com"))
        let didConnect = await waitUntil { transmissionStore.connectionStatus == .connected }
        XCTAssertTrue(didConnect)
        let identity = makeIdentity(torrentID: 42, store: transmissionStore)

        await supplementalStore.loadIfIdle(for: identity, using: transmissionStore) { errors.append($0) }
        XCTAssertEqual(supplementalStore.status, .failed)

        await supplementalStore.load(for: identity, using: transmissionStore) { errors.append($0) }

        let methods = try await sender.capturedRequests().map { try requestMethod(from: $0.asURLRequest()) }
        XCTAssertEqual(methods.filter { $0 == "torrent-get" }.count, 3)
        XCTAssertEqual(errors, ["detail load failed"])
        XCTAssertEqual(supplementalStore.status, .loaded)
        XCTAssertTrue(supplementalStore.shouldDisplayPayload(for: identity))
        XCTAssertEqual(supplementalStore.payload(for: identity).files.map(\.name), ["Ubuntu.iso"])
    }

    func testBackgroundRefreshFailureRetainsPayloadWithoutReportingError() async throws {
        let sender = MethodQueueSender(stepsByMethod: [
            "session-stats": [
                .http(statusCode: 200, body: successStatsBody)
            ],
            "torrent-get": [
                .http(statusCode: 200, body: try loadTransmissionFixture(named: "torrent-get.response.json")),
                .http(statusCode: 200, body: makeTorrentDetailSuccessBody()),
                .http(statusCode: 200, body: rpcFailureBody(result: "background refresh failed"))
            ],
            "session-get": [
                .http(statusCode: 200, body: try sessionSettingsBody(downloadDir: "/downloads/initial", version: "4.0.0"))
            ]
        ])
        let transmissionStore = makeStore(sender: sender)
        let supplementalStore = TorrentDetailSupplementalStore()
        var errors: [String] = []

        transmissionStore.setHost(host: makeHost(serverID: "server-1", server: "example.com"))
        let didConnect = await waitUntil { transmissionStore.connectionStatus == .connected }
        XCTAssertTrue(didConnect)
        let identity = makeIdentity(torrentID: 42, store: transmissionStore)

        await supplementalStore.refresh(for: identity, using: transmissionStore) { errors.append($0) }
        let loadedPayload = supplementalStore.payload(for: identity)
        await supplementalStore.refresh(for: identity, using: transmissionStore) { errors.append($0) }

        XCTAssertEqual(errors, [])
        XCTAssertEqual(supplementalStore.status, .failed)
        XCTAssertEqual(supplementalStore.payload(for: identity), loadedPayload)
        XCTAssertTrue(supplementalStore.shouldDisplayPayload(for: identity))
    }

    func testRepeatedInitialRefreshFailuresReportOnlyFirstError() async throws {
        let sender = MethodQueueSender(stepsByMethod: [
            "session-stats": [
                .http(statusCode: 200, body: successStatsBody)
            ],
            "torrent-get": [
                .http(statusCode: 200, body: try loadTransmissionFixture(named: "torrent-get.response.json")),
                .http(statusCode: 200, body: rpcFailureBody(result: "first failure")),
                .http(statusCode: 200, body: rpcFailureBody(result: "second failure"))
            ],
            "session-get": [
                .http(statusCode: 200, body: try sessionSettingsBody(downloadDir: "/downloads/initial", version: "4.0.0"))
            ]
        ])
        let transmissionStore = makeStore(sender: sender)
        let supplementalStore = TorrentDetailSupplementalStore()
        var errors: [String] = []

        transmissionStore.setHost(host: makeHost(serverID: "server-1", server: "example.com"))
        let didConnect = await waitUntil { transmissionStore.connectionStatus == .connected }
        XCTAssertTrue(didConnect)
        let identity = makeIdentity(torrentID: 42, store: transmissionStore)

        await supplementalStore.refresh(for: identity, using: transmissionStore) { errors.append($0) }
        await supplementalStore.refresh(for: identity, using: transmissionStore) { errors.append($0) }

        XCTAssertEqual(errors, ["first failure"])
        XCTAssertEqual(supplementalStore.status, .failed)
        XCTAssertFalse(supplementalStore.shouldDisplayPayload(for: identity))
    }

    func testRefreshReplacesPayloadForSameTorrent() async throws {
        let sender = MethodQueueSender(stepsByMethod: [
            "session-stats": [
                .http(statusCode: 200, body: successStatsBody)
            ],
            "torrent-get": [
                .http(statusCode: 200, body: try loadTransmissionFixture(named: "torrent-get.response.json")),
                .http(statusCode: 200, body: makeTorrentDetailSuccessBody(bytesCompleted: 1)),
                .http(statusCode: 200, body: makeTorrentDetailSuccessBody(bytesCompleted: 2))
            ],
            "session-get": [
                .http(statusCode: 200, body: try sessionSettingsBody(downloadDir: "/downloads/initial", version: "4.0.0"))
            ]
        ])
        let transmissionStore = makeStore(sender: sender)
        let supplementalStore = TorrentDetailSupplementalStore()
        var errors: [String] = []

        transmissionStore.setHost(host: makeHost(serverID: "server-1", server: "example.com"))
        let didConnect = await waitUntil { transmissionStore.connectionStatus == .connected }
        XCTAssertTrue(didConnect)
        let identity = makeIdentity(torrentID: 42, store: transmissionStore)

        await supplementalStore.refresh(for: identity, using: transmissionStore) { errors.append($0) }
        XCTAssertEqual(supplementalStore.payload(for: identity).files.first?.bytesCompleted, 1)

        await supplementalStore.refresh(for: identity, using: transmissionStore) { errors.append($0) }

        XCTAssertEqual(errors, [])
        XCTAssertEqual(supplementalStore.status, .loaded)
        XCTAssertEqual(supplementalStore.payload(for: identity).files.first?.bytesCompleted, 2)
    }

    func testPayloadForActiveTorrentReflectsCommittedWantedMutationWithoutReload() {
        let store = makeLoadedStore()

        XCTAssertTrue(
            store.applyCommittedFileStatsMutation(
                .wanted(false),
                for: makeTestTorrentDetailIdentity(42),
                fileIndices: [0]
            )
        )

        let payload = store.payload(for: makeTestTorrentDetailIdentity(42))
        XCTAssertFalse(payload.fileStats[0].wanted)
        XCTAssertEqual(payload.fileStats[0].priority, FilePriority.normal.rawValue)
        XCTAssertEqual(payload.fileStats[1], makeDetailSnapshot().fileStats[1])
    }

    func testApplyCommittedPriorityMutationUpdatesCachedPayload() {
        let store = makeLoadedStore()

        XCTAssertTrue(
            store.applyCommittedFileStatsMutation(
                .priority(.high),
                for: makeTestTorrentDetailIdentity(42),
                fileIndices: [1]
            )
        )

        let payload = store.payload(for: makeTestTorrentDetailIdentity(42))
        XCTAssertEqual(payload.fileStats[1].priority, FilePriority.high.rawValue)
        XCTAssertFalse(payload.fileStats[1].wanted)
        XCTAssertEqual(payload.fileStats[0], makeDetailSnapshot().fileStats[0])
    }

    func testApplyCommittedMutationForDifferentTorrentIsNoOp() {
        let store = makeLoadedStore()
        let initialPayload = store.payload(for: makeTestTorrentDetailIdentity(42))

        XCTAssertFalse(
            store.applyCommittedFileStatsMutation(
                .wanted(false),
                for: makeTestTorrentDetailIdentity(99),
                fileIndices: [0]
            )
        )

        XCTAssertEqual(store.payload(for: makeTestTorrentDetailIdentity(42)), initialPayload)
    }

    func testApplyCommittedMutationWithOutOfRangeIndicesIsNoOp() {
        let store = makeLoadedStore()
        let initialPayload = store.payload(for: makeTestTorrentDetailIdentity(42))

        XCTAssertFalse(
            store.applyCommittedFileStatsMutation(
                .priority(.low),
                for: makeTestTorrentDetailIdentity(42),
                fileIndices: [10]
            )
        )

        XCTAssertEqual(store.payload(for: makeTestTorrentDetailIdentity(42)), initialPayload)
    }
}

@MainActor
final class TorrentDetailIdentityStoreTests: XCTestCase {
    func testLoadRejectsIdentityFromPreviousConnectionGeneration() async throws {
        let sender = MethodQueueSender(stepsByMethod: [
            "session-stats": [
                .http(statusCode: 200, body: successStatsBody)
            ],
            "torrent-get": [
                .http(statusCode: 200, body: try loadTransmissionFixture(named: "torrent-get.response.json"))
            ],
            "session-get": [
                .http(
                    statusCode: 200,
                    body: try sessionSettingsBody(downloadDir: "/downloads/initial", version: "4.0.0")
                )
            ]
        ])
        let transmissionStore = makeStore(sender: sender)
        let supplementalStore = TorrentDetailSupplementalStore()
        var errors: [String] = []

        transmissionStore.setHost(host: makeHost(serverID: "server-1", server: "example.com"))
        let didConnect = await waitUntil { transmissionStore.connectionStatus == .connected }
        XCTAssertTrue(didConnect)
        let staleIdentity = makeTestTorrentDetailIdentity(42, connectionGeneration: UUID())

        await supplementalStore.load(for: staleIdentity, using: transmissionStore) { errors.append($0) }

        let methods = try await sender.capturedRequests().map { try requestMethod(from: $0.asURLRequest()) }
        XCTAssertEqual(methods.filter { $0 == "torrent-get" }.count, 1)
        XCTAssertEqual(errors, [])
        XCTAssertEqual(supplementalStore.status, .idle)
        XCTAssertEqual(supplementalStore.payload(for: staleIdentity), .empty)
    }
}

func makeTorrentDetailSuccessBody(bytesCompleted: Int = 1) -> String {
    """
        {
          "arguments": {
                "torrents": [
                  {
                    "files": [
                      { "bytesCompleted": \(bytesCompleted), "length": 2, "name": "Ubuntu.iso" }
                    ],
                    "fileStats": [
                      { "bytesCompleted": \(bytesCompleted), "wanted": true, "priority": 0 }
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

private extension TorrentDetailSupplementalStoreTests {
    func makeIdentity(torrentID: Int, store: TransmissionStore) -> TorrentDetailIdentity {
        TorrentDetailIdentity(
            torrentID: torrentID,
            connectionGeneration: store.torrentDetailRefreshTrigger.connectionGeneration
        )
    }

    func rpcFailureBody(result: String) -> String {
        """
        {
          "arguments": {},
          "result": "\(result)"
        }
        """
    }

    func makeLoadedStore(torrentID: Int = 42) -> TorrentDetailSupplementalStore {
        var state = TorrentDetailSupplementalState()
        let identity = makeTestTorrentDetailIdentity(torrentID)
        let generation = state.beginLoading(for: identity)
        XCTAssertTrue(
            state.apply(
                snapshot: makeDetailSnapshot(),
                for: identity,
                generation: generation
            )
        )
        return TorrentDetailSupplementalStore(state: state)
    }

    func makeDetailSnapshot() -> TransmissionTorrentDetailSnapshot {
        TransmissionTorrentDetailSnapshot(
            files: [
                TorrentFile(bytesCompleted: 50, length: 100, name: "Ubuntu.iso"),
                TorrentFile(bytesCompleted: 0, length: 20, name: "Extras/Readme.txt")
            ],
            fileStats: [
                TorrentFileStats(
                    bytesCompleted: 50,
                    wanted: true,
                    priority: FilePriority.normal.rawValue
                ),
                TorrentFileStats(
                    bytesCompleted: 0,
                    wanted: false,
                    priority: FilePriority.low.rawValue
                )
            ],
            peers: [],
            peersFrom: nil,
            pieceCount: 0,
            pieceSize: 0,
            piecesBitfieldBase64: ""
        )
    }
}
