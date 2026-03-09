import Foundation

internal struct TransmissionPollingSnapshot: Sendable, Equatable {
    let sessionStats: SessionStats
    let torrents: [Torrent]
}

internal struct TransmissionAppRefreshSnapshot: Sendable {
    let polling: TransmissionPollingSnapshot
    let sessionSettingsResult: Result<TransmissionSessionResponseArguments, TransmissionError>
}

internal struct TransmissionWidgetRefreshSnapshot: Sendable {
    let sessionStats: SessionStats
    let torrents: [Torrent]
    let torrentSummaryError: TransmissionError?
}

internal struct TransmissionTorrentDetailSnapshot: Sendable {
    let files: [TorrentFile]
    let fileStats: [TorrentFileStats]
    let peers: [Peer]
    let peersFrom: PeersFrom?
    let pieceCount: Int
    let pieceSize: Int64
    let piecesBitfieldBase64: String
}

internal extension TransmissionConnection {
    func fetchPollingSnapshot() async throws -> TransmissionPollingSnapshot {
        async let sessionStats = fetchSessionStats()
        async let torrents = fetchTorrentSummary()

        return try await TransmissionPollingSnapshot(
            sessionStats: sessionStats,
            torrents: torrents
        )
    }

    func fetchAppRefreshSnapshot() async throws -> TransmissionAppRefreshSnapshot {
        async let polling = fetchPollingSnapshot()
        async let sessionSettingsResult = fetchSessionSettingsResult()

        return try await TransmissionAppRefreshSnapshot(
            polling: polling,
            sessionSettingsResult: sessionSettingsResult
        )
    }

    func fetchWidgetRefreshSnapshot() async throws -> TransmissionWidgetRefreshSnapshot {
        async let sessionStats = fetchSessionStats()
        async let torrentSummaryResult = fetchWidgetSummaryResult()

        let resolvedTorrentSummary = await torrentSummaryResult

        return try await TransmissionPollingSnapshot(
            sessionStats: sessionStats,
            torrents: resolvedTorrentSummary.torrents
        )
        .widgetSnapshot(torrentSummaryError: resolvedTorrentSummary.error)
    }

    func fetchTorrentDetailSnapshot(id: Int) async throws -> TransmissionTorrentDetailSnapshot {
        async let filesResponse = fetchTorrentFiles(id: id)
        async let peersResponse = fetchTorrentPeers(id: id)
        async let piecesResponse = fetchTorrentPieces(id: id)

        let files = try await filesResponse
        let peers = try await peersResponse
        let pieces = try await piecesResponse

        return TransmissionTorrentDetailSnapshot(
            files: files.files,
            fileStats: files.fileStats,
            peers: peers.peers,
            peersFrom: peers.peersFrom,
            pieceCount: pieces.pieceCount,
            pieceSize: pieces.pieceSize,
            piecesBitfieldBase64: pieces.pieces
        )
    }

    private func fetchSessionSettingsResult() async -> Result<TransmissionSessionResponseArguments, TransmissionError> {
        do {
            return .success(try await fetchSessionSettings())
        } catch {
            return .failure(TransmissionErrorResolver.transmissionError(from: error))
        }
    }

    private func fetchWidgetSummaryResult() async -> (torrents: [Torrent], error: TransmissionError?) {
        do {
            return (try await fetchWidgetSummary(), nil)
        } catch {
            return ([], TransmissionErrorResolver.transmissionError(from: error))
        }
    }
}

private extension TransmissionPollingSnapshot {
    func widgetSnapshot(torrentSummaryError: TransmissionError?) -> TransmissionWidgetRefreshSnapshot {
        TransmissionWidgetRefreshSnapshot(
            sessionStats: sessionStats,
            torrents: torrents,
            torrentSummaryError: torrentSummaryError
        )
    }
}
