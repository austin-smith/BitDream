import Foundation

internal struct TransmissionPollingSnapshot: Sendable, Equatable {
    let sessionStats: SessionStats
    let torrents: [Torrent]
}

internal struct TransmissionAppRefreshSnapshot: Sendable, Equatable {
    let polling: TransmissionPollingSnapshot
    let sessionSettings: TransmissionSessionResponseArguments
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
        async let sessionSettings = fetchSessionSettings()

        return try await TransmissionAppRefreshSnapshot(
            polling: polling,
            sessionSettings: sessionSettings
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
}
