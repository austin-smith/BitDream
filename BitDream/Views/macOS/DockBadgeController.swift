#if os(macOS)
import AppKit
import Combine
import SwiftUI

// Keeps the Dock icon badge in sync with the completed torrent count,
// independent of the main window's lifecycle. The badge reflects live app
// state, so NSDockTile is used rather than UNUserNotificationCenter's
// badge APIs (which target persistent, notification-driven unread counts).
@MainActor
final class DockBadgeController: ObservableObject {
    private weak var store: TransmissionStore?
    private var cancellables = Set<AnyCancellable>()

    func configure(store: TransmissionStore) {
        if self.store !== store || cancellables.isEmpty {
            self.store = store
            observeChanges(store)
        }
        refresh()
    }

    private func observeChanges(_ store: TransmissionStore) {
        cancellables.removeAll()

        store.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refresh()
            }
            .store(in: &cancellables)

        // Reflect settings changes immediately, even when no window is open.
        NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refresh()
            }
            .store(in: &cancellables)
    }

    private func refresh() {
        let isEnabled = (UserDefaults.standard.object(forKey: UserDefaultsKeys.dockShowCompletedBadge) as? Bool)
            ?? AppDefaults.dockShowCompletedBadge
        let count = isEnabled ? completedTorrentsCount() : 0
        let badgeLabel = count > 0 ? "\(count)" : nil

        if NSApplication.shared.dockTile.badgeLabel != badgeLabel {
            NSApplication.shared.dockTile.badgeLabel = badgeLabel
        }
    }

    private func completedTorrentsCount() -> Int {
        guard let store, store.connectionStatus == .connected else { return 0 }
        return store.torrents.filter { $0.statusCalc == .complete }.count
    }
}
#endif
