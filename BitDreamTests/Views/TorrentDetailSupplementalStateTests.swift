import XCTest
@testable import BitDream

final class TorrentDetailSupplementalStateTests: XCTestCase {
    func testBeginLoadingClearsPayloadForNewTorrentAndTracksActiveTorrent() {
        var state = TorrentDetailSupplementalState()
        let generation = state.beginLoading(for: 42)

        XCTAssertEqual(state.activeTorrentID, 42)
        XCTAssertEqual(state.activeRequestGeneration, generation)
        XCTAssertEqual(state.status, .loading)
        XCTAssertEqual(state.payload, .empty)
        XCTAssertFalse(state.shouldDisplayPayload(for: 42))
    }

    func testApplySnapshotPopulatesPayloadAndPieceCount() {
        var state = TorrentDetailSupplementalState()
        let snapshot = makeSnapshot(
            pieceCount: 3,
            piecesBitfieldBase64: Data([0b1010_0000]).base64EncodedString()
        )

        let generation = state.beginLoading(for: 7)
        let didApply = state.apply(snapshot: snapshot, for: 7, generation: generation)

        XCTAssertTrue(didApply)
        XCTAssertEqual(state.status, .loaded)
        XCTAssertEqual(state.payload.files, snapshot.files)
        XCTAssertEqual(state.payload.fileStats, snapshot.fileStats)
        XCTAssertEqual(state.payload.peers, snapshot.peers)
        XCTAssertEqual(state.payload.peersFrom, snapshot.peersFrom)
        XCTAssertEqual(state.payload.pieceCount, 3)
        XCTAssertEqual(state.payload.piecesHaveCount, 2)
        XCTAssertTrue(state.shouldDisplayPayload(for: 7))
    }

    func testApplySnapshotIgnoresStaleRequest() {
        var state = TorrentDetailSupplementalState()
        let oldSnapshot = makeSnapshot(fileName: "old-file")
        let newSnapshot = makeSnapshot(fileName: "new-file")

        let oldGeneration = state.beginLoading(for: 1)
        XCTAssertTrue(state.apply(snapshot: oldSnapshot, for: 1, generation: oldGeneration))

        let newGeneration = state.beginLoading(for: 2)
        let didApplyStaleSnapshot = state.apply(
            snapshot: oldSnapshot,
            for: 1,
            generation: oldGeneration
        )
        let didApplyCurrentSnapshot = state.apply(
            snapshot: newSnapshot,
            for: 2,
            generation: newGeneration
        )

        XCTAssertFalse(didApplyStaleSnapshot)
        XCTAssertTrue(didApplyCurrentSnapshot)
        XCTAssertEqual(state.activeTorrentID, 2)
        XCTAssertEqual(state.activeRequestGeneration, newGeneration)
        XCTAssertEqual(state.status, .loaded)
        XCTAssertEqual(state.payload.files.map(\.name), ["new-file"])
        XCTAssertTrue(state.shouldDisplayPayload(for: 2))
    }

    func testBeginLoadingForSameTorrentPreservesLoadedPayload() {
        var state = TorrentDetailSupplementalState()
        let snapshot = makeSnapshot()

        let firstGeneration = state.beginLoading(for: 11)
        XCTAssertTrue(state.apply(snapshot: snapshot, for: 11, generation: firstGeneration))

        let secondGeneration = state.beginLoading(for: 11)

        XCTAssertEqual(state.activeTorrentID, 11)
        XCTAssertEqual(state.activeRequestGeneration, secondGeneration)
        XCTAssertNotEqual(firstGeneration, secondGeneration)
        XCTAssertEqual(state.status, .loading)
        XCTAssertEqual(state.payload.files, snapshot.files)
        XCTAssertTrue(state.shouldDisplayPayload(for: 11))
    }

    func testBeginLoadingForDifferentTorrentClearsLoadedPayload() {
        var state = TorrentDetailSupplementalState()
        let snapshot = makeSnapshot()

        let firstGeneration = state.beginLoading(for: 11)
        XCTAssertTrue(state.apply(snapshot: snapshot, for: 11, generation: firstGeneration))

        let secondGeneration = state.beginLoading(for: 12)

        XCTAssertEqual(state.activeTorrentID, 12)
        XCTAssertEqual(state.activeRequestGeneration, secondGeneration)
        XCTAssertEqual(state.status, .loading)
        XCTAssertEqual(state.payload, .empty)
        XCTAssertFalse(state.shouldDisplayPayload(for: 12))
    }

    func testMarkFailedPreservesPayloadForActiveRequest() {
        var state = TorrentDetailSupplementalState()
        let snapshot = makeSnapshot()

        let generation = state.beginLoading(for: 11)
        XCTAssertTrue(state.apply(snapshot: snapshot, for: 11, generation: generation))

        let didMarkFailure = state.markFailed(for: 11, generation: generation)

        XCTAssertTrue(didMarkFailure)
        XCTAssertEqual(state.status, .failed)
        XCTAssertEqual(state.payload.files, snapshot.files)
        XCTAssertTrue(state.shouldDisplayPayload(for: 11))
    }

    func testMarkFailedIgnoresStaleRequest() {
        var state = TorrentDetailSupplementalState()

        let staleGeneration = state.beginLoading(for: 3)
        let currentGeneration = state.beginLoading(for: 4)

        let didMarkFailure = state.markFailed(for: 3, generation: staleGeneration)

        XCTAssertFalse(didMarkFailure)
        XCTAssertEqual(state.activeTorrentID, 4)
        XCTAssertEqual(state.activeRequestGeneration, currentGeneration)
        XCTAssertEqual(state.status, .loading)
        XCTAssertEqual(state.payload, .empty)
        XCTAssertFalse(state.shouldDisplayPayload(for: 4))
    }

    func testApplySnapshotRecoversAfterFailureWhileRetainingPayload() {
        var state = TorrentDetailSupplementalState()
        let oldSnapshot = makeSnapshot(fileName: "old-file")
        let newSnapshot = makeSnapshot(fileName: "new-file")

        let firstGeneration = state.beginLoading(for: 7)
        XCTAssertTrue(state.apply(snapshot: oldSnapshot, for: 7, generation: firstGeneration))
        XCTAssertTrue(state.markFailed(for: 7, generation: firstGeneration))
        let secondGeneration = state.beginLoading(for: 7)

        let didApply = state.apply(snapshot: newSnapshot, for: 7, generation: secondGeneration)

        XCTAssertTrue(didApply)
        XCTAssertEqual(state.status, .loaded)
        XCTAssertEqual(state.payload.files.map(\.name), ["new-file"])
        XCTAssertTrue(state.shouldDisplayPayload(for: 7))
    }

    func testApplySnapshotIgnoresOlderGenerationForSameTorrent() {
        var state = TorrentDetailSupplementalState()
        let olderSnapshot = makeSnapshot(fileName: "older-file")
        let newerSnapshot = makeSnapshot(fileName: "newer-file")

        let olderGeneration = state.beginLoading(for: 9)
        let newerGeneration = state.beginLoading(for: 9)

        let didApplyOlderSnapshot = state.apply(
            snapshot: olderSnapshot,
            for: 9,
            generation: olderGeneration
        )
        let didApplyNewerSnapshot = state.apply(
            snapshot: newerSnapshot,
            for: 9,
            generation: newerGeneration
        )

        XCTAssertFalse(didApplyOlderSnapshot)
        XCTAssertTrue(didApplyNewerSnapshot)
        XCTAssertEqual(state.activeTorrentID, 9)
        XCTAssertEqual(state.activeRequestGeneration, newerGeneration)
        XCTAssertEqual(state.status, .loaded)
        XCTAssertEqual(state.payload.files.map(\.name), ["newer-file"])
        XCTAssertTrue(state.shouldDisplayPayload(for: 9))
    }

    func testMarkFailedIgnoresOlderGenerationForSameTorrent() {
        var state = TorrentDetailSupplementalState()
        let snapshot = makeSnapshot(fileName: "retained-file")

        let initialGeneration = state.beginLoading(for: 13)
        XCTAssertTrue(state.apply(snapshot: snapshot, for: 13, generation: initialGeneration))

        let staleGeneration = state.beginLoading(for: 13)
        let currentGeneration = state.beginLoading(for: 13)

        let didMarkStaleFailure = state.markFailed(for: 13, generation: staleGeneration)

        XCTAssertFalse(didMarkStaleFailure)
        XCTAssertEqual(state.activeTorrentID, 13)
        XCTAssertEqual(state.activeRequestGeneration, currentGeneration)
        XCTAssertEqual(state.status, .loading)
        XCTAssertEqual(state.payload.files.map(\.name), ["retained-file"])
        XCTAssertTrue(state.shouldDisplayPayload(for: 13))
    }

    func testMarkCancelledRestoresIdleStateWhenNoPayloadExists() {
        var state = TorrentDetailSupplementalState()

        let generation = state.beginLoading(for: 21)
        let didMarkCancellation = state.markCancelled(for: 21, generation: generation)

        XCTAssertTrue(didMarkCancellation)
        XCTAssertEqual(state.activeTorrentID, 21)
        XCTAssertEqual(state.activeRequestGeneration, generation)
        XCTAssertEqual(state.status, .idle)
        XCTAssertEqual(state.payload, .empty)
        XCTAssertFalse(state.shouldDisplayPayload(for: 21))
    }

    func testMarkCancelledRestoresLoadedStateWhenPayloadExists() {
        var state = TorrentDetailSupplementalState()
        let snapshot = makeSnapshot(fileName: "retained-file")

        let firstGeneration = state.beginLoading(for: 22)
        XCTAssertTrue(state.apply(snapshot: snapshot, for: 22, generation: firstGeneration))
        let secondGeneration = state.beginLoading(for: 22)

        let didMarkCancellation = state.markCancelled(for: 22, generation: secondGeneration)

        XCTAssertTrue(didMarkCancellation)
        XCTAssertEqual(state.activeTorrentID, 22)
        XCTAssertEqual(state.activeRequestGeneration, secondGeneration)
        XCTAssertEqual(state.status, .loaded)
        XCTAssertEqual(state.payload.files.map(\.name), ["retained-file"])
        XCTAssertTrue(state.shouldDisplayPayload(for: 22))
    }

    func testMarkCancelledIgnoresOlderGenerationForSameTorrent() {
        var state = TorrentDetailSupplementalState()
        let snapshot = makeSnapshot(fileName: "retained-file")

        let firstGeneration = state.beginLoading(for: 23)
        XCTAssertTrue(state.apply(snapshot: snapshot, for: 23, generation: firstGeneration))
        let staleGeneration = state.beginLoading(for: 23)
        let currentGeneration = state.beginLoading(for: 23)

        let didMarkCancellation = state.markCancelled(for: 23, generation: staleGeneration)

        XCTAssertFalse(didMarkCancellation)
        XCTAssertEqual(state.activeTorrentID, 23)
        XCTAssertEqual(state.activeRequestGeneration, currentGeneration)
        XCTAssertEqual(state.status, .loading)
        XCTAssertEqual(state.payload.files.map(\.name), ["retained-file"])
        XCTAssertTrue(state.shouldDisplayPayload(for: 23))
    }

    func testShouldDisplayPayloadRequiresMatchingActiveTorrentID() {
        var state = TorrentDetailSupplementalState()
        let snapshot = makeSnapshot(fileName: "retained-file")

        let generation = state.beginLoading(for: 24)
        XCTAssertTrue(state.apply(snapshot: snapshot, for: 24, generation: generation))

        XCTAssertTrue(state.shouldDisplayPayload(for: 24))
        XCTAssertFalse(state.shouldDisplayPayload(for: 25))
        XCTAssertEqual(state.visiblePayload(for: 24).files.map(\.name), ["retained-file"])
        XCTAssertEqual(state.visiblePayload(for: 25), .empty)
    }

    func testPiecesSectionStateResolvesLoadingWhenPayloadIsUnavailable() {
        let state = TorrentPiecesSectionState.resolve(
            status: .idle,
            payload: .empty,
            shouldDisplayPayload: false
        )

        XCTAssertEqual(state, .loading)
    }

    func testPiecesSectionStateResolvesContentWhenPayloadHasRenderablePieces() {
        let payload = TorrentDetailSupplementalPayload(snapshot: makeSnapshot(pieceCount: 3))

        let state = TorrentPiecesSectionState.resolve(
            status: .loaded,
            payload: payload,
            shouldDisplayPayload: true
        )

        XCTAssertEqual(state, .content(payload))
    }

    func testPiecesSectionStateResolvesEmptyWhenLoadedPayloadHasNoRenderablePieces() {
        let payload = TorrentDetailSupplementalPayload(
            snapshot: makeSnapshot(pieceCount: 0, piecesBitfieldBase64: "")
        )

        let state = TorrentPiecesSectionState.resolve(
            status: .loaded,
            payload: payload,
            shouldDisplayPayload: true
        )

        XCTAssertEqual(state, .empty)
    }

    func testPiecesSectionStateResolvesFailedWhenInitialLoadFailsWithoutPayload() {
        let state = TorrentPiecesSectionState.resolve(
            status: .failed,
            payload: .empty,
            shouldDisplayPayload: false
        )

        XCTAssertEqual(state, .failed)
    }

    func testPiecesSectionStateKeepsContentVisibleWhenRefreshFailsAfterSuccessfulLoad() {
        let payload = TorrentDetailSupplementalPayload(snapshot: makeSnapshot(pieceCount: 3))

        let state = TorrentPiecesSectionState.resolve(
            status: .failed,
            payload: payload,
            shouldDisplayPayload: true
        )

        XCTAssertEqual(state, .content(payload))
    }
}

private func makeSnapshot(
    fileName: String = "sample-file",
    pieceCount: Int = 1,
    piecesBitfieldBase64: String = Data([0b1000_0000]).base64EncodedString()
) -> TransmissionTorrentDetailSnapshot {
    TransmissionTorrentDetailSnapshot(
        files: [
            TorrentFile(
                bytesCompleted: 512,
                length: 1024,
                name: fileName
            )
        ],
        fileStats: [
            TorrentFileStats(
                bytesCompleted: 512,
                wanted: true,
                priority: 0
            )
        ],
        peers: [
            Peer(
                address: "127.0.0.1",
                clientName: "BitDreamTests",
                clientIsChoked: false,
                clientIsInterested: true,
                flagStr: "D",
                isDownloadingFrom: true,
                isEncrypted: false,
                isIncoming: false,
                isUploadingTo: false,
                isUTP: false,
                peerIsChoked: false,
                peerIsInterested: true,
                port: 51413,
                progress: 0.5,
                rateToClient: 100,
                rateToPeer: 0
            )
        ],
        peersFrom: PeersFrom(
            fromCache: 0,
            fromDht: 1,
            fromIncoming: 0,
            fromLpd: 0,
            fromLtep: 0,
            fromPex: 0,
            fromTracker: 1
        ),
        pieceCount: pieceCount,
        pieceSize: 1024,
        piecesBitfieldBase64: piecesBitfieldBase64
    )
}
