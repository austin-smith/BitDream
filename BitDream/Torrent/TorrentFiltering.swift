import Foundation

enum TorrentLabelRule: String {
    case none = "No Filter"
    case include = "Include"
    case exclude = "Exclude"

    var next: Self {
        switch self {
        case .none:
            return .include
        case .include:
            return .exclude
        case .exclude:
            return .none
        }
    }
}

struct TorrentLabelFilter: Equatable {
    var includedLabels: Set<String> = []
    var excludedLabels: Set<String> = []
    var showsUnlabeledOnly = false

    var activeCount: Int {
        includedLabels.count + excludedLabels.count + (showsUnlabeledOnly ? 1 : 0)
    }

    var isActive: Bool {
        activeCount > 0
    }

    func rule(for label: String) -> TorrentLabelRule {
        if includedLabels.contains(caseInsensitive: label) {
            return .include
        }
        if excludedLabels.contains(caseInsensitive: label) {
            return .exclude
        }
        return .none
    }

    mutating func setRule(_ rule: TorrentLabelRule, for label: String) {
        includedLabels.remove(caseInsensitive: label)
        excludedLabels.remove(caseInsensitive: label)

        switch rule {
        case .none:
            break
        case .include:
            includedLabels.insert(label)
            showsUnlabeledOnly = false
        case .exclude:
            excludedLabels.insert(label)
            showsUnlabeledOnly = false
        }
    }

    mutating func advanceRule(for label: String) {
        setRule(rule(for: label).next, for: label)
    }

    mutating func setShowsUnlabeledOnly(_ showsUnlabeledOnly: Bool) {
        self.showsUnlabeledOnly = showsUnlabeledOnly

        if showsUnlabeledOnly {
            includedLabels.removeAll()
            excludedLabels.removeAll()
        }
    }

    mutating func reconcile(with availableLabels: [String]) {
        let includedKeys = Set(includedLabels.map { $0.lowercased() })
        let excludedKeys = Set(excludedLabels.map { $0.lowercased() })

        includedLabels = Set(
            availableLabels.filter { includedKeys.contains($0.lowercased()) }
        )
        excludedLabels = Set(
            availableLabels.filter { excludedKeys.contains($0.lowercased()) }
        )
    }

    mutating func clear() {
        includedLabels.removeAll()
        excludedLabels.removeAll()
        showsUnlabeledOnly = false
    }
}

struct TorrentDisplayOptions {
    let statusFilter: [TorrentStatusCalc]
    let labelFilter: TorrentLabelFilter
    let searchText: String
    let sortProperty: SortProperty
    let sortOrder: SortOrder
}

extension Array where Element == Torrent {
    func filtered(by statusFilter: [TorrentStatusCalc]) -> [Torrent] {
        guard statusFilter != TorrentStatusCalc.allCases else {
            return self
        }

        return filter { statusFilter.contains($0.statusCalc) }
    }

    func filtered(by labelFilter: TorrentLabelFilter) -> [Torrent] {
        guard labelFilter.isActive else {
            return self
        }

        let includedLabels = Set(labelFilter.includedLabels.map { $0.lowercased() })
        let excludedLabels = Set(labelFilter.excludedLabels.map { $0.lowercased() })

        return filter { torrent in
            if labelFilter.showsUnlabeledOnly {
                return torrent.labels.isEmpty
            }

            let torrentLabels = Set(torrent.labels.map { $0.lowercased() })
            let matchesIncludedLabel = includedLabels.isEmpty
                || !torrentLabels.isDisjoint(with: includedLabels)
            let matchesExcludedLabel = !torrentLabels.isDisjoint(with: excludedLabels)

            return matchesIncludedLabel && !matchesExcludedLabel
        }
    }

    func filtered(
        by statusFilter: [TorrentStatusCalc],
        labelFilter: TorrentLabelFilter,
        searchText: String
    ) -> [Torrent] {
        let filteredByStatusAndLabel = filtered(by: statusFilter)
            .filtered(by: labelFilter)

        guard !searchText.isEmpty else {
            return filteredByStatusAndLabel
        }

        return filteredByStatusAndLabel.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }
}

func filterAndSortTorrents(
    _ torrents: [Torrent],
    options: TorrentDisplayOptions
) -> [Torrent] {
    let filteredTorrents = torrents.filtered(
        by: options.statusFilter,
        labelFilter: options.labelFilter,
        searchText: options.searchText
    )

    return sortTorrents(
        filteredTorrents,
        by: options.sortProperty,
        order: options.sortOrder
    )
}

private extension Set where Element == String {
    func contains(caseInsensitive value: String) -> Bool {
        contains { $0.localizedCaseInsensitiveCompare(value) == .orderedSame }
    }

    mutating func remove(caseInsensitive value: String) {
        guard let matchingValue = first(where: {
            $0.localizedCaseInsensitiveCompare(value) == .orderedSame
        }) else {
            return
        }

        remove(matchingValue)
    }
}
