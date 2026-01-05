import SwiftUI
import UserNotifications

#if os(macOS)
class AppBadgeManager: ObservableObject {
    static let shared = AppBadgeManager()

    init() {
        // Request permission to use badges
        requestNotificationPermissions()
    }

    func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.badge]) { granted, error in
            if let error = error {
                print("Error requesting notification authorization: \(error)")
            }
        }
    }

    // Update badge with completed torrents count
    func updateBadge(completedCount: Int) {
        NSApplication.shared.dockTile.badgeLabel = completedCount > 0 ? "\(completedCount)" : ""
    }
}
#endif