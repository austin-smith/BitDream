//  macOS background activity scheduler for widget updates.

#if os(macOS)
import Foundation
import WidgetKit

/// Manages background widget updates on macOS using NSBackgroundActivityScheduler
enum BackgroundActivityScheduler {
    private static var scheduler: NSBackgroundActivityScheduler?
    private static let activityIdentifier = "crapshack.BitDream.widgetRefresh"
    /// Default cadence for macOS background activity refresh (15 minutes)
    private static let defaultInterval: TimeInterval = 15 * 60
    /// Default tolerance to let the system batch work efficiently (5 minutes)
    private static let defaultTolerance: TimeInterval = 5 * 60

    /// Register and start the background activity scheduler
    static func register() {
        guard scheduler == nil else { return }

        let newScheduler = NSBackgroundActivityScheduler(identifier: activityIdentifier)
        newScheduler.repeats = true
        newScheduler.interval = defaultInterval
        newScheduler.tolerance = defaultTolerance
        newScheduler.qualityOfService = .utility

        newScheduler.schedule { [weak newScheduler] completion in
            guard newScheduler != nil else {
                completion(.finished)
                return
            }

            // Perform widget refresh
            performWidgetRefresh {
                completion(.finished)
            }
        }

        scheduler = newScheduler
    }

    /// Stop the background activity scheduler
    static func unregister() {
        scheduler?.invalidate()
        scheduler = nil
    }

    /// Update the refresh interval
    static func updateInterval(_ intervalInSeconds: Double) {
        // Minimum 5 minutes to be respectful of system resources
        let safeInterval = max(5 * 60, intervalInSeconds)

        unregister()

        let newScheduler = NSBackgroundActivityScheduler(identifier: activityIdentifier)
        newScheduler.repeats = true
        newScheduler.interval = safeInterval
        newScheduler.tolerance = min(5 * 60, safeInterval * 0.3) // 30% tolerance, max 5 minutes
        newScheduler.qualityOfService = .utility

        newScheduler.schedule { [weak newScheduler] completion in
            guard newScheduler != nil else {
                completion(.finished)
                return
            }

            performWidgetRefresh {
                completion(.finished)
            }
        }

        scheduler = newScheduler
    }

    /// Check if the scheduler is currently active
    static var isActive: Bool {
        return scheduler != nil
    }
}
#endif
