//  App-only helpers to write App Group snapshot files for widgets.

import Foundation
import WidgetKit

struct WidgetSnapshotWriter: Sendable {
    let writeServerIndex: @Sendable ([ServerSummary]) -> Void
    let writeSessionSnapshot: @Sendable (_ serverID: String, _ serverName: String, _ stats: SessionStats, _ torrents: [Torrent], _ reloadTimelines: Bool) -> Void
    let reloadTimelines: @Sendable () -> Void

    static let live = Self(
        writeServerIndex: { writeServersIndex(servers: $0) },
        writeSessionSnapshot: writeLiveSessionSnapshot,
        reloadTimelines: {
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.sessionOverview)
        }
    )
}

private func writeLiveSessionSnapshot(
    serverID: String,
    serverName: String,
    stats: SessionStats,
    torrents: [Torrent],
    reloadTimelines: Bool
) {
    writeSessionSnapshot(
        serverID: serverID,
        serverName: serverName,
        stats: stats,
        torrents: torrents,
        reloadTimelines: reloadTimelines
    )
}

func writeServersIndex(servers: [ServerSummary]) {
    guard let url = AppGroup.Files.serversIndexURL() else { return }

    let deduplicated = Dictionary(uniqueKeysWithValues: servers.map { ($0.id, $0) })
    let sortedServers = Array(deduplicated.values).sorted { lhs, rhs in
        let compare = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
        if compare == .orderedSame {
            return lhs.id < rhs.id
        }
        return compare == .orderedAscending
    }
    let updated = ServerIndex(servers: sortedServers)
    _ = AppGroupJSON.write(updated, to: url)
}

func writeSessionSnapshot(
    serverID: String,
    serverName: String,
    stats: SessionStats,
    torrents: [Torrent],
    reloadTimelines: Bool = true
) {
    let active = stats.activeTorrentCount
    let paused = stats.pausedTorrentCount
    let total = stats.torrentCount

    // Calculate status counts using existing filter logic
    let totalCount = torrents.count
    let downloadingCount = torrents.filter { $0.statusCalc == .downloading }.count
    let completedCount = torrents.filter { $0.statusCalc == .complete }.count

    let uploaded = stats.currentStats?.uploadedBytes ?? 0
    let downloaded = stats.currentStats?.downloadedBytes ?? 0
    let ratio = (downloaded > 0) ? (Double(uploaded) / Double(downloaded)) : 0

    let snap = SessionOverviewSnapshot(
        serverId: serverID,
        serverName: serverName,
        active: active,
        paused: paused,
        total: total,
        totalCount: totalCount,
        downloadingCount: downloadingCount,
        completedCount: completedCount,
        downloadSpeed: stats.downloadSpeed,
        uploadSpeed: stats.uploadSpeed,
        ratio: ratio,
        timestamp: Date()
    )

    guard let url = AppGroup.Files.sessionURL(for: serverID) else { return }
    if AppGroupJSON.write(snap, to: url), reloadTimelines {
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.sessionOverview)
    }
}
