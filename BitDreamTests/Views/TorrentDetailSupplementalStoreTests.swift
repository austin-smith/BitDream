import XCTest
@testable import BitDream

@MainActor
final class TorrentDetailSupplementalStoreTests: XCTestCase {
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
