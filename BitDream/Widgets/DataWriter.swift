//  App-only helpers to write App Group snapshot files for widgets.

import Foundation
import WidgetKit

func writeServersIndex(serverID: String, serverName: String) {
    guard let url = AppGroup.Files.serversIndexURL() else { return }

    let existing: ServerIndex = AppGroupJSON.read(ServerIndex.self, from: url) ?? ServerIndex(servers: [])
    let summary = ServerSummary(id: serverID, name: serverName)
    var dict = Dictionary(uniqueKeysWithValues: existing.servers.map { ($0.id, $0) })
    dict[serverID] = summary
    let updated = ServerIndex(servers: Array(dict.values).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
    _ = AppGroupJSON.write(updated, to: url)
}

func writeSessionSnapshot(serverID: String, serverName: String, stats: SessionStats, torrents: [Torrent]) {
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
    if AppGroupJSON.write(snap, to: url) {
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.sessionOverview)
    }
}
