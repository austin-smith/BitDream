import Foundation

public enum SortProperty: String, CaseIterable {
    case name = "Name"
    case size = "Size"
    case status = "Status"
    case dateAdded = "Date Added"
    case eta = "Remaining Time"
}

struct EtaSortKey: Comparable {
    let priority: Int
    let eta: Int

    static func < (lhs: EtaSortKey, rhs: EtaSortKey) -> Bool {
        if lhs.priority != rhs.priority {
            return lhs.priority < rhs.priority
        }
        return lhs.eta < rhs.eta
    }
}

fileprivate struct TorrentActivitySortKey {
    let maxRate: Int64
    let downloadRate: Int64
    let uploadRate: Int64
    let normalizedName: String
}

func makeEtaSortKey(for torrent: Torrent) -> EtaSortKey {
    let priority: Int
    if torrent.statusCalc == .complete {
        priority = 5
    } else if torrent.statusCalc == .seeding {
        priority = 4
    } else if torrent.statusCalc == .paused {
        priority = 3
    } else if torrent.statusCalc == .stalled {
        priority = 2
    } else if torrent.eta <= 0 {
        priority = 1
    } else {
        priority = 0
    }
    return EtaSortKey(priority: priority, eta: torrent.eta)
}

func sortTorrents(_ torrents: [Torrent], by property: SortProperty, order: SortOrder) -> [Torrent] {
    let sortedList = torrents.sortedAscending(using: .keyPath(\.name))

    switch property {
    case .name:
        return order == .ascending ? torrents.sortedAscending(using: .keyPath(\.name)) : torrents.sortedDescending(using: .keyPath(\.name))
    case .dateAdded:
        return order == .ascending ? sortedList.sortedAscending(using: .keyPath(\.addedDate)) : sortedList.sortedDescending(using: .keyPath(\.addedDate))
    case .status:
        return order == .ascending ? sortedList.sortedAscending(using: .keyPath(\.statusCalc.rawValue)) : sortedList.sortedDescending(using: .keyPath(\.statusCalc.rawValue))
    case .eta:
        return sortedList.sorted { leftTorrent, rightTorrent in
            let leftEtaSortKey = makeEtaSortKey(for: leftTorrent)
            let rightEtaSortKey = makeEtaSortKey(for: rightTorrent)
            if order == .ascending {
                return leftEtaSortKey < rightEtaSortKey
            }
            return leftEtaSortKey > rightEtaSortKey
        }
    case .size:
        return order == .ascending ? sortedList.sortedAscending(using: .keyPath(\.sizeWhenDone)) : sortedList.sortedDescending(using: .keyPath(\.sizeWhenDone))
    }
}

extension Torrent {
    fileprivate var activitySortKey: TorrentActivitySortKey {
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
