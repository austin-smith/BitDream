#if os(iOS)
import Foundation
import BackgroundTasks
import Synchronization
import OSLog

/// Bridges non-Sendable `BGAppRefreshTask` into `@Sendable` completion contexts.
/// Safety invariant: `setTaskCompleted(success:)` is invoked at most once, guarded by a mutex.
private final class AppRefreshTaskBox: @unchecked Sendable {
    private let task: BGAppRefreshTask
    private let completionState = Mutex(false)

    init(task: BGAppRefreshTask) {
        self.task = task
    }

    func complete(success: Bool) {
        let shouldComplete = completionState.withLock { completed in
            guard !completed else { return false }
            completed = true
            return true
        }
        guard shouldComplete else { return }
        task.setTaskCompleted(success: success)
    }
}

enum BackgroundRefreshManager {
    static let taskIdentifier = "\(AppIdentity.bundleIdentifier).refresh"
    private static let logger = Logger(subsystem: AppIdentity.bundleIdentifier, category: "backgroundRefresh")
    /// Default refresh cadence for background app refresh (15 minutes)
    /// iOS executes opportunistically; this expresses our desired minimum cadence
    private static let defaultRefreshInterval: TimeInterval = 15 * 60

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(task: refreshTask)
        }
    }

    static func schedule(earliestBegin interval: TimeInterval = defaultRefreshInterval) {
        // Ensure only one pending refresh request exists for this identifier
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date().addingTimeInterval(interval)
        do { try BGTaskScheduler.shared.submit(request) } catch {
            logger.error("BGTaskScheduler submit failed for \(taskIdentifier): \(error.localizedDescription)")
        }
    }

    private static func handle(task: BGAppRefreshTask) {
        schedule() // schedule the next one ASAP to keep cadence

        let taskBox = AppRefreshTaskBox(task: task)
        let refreshHandle = WidgetRefreshScheduler.enqueue { success in
            taskBox.complete(success: success)
        }

        task.expirationHandler = {
            refreshHandle.cancel()
            taskBox.complete(success: false)
        }
    }
}
#endif
