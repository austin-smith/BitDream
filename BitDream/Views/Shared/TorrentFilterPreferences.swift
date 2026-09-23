import Foundation
import Observation

@MainActor
@Observable
final class TorrentFilterPreferences {
    private enum Keys {
        static let status = "torrentStatusFilter"
        static let labels = "torrentLabelFilter."
        static let included = "includedLabels"
        static let excluded = "excludedLabels"
        static let unlabeled = "showsUnlabeledOnly"
    }

    private let userDefaults: UserDefaults
    private var serverID: String?

    var sidebarSelection: SidebarSelection {
        didSet {
            userDefaults.set(sidebarSelection.rawValue, forKey: Keys.status)
        }
    }

    var labelFilter: TorrentLabelFilter {
        didSet {
            guard let serverID, labelFilter != oldValue else { return }
            let key = Keys.labels + serverID
            guard labelFilter.isActive else {
                userDefaults.removeObject(forKey: key)
                return
            }
            userDefaults.set([
                Keys.included: labelFilter.includedLabels.sorted(),
                Keys.excluded: labelFilter.excludedLabels.sorted(),
                Keys.unlabeled: labelFilter.showsUnlabeledOnly
            ], forKey: key)
        }
    }

    init(userDefaults: UserDefaults, serverID: String?) {
        self.userDefaults = userDefaults
        self.serverID = serverID
        sidebarSelection = userDefaults.string(forKey: Keys.status)
            .flatMap(SidebarSelection.init(rawValue:)) ?? .allDreams
        labelFilter = Self.savedLabels(for: serverID, in: userDefaults)
    }

    func selectServer(_ serverID: String?) {
        guard self.serverID != serverID else { return }
        self.serverID = serverID
        labelFilter = Self.savedLabels(for: serverID, in: userDefaults)
    }

    func synchronize(serverID: String?, availableLabels: [String], hasLoadedSnapshot: Bool) {
        selectServer(serverID)
        reconcileLabels(with: availableLabels, hasLoadedSnapshot: hasLoadedSnapshot)
    }

    func reconcileLabels(with availableLabels: [String], hasLoadedSnapshot: Bool) {
        // An empty list during connection setup is not the server's saved label list.
        guard serverID != nil, hasLoadedSnapshot else { return }
        var reconciledFilter = labelFilter
        reconciledFilter.reconcile(with: availableLabels)
        if reconciledFilter != labelFilter {
            labelFilter = reconciledFilter
        }
    }

    private static func savedLabels(for serverID: String?, in userDefaults: UserDefaults) -> TorrentLabelFilter {
        guard let serverID,
              let saved = userDefaults.dictionary(forKey: Keys.labels + serverID) else {
            return TorrentLabelFilter()
        }
        return TorrentLabelFilter(
            includedLabels: Set(saved[Keys.included] as? [String] ?? []),
            excludedLabels: Set(saved[Keys.excluded] as? [String] ?? []),
            showsUnlabeledOnly: saved[Keys.unlabeled] as? Bool ?? false
        )
    }
}
