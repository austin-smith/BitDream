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
                let a = lhs.activitySortKey
                let b = rhs.activitySortKey

                if a.0 != b.0 { return a.0 > b.0 }
                if a.1 != b.1 { return a.1 > b.1 }
                if a.2 != b.2 { return a.2 > b.2 }
                return a.3 < b.3
            }
    }
}
