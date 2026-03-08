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
