import Foundation

#if os(macOS)

struct MenuBarTorrentSummary {
    let serverName: String
    let activeCount: Int
    let downloadSpeed: Int64
    let uploadSpeed: Int64
    let ratio: Double
}

@MainActor
func menuBarActiveTorrents(from store: TransmissionStore, sortMode: MenuBarSortMode) -> [Torrent] {
    let active = store.torrents.filter(\.isActiveTransfer)

    switch sortMode {
    case .activity:
        return active.sortedActiveTransfersByActivity()
    case .name:
        return sortTorrents(active, by: .name, order: .ascending)
    case .eta:
        return sortTorrents(active, by: .eta, order: .ascending)
    }
}

@MainActor
func menuBarSummary(from store: TransmissionStore) -> MenuBarTorrentSummary {
    menuBarSummary(from: store, activeTorrents: menuBarActiveTorrents(from: store, sortMode: .activity))
}

@MainActor
func menuBarSummary(from store: TransmissionStore, activeTorrents: [Torrent]) -> MenuBarTorrentSummary {
    let stats = store.sessionStats

    let uploaded = stats?.currentStats?.uploadedBytes ?? 0
    let downloaded = stats?.currentStats?.downloadedBytes ?? 0
    let ratio = downloaded > 0 ? Double(uploaded) / Double(downloaded) : 0

    return MenuBarTorrentSummary(
        serverName: store.host?.name ?? "No Server",
        activeCount: activeTorrents.count,
        downloadSpeed: stats?.downloadSpeed ?? 0,
        uploadSpeed: stats?.uploadSpeed ?? 0,
        ratio: ratio
    )
}

#endif
