import Foundation

// MARK: - Torrent Action Extensions

extension Collection where Element == Torrent {
    /// Whether pause action should be disabled for this collection of torrents
    var shouldDisablePause: Bool {
        return isEmpty || (count == 1 && first?.status == TorrentStatus.stopped.rawValue)
    }

    /// Whether resume actions should be disabled for this collection of torrents
    var shouldDisableResume: Bool {
        return isEmpty || (count == 1 && first?.status != TorrentStatus.stopped.rawValue)
    }
}

extension Torrent {
    var isActiveTransfer: Bool {
        switch statusCalc {
        case .downloading, .retrievingMetadata, .seeding, .verifyingLocalData:
            return true
        default:
            return false
        }
    }

    var activitySortKey: (Int64, Int64, Int64, String) {
        let maxRate = max(rateDownload, rateUpload)
        return (maxRate, rateDownload, rateUpload, name.lowercased())
    }
}

extension Sequence where Element == Torrent {
    func sortedActiveTransfersByActivity() -> [Torrent] {
        self
            .filter(\.isActiveTransfer)
            .sorted { lhs, rhs in
                let leftSortKey = lhs.activitySortKey
                let rightSortKey = rhs.activitySortKey

                if leftSortKey.0 != rightSortKey.0 { return leftSortKey.0 > rightSortKey.0 }
                if leftSortKey.1 != rightSortKey.1 { return leftSortKey.1 > rightSortKey.1 }
                if leftSortKey.2 != rightSortKey.2 { return leftSortKey.2 > rightSortKey.2 }
                return leftSortKey.3 < rightSortKey.3
            }
    }
}
