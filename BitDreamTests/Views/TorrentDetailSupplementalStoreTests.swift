import XCTest
@testable import BitDream

@MainActor
final class TorrentDetailSupplementalStoreTests: XCTestCase {
    func testLoadIfIdleLoadsOnlyOnceFromIdle() async throws {
        let sender = MethodQueueSender(stepsByMethod: [
            "session-stats": [
                .http(statusCode: 200, body: successStatsBody)
            ],
            "torrent-get": [
                .http(statusCode: 200, body: try loadTransmissionFixture(named: "torrent-get.response.json")),
                .http(statusCode: 200, body: makeTorrentDetailSuccessBody()),
                .http(statusCode: 200, body: makeTorrentDetailSuccessBody()),
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

        await supplementalStore.loadIfIdle(for: 42, using: transmissionStore) { errors.append($0) }
        await supplementalStore.loadIfIdle(for: 42, using: transmissionStore) { errors.append($0) }

        let methods = try await sender.capturedRequests().map { try requestMethod(from: $0.asURLRequest()) }
        XCTAssertEqual(methods.filter { $0 == "torrent-get" }.count, 4)
        XCTAssertEqual(errors, [])
        XCTAssertEqual(supplementalStore.status, .loaded)
        XCTAssertTrue(supplementalStore.shouldDisplayPayload(for: 42))
    }

    func testLoadIfIdleDoesNotRetryFromFailedStateWithoutPayload() async throws {
        let sender = MethodQueueSender(stepsByMethod: [
            "session-stats": [
                .http(statusCode: 200, body: successStatsBody)
            ],
            "torrent-get": [
                .http(statusCode: 200, body: try loadTransmissionFixture(named: "torrent-get.response.json")),
                .http(statusCode: 200, body: makeTorrentDetailSuccessBody()),
                .http(statusCode: 200, body: makeTorrentDetailSuccessBody()),
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

        await supplementalStore.loadIfIdle(for: 42, using: transmissionStore) { errors.append($0) }
        await supplementalStore.loadIfIdle(for: 42, using: transmissionStore) { errors.append($0) }

        let methods = try await sender.capturedRequests().map { try requestMethod(from: $0.asURLRequest()) }
        XCTAssertEqual(methods.filter { $0 == "torrent-get" }.count, 4)
        XCTAssertEqual(errors, ["detail load failed"])
        XCTAssertEqual(supplementalStore.status, .failed)
        XCTAssertEqual(supplementalStore.payload(for: 42), .empty)
        XCTAssertFalse(supplementalStore.shouldDisplayPayload(for: 42))
    }

    func testExplicitLoadRetriesAfterFailedIdleLoadAndRecovers() async throws {
        let sender = MethodQueueSender(stepsByMethod: [
            "session-stats": [
                .http(statusCode: 200, body: successStatsBody)
            ],
            "torrent-get": [
                .http(statusCode: 200, body: try loadTransmissionFixture(named: "torrent-get.response.json")),
                .http(statusCode: 200, body: makeTorrentDetailSuccessBody()),
                .http(statusCode: 200, body: makeTorrentDetailSuccessBody()),
                .http(statusCode: 200, body: rpcFailureBody(result: "detail load failed")),
                .http(statusCode: 200, body: makeTorrentDetailSuccessBody()),
                .http(statusCode: 200, body: makeTorrentDetailSuccessBody()),
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

        await supplementalStore.loadIfIdle(for: 42, using: transmissionStore) { errors.append($0) }
        XCTAssertEqual(supplementalStore.status, .failed)

        await supplementalStore.load(for: 42, using: transmissionStore) { errors.append($0) }

        let methods = try await sender.capturedRequests().map { try requestMethod(from: $0.asURLRequest()) }
        XCTAssertEqual(methods.filter { $0 == "torrent-get" }.count, 7)
        XCTAssertEqual(errors, ["detail load failed"])
        XCTAssertEqual(supplementalStore.status, .loaded)
        XCTAssertTrue(supplementalStore.shouldDisplayPayload(for: 42))
        XCTAssertEqual(supplementalStore.payload(for: 42).files.map(\.name), ["Ubuntu.iso"])
    }

    func testPayloadForActiveTorrentReflectsCommittedWantedMutationWithoutReload() {
        let store = makeLoadedStore()

        XCTAssertTrue(
            store.applyCommittedFileStatsMutation(
                .wanted(false),
                for: 42,
                fileIndices: [0]
            )
        )

        let payload = store.payload(for: 42)
        XCTAssertFalse(payload.fileStats[0].wanted)
        XCTAssertEqual(payload.fileStats[0].priority, FilePriority.normal.rawValue)
        XCTAssertEqual(payload.fileStats[1], makeDetailSnapshot().fileStats[1])
    }

    func testApplyCommittedPriorityMutationUpdatesCachedPayload() {
        let store = makeLoadedStore()

        XCTAssertTrue(
            store.applyCommittedFileStatsMutation(
                .priority(.high),
                for: 42,
                fileIndices: [1]
            )
        )

        let payload = store.payload(for: 42)
        XCTAssertEqual(payload.fileStats[1].priority, FilePriority.high.rawValue)
        XCTAssertFalse(payload.fileStats[1].wanted)
        XCTAssertEqual(payload.fileStats[0], makeDetailSnapshot().fileStats[0])
    }

    func testApplyCommittedMutationForDifferentTorrentIsNoOp() {
        let store = makeLoadedStore()
        let initialPayload = store.payload(for: 42)

        XCTAssertFalse(
            store.applyCommittedFileStatsMutation(
                .wanted(false),
                for: 99,
                fileIndices: [0]
            )
        )

        XCTAssertEqual(store.payload(for: 42), initialPayload)
    }

    func testApplyCommittedMutationWithOutOfRangeIndicesIsNoOp() {
        let store = makeLoadedStore()
        let initialPayload = store.payload(for: 42)

        XCTAssertFalse(
            store.applyCommittedFileStatsMutation(
                .priority(.low),
                for: 42,
                fileIndices: [10]
            )
        )

        XCTAssertEqual(store.payload(for: 42), initialPayload)
    }
}

private extension TorrentDetailSupplementalStoreTests {
    func makeTorrentDetailSuccessBody() -> String {
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
        let generation = state.beginLoading(for: torrentID)
        XCTAssertTrue(
            state.apply(
                snapshot: makeDetailSnapshot(),
                for: torrentID,
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
