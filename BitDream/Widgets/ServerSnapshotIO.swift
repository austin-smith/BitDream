//
//  ServerSnapshotIO.swift
//  BitDream
//
//  App-only helpers to write App Group snapshot files for widgets.
//

import Foundation
import WidgetKit

func writeServersIndexIfPossible(store: Store) {
    guard let host = store.host else { return }
    let id = host.objectID.uriRepresentation().absoluteString
    let name = host.name ?? host.server ?? "Server"
    guard let url = AppGroup.Files.serversIndexURL() else { return }

    var existing: ServerIndex = AppGroupJSON.read(ServerIndex.self, from: url) ?? ServerIndex(servers: [])
    let summary = ServerSummary(id: id, name: name)
    var dict = Dictionary(uniqueKeysWithValues: existing.servers.map { ($0.id, $0) })
    dict[id] = summary
    let updated = ServerIndex(servers: Array(dict.values).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
    _ = AppGroupJSON.write(updated, to: url)
}

func writeSessionSnapshotIfPossible(store: Store, stats: SessionStats) {
    guard let host = store.host else { return }
    let id = host.objectID.uriRepresentation().absoluteString
    let name = host.name ?? host.server ?? "Server"

    let active = stats.activeTorrentCount
    let paused = stats.pausedTorrentCount
    let total = stats.torrentCount

    let uploaded = stats.currentStats?.uploadedBytes ?? 0
    let downloaded = stats.currentStats?.downloadedBytes ?? 0
    let ratio = (downloaded > 0) ? (Double(uploaded) / Double(downloaded)) : 0

    let snap = SessionOverviewSnapshot(
        serverId: id,
        serverName: name,
        active: active,
        paused: paused,
        total: total,
        downloadSpeed: stats.downloadSpeed,
        uploadSpeed: stats.uploadSpeed,
        ratio: ratio,
        timestamp: Date()
    )

    guard let url = AppGroup.Files.sessionURL(for: id) else { return }
    if AppGroupJSON.write(snap, to: url) {
        WidgetCenter.shared.reloadTimelines(ofKind: "SessionOverviewWidget")
    }
}


