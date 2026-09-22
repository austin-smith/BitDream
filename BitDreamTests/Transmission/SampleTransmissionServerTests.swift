#if BITDREAM_SAMPLE_SUPPORT
import XCTest
@testable import BitDream

final class SampleTransmissionServerTests: XCTestCase {
    private func connection(host: String = "demo.example.invalid") throws -> TransmissionConnection {
        TransmissionConnection(
            endpoint: try TransmissionEndpoint(scheme: "https", host: host, port: 9091),
            auth: TransmissionAuth(username: "", password: ""),
            transport: TransmissionTransport(sender: try SampleTransmissionServer())
        )
    }

    func testLibraryLoadsThroughRealRPCAndMatchesDetailsAndWidget() async throws {
        let connection = try connection()
        let snapshot = try await connection.fetchAppRefreshSnapshot()
        let torrents = snapshot.polling.torrents
        XCTAssertEqual(torrents.count, 7)
        XCTAssertEqual(snapshot.polling.sessionStats.pausedTorrentCount, 2)
        XCTAssertEqual(snapshot.polling.sessionStats.activeTorrentCount, 5)
        XCTAssertEqual(snapshot.polling.sessionStats.downloadSpeed, 13_739_764)
        XCTAssertEqual(torrents.filter { $0.statusCalc == .downloading }.count, 2)
        XCTAssertEqual(torrents.filter { $0.statusCalc == .seeding }.count, 2)
        XCTAssertEqual(torrents.filter { $0.statusCalc == .complete }.count, 1)
        XCTAssertEqual(torrents.filter { $0.statusCalc == .paused }.count, 1)
        XCTAssertEqual(torrents.filter { $0.statusCalc == .stalled }.count, 1)
        let stalled = try XCTUnwrap(torrents.first { $0.id == 3 })
        XCTAssertEqual(stalled.statusCalc, .stalled)
        XCTAssertEqual(stalled.rateDownload, 0)
        XCTAssertEqual(stalled.peersConnected, 0)
        XCTAssertEqual(torrents.first { $0.id == 6 }?.statusCalc, .downloading)
        let token = await connection.currentSessionToken()
        XCTAssertNotNil(token)
        for torrent in torrents {
            let detail = try await connection.fetchTorrentDetail(id: torrent.id)
            XCTAssertEqual(detail.files.reduce(0) { $0 + $1.length }, torrent.totalSize)
            XCTAssertEqual(detail.files.reduce(0) { $0 + $1.bytesCompleted }, torrent.haveValid)
            XCTAssertEqual(detail.files.map(\.bytesCompleted), detail.fileStats.map(\.bytesCompleted))
            XCTAssertEqual(detail.peers.count, torrent.peersConnected)
            XCTAssertEqual(detail.peers.reduce(Int64(0)) { $0 + ($1.rateToClient ?? 0) }, torrent.rateDownload)
            XCTAssertEqual(detail.peers.reduce(Int64(0)) { $0 + ($1.rateToPeer ?? 0) }, torrent.rateUpload)
            XCTAssertEqual(detail.peers.filter(\.isUploadingTo).count, torrent.peersGettingFromUs)
            XCTAssertEqual(detail.peers.filter(\.isDownloadingFrom).count, torrent.peersSendingToUs)
            for peer in detail.peers where peer.isUploadingTo {
                XCTAssertLessThan(peer.progress, 1)
                XCTAssertTrue(peer.peerIsInterested)
                XCTAssertTrue(peer.flagStr.contains("U"))
            }
            let bits = try XCTUnwrap(Data(base64Encoded: detail.pieces))
            XCTAssertEqual(bits.count, (detail.pieceCount + 7) / 8)
            let fullPieces = bits.reduce(0) { $0 + $1.nonzeroBitCount }
            XCTAssertEqual(fullPieces, torrent.percentDone == 1 ? detail.pieceCount : Int(torrent.haveValid / detail.pieceSize))
        }
        let widget = SampleLibrary.widgetSnapshot()
        XCTAssertEqual(widget.total, torrents.count)
        XCTAssertEqual(widget.active, snapshot.polling.sessionStats.activeTorrentCount)
        XCTAssertEqual(widget.paused, snapshot.polling.sessionStats.pausedTorrentCount)
        XCTAssertEqual(widget.downloadSpeed, snapshot.polling.sessionStats.downloadSpeed)
        XCTAssertEqual(widget.downloadingCount, torrents.filter { $0.statusCalc == .downloading }.count)
        XCTAssertEqual(widget.completedCount, torrents.filter { $0.statusCalc == .complete }.count)
    }

    func testVerifiedFileMetadata() async throws {
        let connection = try connection()
        struct Metadata {
            let id: Int
            let fileCount: Int
            let totalSize: Int64
            let pieceSize: Int64
        }
        let expected: [Metadata] = [
            Metadata(id: 1, fileCount: 3, totalSize: 276_445_467, pieceSize: 262_144),
            Metadata(id: 2, fileCount: 1, totalSize: 170_835_968, pieceSize: 131_072),
            Metadata(id: 3, fileCount: 2, totalSize: 2_645_647_894, pieceSize: 262_144),
            Metadata(id: 4, fileCount: 94, totalSize: 172_834_850, pieceSize: 262_144),
            Metadata(id: 5, fileCount: 18, totalSize: 56_070_710, pieceSize: 65_536),
            Metadata(id: 6, fileCount: 1, totalSize: 24_749_684_048, pieceSize: 16_777_216),
            Metadata(id: 7, fileCount: 1, totalSize: 3_654_957_056, pieceSize: 262_144)
        ]
        for item in expected {
            let detail = try await connection.fetchTorrentDetail(id: item.id)
            XCTAssertEqual(detail.files.count, item.fileCount)
            XCTAssertEqual(detail.files.reduce(0) { $0 + $1.length }, item.totalSize)
            XCTAssertEqual(detail.pieceSize, item.pieceSize)
            XCTAssertEqual(detail.pieceCount, Int((item.totalSize + item.pieceSize - 1) / item.pieceSize))
            XCTAssertTrue(detail.files.allSatisfy { $0.bytesCompleted >= 0 && $0.bytesCompleted <= $0.length })
        }
        let bunny = try await connection.fetchTorrentDetail(id: 1)
        XCTAssertEqual(bunny.files.map(\.name), [
            "Big Buck Bunny/Big Buck Bunny.en.srt", "Big Buck Bunny/Big Buck Bunny.mp4", "Big Buck Bunny/poster.jpg"
        ])
        let wired = try await connection.fetchTorrentDetail(id: 5)
        XCTAssertEqual(wired.files.filter { $0.name.hasSuffix(".mp3") }.count, 16)
        let mozart = try await connection.fetchTorrentDetail(id: 4)
        XCTAssertEqual(mozart.files.filter { $0.name.hasSuffix(".pdf") }.count, 94)
        XCTAssertTrue(mozart.files.contains { $0.name.contains("/Piano with Orchestra/Cadenzas/") })
    }

    func testTransferTotalsAndRatiosMatchTorrentBytes() async throws {
        let snapshot = try await connection().fetchPollingSnapshot()
        let torrents = snapshot.torrents
        let stats = snapshot.sessionStats
        let current = try XCTUnwrap(stats.currentStats)
        let cumulative = try XCTUnwrap(stats.cumulativeStats)
        let downloaded = torrents.reduce(Int64(0)) { $0 + $1.downloadedEver }
        let uploaded = torrents.reduce(Int64(0)) { $0 + $1.uploadedEver }
        let ratio = Double(uploaded) / Double(downloaded)
        XCTAssertEqual(stats.downloadSpeed, torrents.reduce(0) { $0 + $1.rateDownload })
        XCTAssertEqual(stats.uploadSpeed, torrents.reduce(0) { $0 + $1.rateUpload })
        XCTAssertEqual(stats.uploadSpeed, 2_829_328)
        XCTAssertLessThan(stats.uploadSpeed, stats.downloadSpeed)
        XCTAssertEqual(current.downloadedBytes, downloaded)
        XCTAssertEqual(current.uploadedBytes, uploaded)
        XCTAssertEqual(ratio, 0.5828, accuracy: 0.0001)
        XCTAssertEqual(Double(cumulative.uploadedBytes) / Double(cumulative.downloadedBytes), ratio, accuracy: 0.000001)
        for torrent in torrents {
            XCTAssertEqual(torrent.uploadRatioRaw, Double(torrent.uploadedEver) / Double(torrent.downloadedEver), accuracy: 0.000001)
        }
        let widget = SampleLibrary.widgetSnapshot()
        XCTAssertEqual(widget.uploadSpeed, stats.uploadSpeed)
        XCTAssertEqual(widget.ratio, ratio, accuracy: 0.000001)
        let paused = SampleLibrary.widgetSnapshot(paused: true)
        XCTAssertEqual(paused.uploadSpeed, 0)
        XCTAssertEqual(paused.downloadSpeed, 0)
        XCTAssertEqual(paused.ratio, ratio, accuracy: 0.000001)
    }

    func testMutationsSurviveRefreshAndNewServerResets() async throws {
        let connection = try connection()
        try await connection.pauseTorrents(ids: [6])
        try await connection.setTorrentLabels(ids: [6], labels: ["reference", "archive"])
        var torrents = try await connection.fetchTorrentSummary()
        let wiki = try XCTUnwrap(torrents.first { $0.id == 6 })
        XCTAssertEqual(wiki.status, 0)
        XCTAssertEqual(wiki.rateDownload, 0)
        XCTAssertEqual(wiki.rateUpload, 0)
        XCTAssertEqual(wiki.peersGettingFromUs, 0)
        XCTAssertEqual(wiki.labels, ["archive", "reference"])
        let stats = try await connection.fetchSessionStats()
        XCTAssertEqual(stats.pausedTorrentCount, 3)
        XCTAssertEqual(stats.downloadSpeed, 67_283)
        XCTAssertEqual(stats.uploadSpeed, 2_191_111)
        try await connection.resumeTorrents(ids: [6])
        try await connection.removeTorrents(ids: [2], deleteLocalData: true)
        torrents = try await connection.fetchTorrentSummary()
        XCTAssertEqual(torrents.count, 6)
        XCTAssertEqual(torrents.first { $0.id == 6 }?.status, 4)
        let fresh = try await self.connection().fetchTorrentSummary()
        XCTAssertEqual(fresh.count, 7)
        XCTAssertEqual(fresh.first { $0.id == 6 }?.rateDownload, 13_672_481)
        XCTAssertEqual(fresh.first { $0.id == 6 }?.rateUpload, 638_217)
    }

    func testFileSelectionPriorityRenameAndQueue() async throws {
        let connection = try connection()
        try await connection.setFileWantedStatus(torrentID: 1, fileIndices: [2], wanted: false)
        try await connection.setFilePriority(torrentID: 1, fileIndices: [1], priority: .high)
        _ = try await connection.renameTorrentPath(torrentID: 1, path: "Big Buck Bunny", newName: "Bunny")
        let detail = try await connection.fetchTorrentDetail(id: 1)
        XCTAssertFalse(detail.fileStats[2].wanted)
        XCTAssertEqual(detail.fileStats[1].priority, 1)
        XCTAssertEqual(detail.files[1].name, "Bunny/Big Buck Bunny.mp4")
        try await connection.queueMove(.top, ids: [7, 6])
        let torrents = try await connection.fetchTorrentSummary().sorted { $0.queuePosition < $1.queuePosition }
        XCTAssertEqual(torrents.prefix(2).map(\.id), [6, 7])
        XCTAssertEqual(torrents.first { $0.id == 1 }?.name, "Bunny")
    }

    func testSettingsAndDeterministicAdd() async throws {
        let connection = try connection()
        var settings = TransmissionSessionSetRequestArgs()
        settings.altSpeedEnabled = true
        try await connection.setSession(settings)
        let loaded = try await connection.fetchSessionSettings()
        XCTAssertTrue(loaded.altSpeedEnabled)
        let space = try await connection.checkFreeSpace(path: "/Downloads")
        XCTAssertEqual(space.path, "/Downloads")
        XCTAssertGreaterThan(space.totalSize, space.sizeBytes)
        let port = try await connection.testPort()
        XCTAssertEqual(port.portIsOpen, true)
        let blocklist = try await connection.updateBlocklist()
        XCTAssertEqual(blocklist.blocklistSize, loaded.blocklistSize)
        _ = try await connection.addTorrent(fileURL: SampleFixtures.magnet(id: 8), saveLocation: "/Downloads", isTorrentFile: false)
        let first = try await connection.fetchTorrentSummary()
        XCTAssertEqual(first.count, 8)
        XCTAssertEqual(first.last?.name, "Sintel")
        XCTAssertEqual(first.last?.uploadedEver, 0)
        XCTAssertEqual(first.last?.downloadedEver, 0)
        XCTAssertEqual(first.last?.uploadRatioRaw, -1)
        _ = try await connection.addTorrent(fileURL: SampleFixtures.magnet(id: 8), saveLocation: "/Downloads", isTorrentFile: false)
        let second = try await connection.fetchTorrentSummary()
        XCTAssertEqual(second.count, 8)
    }

    func testEmptyLibraryAndUnsupportedRequests() async throws {
        let connection = try connection()
        try await connection.removeTorrents(ids: SampleLibrary.items.map(\.id), deleteLocalData: false)
        let empty = try await connection.fetchPollingSnapshot()
        XCTAssertTrue(empty.torrents.isEmpty)
        XCTAssertEqual(empty.sessionStats.torrentCount, 0)
        do {
            try await connection.sendStatusRequest(method: "future-method", arguments: EmptyArguments())
            XCTFail("An unsupported method must not silently succeed")
        } catch let error as TransmissionError {
            guard case .rpcFailure(let result) = error else { return XCTFail("\(error)") }
            XCTAssertTrue(result.contains("future-method"))
        }
    }

    func testRemoteServerAuthenticationFailure() async throws {
        do {
            _ = try await connection(host: SampleFixtures.remoteServerAddress).fetchSessionStats()
            XCTFail("Expected an authentication failure")
        } catch let error as TransmissionError {
            XCTAssertEqual(error.diagnosticCode, "unauthorized")
        }
    }
}
extension SampleTransmissionServerTests {
    func testFileSelectionRestoresDownloadingAndKeepsActivityConsistent() async throws {
        let connection = try connection()
        let initial = try await connection.fetchPollingSnapshot()
        let original = try XCTUnwrap(initial.torrents.first { $0.id == 6 })

        for wanted in [false, true] {
            try await connection.setFileWantedStatus(torrentID: 6, fileIndices: [0], wanted: wanted)
            let snapshot = try await connection.fetchPollingSnapshot()
            let torrent = try XCTUnwrap(snapshot.torrents.first { $0.id == 6 })
            let detail = try await connection.fetchTorrentDetail(id: 6)
            XCTAssertEqual(torrent.statusCalc, wanted ? .downloading : .seeding)
            XCTAssertEqual(torrent.sizeWhenDone, wanted ? original.totalSize : 0)
            XCTAssertEqual(torrent.leftUntilDone, wanted ? original.leftUntilDone : 0)
            XCTAssertEqual(torrent.percentDone, wanted ? original.percentDone : 1)
            XCTAssertEqual(torrent.haveValid, original.haveValid)
            XCTAssertEqual(torrent.downloadedEver, original.downloadedEver)
            XCTAssertEqual(torrent.uploadedEver, original.uploadedEver)
            XCTAssertEqual(detail.fileStats[0].wanted, wanted)
            XCTAssertEqual(detail.files[0].bytesCompleted, original.haveValid)
            XCTAssertFalse(torrent.isStalled)
            XCTAssertFalse(torrent.isFinished)
            XCTAssertEqual(torrent.eta, -1)
            XCTAssertEqual(torrent.rateDownload, 0)
            XCTAssertEqual(torrent.rateUpload, original.rateUpload)
            XCTAssertEqual(detail.peers.count, original.peersConnected)
            XCTAssertEqual(torrent.peersConnected, detail.peers.count)
            XCTAssertEqual(torrent.peersSendingToUs, 0)
            XCTAssertEqual(torrent.peersGettingFromUs, original.peersGettingFromUs)
            XCTAssertEqual(detail.peers.reduce(Int64(0)) { $0 + ($1.rateToClient ?? 0) }, torrent.rateDownload)
            XCTAssertEqual(detail.peers.reduce(Int64(0)) { $0 + ($1.rateToPeer ?? 0) }, torrent.rateUpload)
            for peer in detail.peers {
                XCTAssertFalse(peer.isDownloadingFrom)
                XCTAssertFalse(peer.clientIsInterested)
                XCTAssertFalse(peer.flagStr.contains("D"))
                XCTAssertTrue(peer.isUploadingTo)
                XCTAssertTrue(peer.flagStr.contains("U"))
            }
            XCTAssertEqual(snapshot.sessionStats.downloadSpeed, initial.sessionStats.downloadSpeed - original.rateDownload)
            XCTAssertEqual(snapshot.sessionStats.uploadSpeed, initial.sessionStats.uploadSpeed)
        }
    }

    func testFileSelectionPreservesPausedAndVerifyingStates() async throws {
        let connection = try connection()
        try await connection.verifyTorrents(ids: [6])
        for wanted in [false, true] {
            try await connection.setFileWantedStatus(torrentID: 7, fileIndices: [0], wanted: wanted)
            try await connection.setFileWantedStatus(torrentID: 6, fileIndices: [0], wanted: wanted)
            let torrents = try await connection.fetchTorrentSummary()
            let paused = try XCTUnwrap(torrents.first { $0.id == 7 })
            let verifying = try XCTUnwrap(torrents.first { $0.id == 6 })
            XCTAssertEqual(paused.status, 0)
            XCTAssertEqual(paused.isFinished, !wanted)
            XCTAssertEqual(verifying.status, 2)
        }
    }
}
#endif
