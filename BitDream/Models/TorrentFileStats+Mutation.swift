extension TorrentFileStats {
    func applying(_ mutation: TorrentDetailFileStatsMutation) -> Self {
        switch mutation {
        case .wanted(let wanted):
            TorrentFileStats(
                bytesCompleted: bytesCompleted,
                wanted: wanted,
                priority: priority
            )
        case .priority(let priority):
            TorrentFileStats(
                bytesCompleted: bytesCompleted,
                wanted: wanted,
                priority: priority.rawValue
            )
        }
    }
}
