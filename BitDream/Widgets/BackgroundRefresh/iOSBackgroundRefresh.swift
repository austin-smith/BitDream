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
    /// The earliest requested start is 15 minutes away; iOS decides whether and when to run.
    private static let defaultRefreshInterval: TimeInterval = 15 * 60

    static func register() {
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(task: refreshTask)
        }
        if !registered {
            logger.error("BGTaskScheduler registration failed for \(taskIdentifier)")
        }
    }

    static func schedule(earliestBegin interval: TimeInterval = defaultRefreshInterval) {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date().addingTimeInterval(interval)
        // Submitting the same identifier replaces its pending request.
        if #available(iOS 27, *) {
            BGTaskScheduler.shared.submitTaskRequest(request) { error in
                logSubmission(error: error)
            }
        } else {
            do {
                try BGTaskScheduler.shared.submit(request)
                logSubmission(error: nil)
            } catch {
                logSubmission(error: error)
            }
        }
    }

    private static func logSubmission(error: Error?) {
        if let error {
            logger.error("BGTaskScheduler submit failed for \(taskIdentifier): \(error.localizedDescription)")
        } else {
            logger.debug("BGTaskScheduler submitted \(taskIdentifier)")
        }
    }

    private static func handle(task: BGAppRefreshTask) {
        schedule() // Request another opportunity before starting this refresh.

        let taskBox = AppRefreshTaskBox(task: task)
        let refreshHandle = WidgetRefreshScheduler.enqueue { success in
            taskBox.complete(success: success)
        }

        task.expirationHandler = { [weak taskBox] in
            guard let taskBox else { return }
            refreshHandle.cancel()
            taskBox.complete(success: false)
        }
    }
}
#endif
