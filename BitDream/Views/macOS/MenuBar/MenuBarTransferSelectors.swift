import Foundation

#if os(macOS)

struct MenuBarTransferSummary {
    let serverName: String
    let activeCount: Int
    let downloadSpeed: Int64
    let uploadSpeed: Int64
    let ratio: Double
}

func menuBarSummary(from store: Store) -> MenuBarTransferSummary {
    let activeTransfers = store.torrents.sortedActiveTransfersByActivity()
    let stats = store.sessionStats

    let uploaded = stats?.currentStats?.uploadedBytes ?? 0
    let downloaded = stats?.currentStats?.downloadedBytes ?? 0
    let ratio = downloaded > 0 ? Double(uploaded) / Double(downloaded) : 0

    return MenuBarTransferSummary(
        serverName: store.host?.name ?? "No Server",
        activeCount: activeTransfers.count,
        downloadSpeed: stats?.downloadSpeed ?? 0,
        uploadSpeed: stats?.uploadSpeed ?? 0,
        ratio: ratio
    )
}

#endif
