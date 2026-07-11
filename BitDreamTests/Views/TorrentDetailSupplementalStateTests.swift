import XCTest
@testable import BitDream

final class TorrentDetailSupplementalStateTests: XCTestCase {
    func testBeginLoadingClearsPayloadForNewTorrentAndTracksActiveTorrent() {
        var state = TorrentDetailSupplementalState()
        let generation = state.beginLoading(for: makeTestTorrentDetailIdentity(42))

        XCTAssertEqual(state.activeIdentity, makeTestTorrentDetailIdentity(42))
        XCTAssertEqual(state.activeRequestGeneration, generation)
        XCTAssertEqual(state.status, .loading)
        XCTAssertEqual(state.payload, .empty)
        XCTAssertFalse(state.shouldDisplayPayload(for: makeTestTorrentDetailIdentity(42)))
        XCTAssertFalse(state.hasReportedInitialLoadError)
    }

    func testApplySnapshotPopulatesPayloadAndPieceCount() {
        var state = TorrentDetailSupplementalState()
        let snapshot = makeSnapshot(
            pieceCount: 3,
            piecesBitfieldBase64: Data([0b1010_0000]).base64EncodedString()
        )

        let generation = state.beginLoading(for: makeTestTorrentDetailIdentity(7))
        let didApply = state.apply(snapshot: snapshot, for: makeTestTorrentDetailIdentity(7), generation: generation)

        XCTAssertTrue(didApply)
        XCTAssertEqual(state.status, .loaded)
        XCTAssertEqual(state.payload.files, snapshot.files)
        XCTAssertEqual(state.payload.fileStats, snapshot.fileStats)
        XCTAssertEqual(state.payload.peers, snapshot.peers)
        XCTAssertEqual(state.payload.peersFrom, snapshot.peersFrom)
        XCTAssertEqual(state.payload.pieceCount, 3)
        XCTAssertEqual(state.payload.piecesHaveCount, 2)
        XCTAssertTrue(state.shouldDisplayPayload(for: makeTestTorrentDetailIdentity(7)))
    }

    func testApplySnapshotIgnoresStaleRequest() {
        var state = TorrentDetailSupplementalState()
        let oldSnapshot = makeSnapshot(fileName: "old-file")
        let newSnapshot = makeSnapshot(fileName: "new-file")

        let oldGeneration = state.beginLoading(for: makeTestTorrentDetailIdentity(1))
        XCTAssertTrue(state.apply(snapshot: oldSnapshot, for: makeTestTorrentDetailIdentity(1), generation: oldGeneration))

        let newGeneration = state.beginLoading(for: makeTestTorrentDetailIdentity(2))
        let didApplyStaleSnapshot = state.apply(
            snapshot: oldSnapshot,
            for: makeTestTorrentDetailIdentity(1),
            generation: oldGeneration
        )
        let didApplyCurrentSnapshot = state.apply(
            snapshot: newSnapshot,
            for: makeTestTorrentDetailIdentity(2),
            generation: newGeneration
        )

        XCTAssertFalse(didApplyStaleSnapshot)
        XCTAssertTrue(didApplyCurrentSnapshot)
        XCTAssertEqual(state.activeIdentity, makeTestTorrentDetailIdentity(2))
        XCTAssertEqual(state.activeRequestGeneration, newGeneration)
        XCTAssertEqual(state.status, .loaded)
        XCTAssertEqual(state.payload.files.map(\.name), ["new-file"])
        XCTAssertTrue(state.shouldDisplayPayload(for: makeTestTorrentDetailIdentity(2)))
    }

    func testBeginLoadingForSameTorrentPreservesLoadedPayload() {
        var state = TorrentDetailSupplementalState()
        let snapshot = makeSnapshot()

        let firstGeneration = state.beginLoading(for: makeTestTorrentDetailIdentity(11))
        XCTAssertTrue(state.apply(snapshot: snapshot, for: makeTestTorrentDetailIdentity(11), generation: firstGeneration))

        let secondGeneration = state.beginLoading(for: makeTestTorrentDetailIdentity(11))

        XCTAssertEqual(state.activeIdentity, makeTestTorrentDetailIdentity(11))
        XCTAssertEqual(state.activeRequestGeneration, secondGeneration)
        XCTAssertNotEqual(firstGeneration, secondGeneration)
        XCTAssertEqual(state.status, .loading)
        XCTAssertEqual(state.payload.files, snapshot.files)
        XCTAssertTrue(state.shouldDisplayPayload(for: makeTestTorrentDetailIdentity(11)))
    }

    func testBeginLoadingForDifferentTorrentClearsLoadedPayload() {
        var state = TorrentDetailSupplementalState()
        let snapshot = makeSnapshot()

        let firstGeneration = state.beginLoading(for: makeTestTorrentDetailIdentity(11))
        XCTAssertTrue(state.apply(snapshot: snapshot, for: makeTestTorrentDetailIdentity(11), generation: firstGeneration))

        let secondGeneration = state.beginLoading(for: makeTestTorrentDetailIdentity(12))

        XCTAssertEqual(state.activeIdentity, makeTestTorrentDetailIdentity(12))
        XCTAssertEqual(state.activeRequestGeneration, secondGeneration)
        XCTAssertEqual(state.status, .loading)
        XCTAssertEqual(state.payload, .empty)
        XCTAssertFalse(state.shouldDisplayPayload(for: makeTestTorrentDetailIdentity(12)))
    }

    func testMarkFailedPreservesPayloadForActiveRequest() {
        var state = TorrentDetailSupplementalState()
        let snapshot = makeSnapshot()

        let generation = state.beginLoading(for: makeTestTorrentDetailIdentity(11))
        XCTAssertTrue(state.apply(snapshot: snapshot, for: makeTestTorrentDetailIdentity(11), generation: generation))

        let didMarkFailure = state.markFailed(for: makeTestTorrentDetailIdentity(11), generation: generation)

        XCTAssertTrue(didMarkFailure)
        XCTAssertEqual(state.status, .failed)
        XCTAssertEqual(state.payload.files, snapshot.files)
        XCTAssertTrue(state.shouldDisplayPayload(for: makeTestTorrentDetailIdentity(11)))
    }

    func testMarkFailedIgnoresStaleRequest() {
        var state = TorrentDetailSupplementalState()

        let staleGeneration = state.beginLoading(for: makeTestTorrentDetailIdentity(3))
        let currentGeneration = state.beginLoading(for: makeTestTorrentDetailIdentity(4))

        let didMarkFailure = state.markFailed(for: makeTestTorrentDetailIdentity(3), generation: staleGeneration)

        XCTAssertFalse(didMarkFailure)
        XCTAssertEqual(state.activeIdentity, makeTestTorrentDetailIdentity(4))
        XCTAssertEqual(state.activeRequestGeneration, currentGeneration)
        XCTAssertEqual(state.status, .loading)
        XCTAssertEqual(state.payload, .empty)
        XCTAssertFalse(state.shouldDisplayPayload(for: makeTestTorrentDetailIdentity(4)))
    }

    func testApplySnapshotRecoversAfterFailureWhileRetainingPayload() {
        var state = TorrentDetailSupplementalState()
        let oldSnapshot = makeSnapshot(fileName: "old-file")
        let newSnapshot = makeSnapshot(fileName: "new-file")

        let firstGeneration = state.beginLoading(for: makeTestTorrentDetailIdentity(7))
        XCTAssertTrue(state.apply(snapshot: oldSnapshot, for: makeTestTorrentDetailIdentity(7), generation: firstGeneration))
        XCTAssertTrue(state.markFailed(for: makeTestTorrentDetailIdentity(7), generation: firstGeneration))
        let secondGeneration = state.beginLoading(for: makeTestTorrentDetailIdentity(7))

        let didApply = state.apply(snapshot: newSnapshot, for: makeTestTorrentDetailIdentity(7), generation: secondGeneration)

        XCTAssertTrue(didApply)
        XCTAssertEqual(state.status, .loaded)
        XCTAssertEqual(state.payload.files.map(\.name), ["new-file"])
        XCTAssertTrue(state.shouldDisplayPayload(for: makeTestTorrentDetailIdentity(7)))
    }

    func testApplySnapshotIgnoresOlderGenerationForSameTorrent() {
        var state = TorrentDetailSupplementalState()
        let olderSnapshot = makeSnapshot(fileName: "older-file")
        let newerSnapshot = makeSnapshot(fileName: "newer-file")

        let olderGeneration = state.beginLoading(for: makeTestTorrentDetailIdentity(9))
        let newerGeneration = state.beginLoading(for: makeTestTorrentDetailIdentity(9))

        let didApplyOlderSnapshot = state.apply(
            snapshot: olderSnapshot,
            for: makeTestTorrentDetailIdentity(9),
            generation: olderGeneration
        )
        let didApplyNewerSnapshot = state.apply(
            snapshot: newerSnapshot,
            for: makeTestTorrentDetailIdentity(9),
            generation: newerGeneration
        )

        XCTAssertFalse(didApplyOlderSnapshot)
        XCTAssertTrue(didApplyNewerSnapshot)
        XCTAssertEqual(state.activeIdentity, makeTestTorrentDetailIdentity(9))
        XCTAssertEqual(state.activeRequestGeneration, newerGeneration)
        XCTAssertEqual(state.status, .loaded)
        XCTAssertEqual(state.payload.files.map(\.name), ["newer-file"])
        XCTAssertTrue(state.shouldDisplayPayload(for: makeTestTorrentDetailIdentity(9)))
    }

    func testMarkFailedIgnoresOlderGenerationForSameTorrent() {
        var state = TorrentDetailSupplementalState()
        let snapshot = makeSnapshot(fileName: "retained-file")

        let initialGeneration = state.beginLoading(for: makeTestTorrentDetailIdentity(13))
        XCTAssertTrue(state.apply(snapshot: snapshot, for: makeTestTorrentDetailIdentity(13), generation: initialGeneration))

        let staleGeneration = state.beginLoading(for: makeTestTorrentDetailIdentity(13))
        let currentGeneration = state.beginLoading(for: makeTestTorrentDetailIdentity(13))

        let didMarkStaleFailure = state.markFailed(for: makeTestTorrentDetailIdentity(13), generation: staleGeneration)

        XCTAssertFalse(didMarkStaleFailure)
        XCTAssertEqual(state.activeIdentity, makeTestTorrentDetailIdentity(13))
        XCTAssertEqual(state.activeRequestGeneration, currentGeneration)
        XCTAssertEqual(state.status, .loading)
        XCTAssertEqual(state.payload.files.map(\.name), ["retained-file"])
        XCTAssertTrue(state.shouldDisplayPayload(for: makeTestTorrentDetailIdentity(13)))
    }

    func testMarkCancelledRestoresIdleStateWhenNoPayloadExists() {
        var state = TorrentDetailSupplementalState()

        let generation = state.beginLoading(for: makeTestTorrentDetailIdentity(21))
        let didMarkCancellation = state.markCancelled(for: makeTestTorrentDetailIdentity(21), generation: generation)

        XCTAssertTrue(didMarkCancellation)
        XCTAssertEqual(state.activeIdentity, makeTestTorrentDetailIdentity(21))
        XCTAssertEqual(state.activeRequestGeneration, generation)
        XCTAssertEqual(state.status, .idle)
        XCTAssertEqual(state.payload, .empty)
        XCTAssertFalse(state.shouldDisplayPayload(for: makeTestTorrentDetailIdentity(21)))
    }

    func testMarkCancelledRestoresLoadedStateWhenPayloadExists() {
        var state = TorrentDetailSupplementalState()
        let snapshot = makeSnapshot(fileName: "retained-file")

        let firstGeneration = state.beginLoading(for: makeTestTorrentDetailIdentity(22))
        XCTAssertTrue(state.apply(snapshot: snapshot, for: makeTestTorrentDetailIdentity(22), generation: firstGeneration))
        let secondGeneration = state.beginLoading(for: makeTestTorrentDetailIdentity(22))

        let didMarkCancellation = state.markCancelled(for: makeTestTorrentDetailIdentity(22), generation: secondGeneration)

        XCTAssertTrue(didMarkCancellation)
        XCTAssertEqual(state.activeIdentity, makeTestTorrentDetailIdentity(22))
        XCTAssertEqual(state.activeRequestGeneration, secondGeneration)
        XCTAssertEqual(state.status, .loaded)
        XCTAssertEqual(state.payload.files.map(\.name), ["retained-file"])
        XCTAssertTrue(state.shouldDisplayPayload(for: makeTestTorrentDetailIdentity(22)))
    }

    func testMarkCancelledIgnoresOlderGenerationForSameTorrent() {
        var state = TorrentDetailSupplementalState()
        let snapshot = makeSnapshot(fileName: "retained-file")

        let firstGeneration = state.beginLoading(for: makeTestTorrentDetailIdentity(23))
        XCTAssertTrue(state.apply(snapshot: snapshot, for: makeTestTorrentDetailIdentity(23), generation: firstGeneration))
        let staleGeneration = state.beginLoading(for: makeTestTorrentDetailIdentity(23))
        let currentGeneration = state.beginLoading(for: makeTestTorrentDetailIdentity(23))

        let didMarkCancellation = state.markCancelled(for: makeTestTorrentDetailIdentity(23), generation: staleGeneration)

        XCTAssertFalse(didMarkCancellation)
        XCTAssertEqual(state.activeIdentity, makeTestTorrentDetailIdentity(23))
        XCTAssertEqual(state.activeRequestGeneration, currentGeneration)
        XCTAssertEqual(state.status, .loading)
        XCTAssertEqual(state.payload.files.map(\.name), ["retained-file"])
        XCTAssertTrue(state.shouldDisplayPayload(for: makeTestTorrentDetailIdentity(23)))
    }

    func testShouldDisplayPayloadRequiresMatchingActiveTorrentID() {
        var state = TorrentDetailSupplementalState()
        let snapshot = makeSnapshot(fileName: "retained-file")

        let generation = state.beginLoading(for: makeTestTorrentDetailIdentity(24))
        XCTAssertTrue(state.apply(snapshot: snapshot, for: makeTestTorrentDetailIdentity(24), generation: generation))

        XCTAssertTrue(state.shouldDisplayPayload(for: makeTestTorrentDetailIdentity(24)))
        XCTAssertFalse(state.shouldDisplayPayload(for: makeTestTorrentDetailIdentity(25)))
        XCTAssertEqual(state.visiblePayload(for: makeTestTorrentDetailIdentity(24)).files.map(\.name), ["retained-file"])
        XCTAssertEqual(state.visiblePayload(for: makeTestTorrentDetailIdentity(25)), .empty)
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

final class TorrentDetailIdentityStateTests: XCTestCase {
    func testBeginLoadingForNewConnectionClearsPayloadForSameTorrent() {
        var state = TorrentDetailSupplementalState()
        let oldIdentity = makeTestTorrentDetailIdentity(42, connectionGeneration: UUID())
        let newIdentity = makeTestTorrentDetailIdentity(42, connectionGeneration: UUID())
        let oldGeneration = state.beginLoading(for: oldIdentity)

        XCTAssertTrue(state.apply(snapshot: makeSnapshot(), for: oldIdentity, generation: oldGeneration))
        XCTAssertTrue(state.markInitialLoadErrorReported(for: oldIdentity))

        let newGeneration = state.beginLoading(for: newIdentity)

        XCTAssertEqual(state.activeIdentity, newIdentity)
        XCTAssertEqual(state.activeRequestGeneration, newGeneration)
        XCTAssertEqual(state.status, .loading)
        XCTAssertEqual(state.payload, .empty)
        XCTAssertFalse(state.shouldDisplayPayload(for: oldIdentity))
        XCTAssertFalse(state.shouldDisplayPayload(for: newIdentity))
        XCTAssertFalse(state.hasReportedInitialLoadError)
        XCTAssertTrue(state.shouldReportInitialLoadError(for: newIdentity))
    }

    func testLateResponseFromPreviousConnectionIsIgnoredForSameTorrent() {
        var state = TorrentDetailSupplementalState()
        let oldIdentity = makeTestTorrentDetailIdentity(42, connectionGeneration: UUID())
        let newIdentity = makeTestTorrentDetailIdentity(42, connectionGeneration: UUID())
        let oldGeneration = state.beginLoading(for: oldIdentity)
        let newGeneration = state.beginLoading(for: newIdentity)

        let didApplyOldResponse = state.apply(
            snapshot: makeSnapshot(fileName: "old-connection-file"),
            for: oldIdentity,
            generation: oldGeneration
        )
        let didApplyNewResponse = state.apply(
            snapshot: makeSnapshot(fileName: "new-connection-file"),
            for: newIdentity,
            generation: newGeneration
        )

        XCTAssertFalse(didApplyOldResponse)
        XCTAssertTrue(didApplyNewResponse)
        XCTAssertEqual(state.payload.files.map(\.name), ["new-connection-file"])
        XCTAssertTrue(state.shouldDisplayPayload(for: newIdentity))
    }

    func testCommittedMutationFromPreviousConnectionIsIgnoredForSameTorrent() {
        var state = TorrentDetailSupplementalState()
        let oldIdentity = makeTestTorrentDetailIdentity(42, connectionGeneration: UUID())
        let newIdentity = makeTestTorrentDetailIdentity(42, connectionGeneration: UUID())
        let generation = state.beginLoading(for: newIdentity)
        XCTAssertTrue(state.apply(snapshot: makeSnapshot(), for: newIdentity, generation: generation))

        let didApply = state.applyCommittedFileStatsMutation(
            .wanted(false),
            for: oldIdentity,
            fileIndices: [0]
        )

        XCTAssertFalse(didApply)
        XCTAssertTrue(state.payload.fileStats[0].wanted)
    }
}

final class TorrentDetailSupplementalErrorStateTests: XCTestCase {
    func testInitialLoadErrorIsReportedOnlyOnceForActiveTorrent() {
        var state = TorrentDetailSupplementalState()

        XCTAssertTrue(state.shouldReportInitialLoadError(for: makeTestTorrentDetailIdentity(11)))
        _ = state.beginLoading(for: makeTestTorrentDetailIdentity(11))
        XCTAssertTrue(state.shouldReportInitialLoadError(for: makeTestTorrentDetailIdentity(11)))
        XCTAssertTrue(state.markInitialLoadErrorReported(for: makeTestTorrentDetailIdentity(11)))

        XCTAssertFalse(state.shouldReportInitialLoadError(for: makeTestTorrentDetailIdentity(11)))
        XCTAssertTrue(state.shouldReportInitialLoadError(for: makeTestTorrentDetailIdentity(12)))
    }

    func testTaskIdentityIgnoresPollingRevisionButTracksTorrentAndConnection() {
        let connectionGeneration = UUID()
        let initialIdentity = TorrentDetailIdentity(
            torrentID: 42,
            connectionGeneration: connectionGeneration
        )
        let sameIdentityAfterPolling = TorrentDetailIdentity(
            torrentID: 42,
            connectionGeneration: connectionGeneration
        )

        XCTAssertEqual(initialIdentity, sameIdentityAfterPolling)
        XCTAssertNotEqual(
            initialIdentity,
            TorrentDetailIdentity(torrentID: 43, connectionGeneration: connectionGeneration)
        )
        XCTAssertNotEqual(
            initialIdentity,
            TorrentDetailIdentity(torrentID: 42, connectionGeneration: UUID())
        )
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
