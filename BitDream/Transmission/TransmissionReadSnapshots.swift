import Foundation

internal struct TransmissionPollingSnapshot: Sendable, Equatable {
    let sessionStats: SessionStats
    let torrents: [Torrent]
}

internal struct TransmissionAppRefreshSnapshot: Sendable {
    let polling: TransmissionPollingSnapshot
    let sessionSettingsResult: Result<TransmissionSessionResponseArguments, TransmissionError>
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

    func fetchWidgetRefreshSnapshot() async throws -> TransmissionPollingSnapshot {
        async let sessionStats = fetchSessionStats()
        async let torrents = fetchWidgetSummary()

        return try await TransmissionPollingSnapshot(
            sessionStats: sessionStats,
            torrents: torrents
        )
    }

    private func fetchSessionSettingsResult() async -> Result<TransmissionSessionResponseArguments, TransmissionError> {
        do {
            return .success(try await fetchSessionSettings())
        } catch {
            return .failure(TransmissionErrorResolver.transmissionError(from: error))
        }
    }
}
