import Foundation

// MARK: - Torrent Action Extensions

struct TorrentActivitySortKey {
    let maxRate: Int64
    let downloadRate: Int64
    let uploadRate: Int64
    let normalizedName: String
}

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

    var activitySortKey: TorrentActivitySortKey {
        let maxRate = max(rateDownload, rateUpload)
        return TorrentActivitySortKey(
            maxRate: maxRate,
            downloadRate: rateDownload,
            uploadRate: rateUpload,
            normalizedName: name.lowercased()
        )
    }
}

extension Sequence where Element == Torrent {
    func sortedActiveTransfersByActivity() -> [Torrent] {
        self
            .filter(\.isActiveTransfer)
            .sorted { lhs, rhs in
                let leftSortKey = lhs.activitySortKey
                let rightSortKey = rhs.activitySortKey

                if leftSortKey.maxRate != rightSortKey.maxRate {
                    return leftSortKey.maxRate > rightSortKey.maxRate
                }
                if leftSortKey.downloadRate != rightSortKey.downloadRate {
                    return leftSortKey.downloadRate > rightSortKey.downloadRate
                }
                if leftSortKey.uploadRate != rightSortKey.uploadRate {
                    return leftSortKey.uploadRate > rightSortKey.uploadRate
                }
                return leftSortKey.normalizedName < rightSortKey.normalizedName
            }
    }
}
