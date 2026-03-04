#if os(iOS)
import Foundation
import BackgroundTasks
import Synchronization
import WidgetKit

/// Bridges non-Sendable `BGAppRefreshTask` into `@Sendable` completion contexts.
/// Safety invariant: `setTaskCompleted` is invoked at most once, guarded by a mutex.
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
    static let taskIdentifier = "crapshack.BitDream.refresh"
    /// Default refresh cadence for background app refresh (15 minutes)
    /// iOS executes opportunistically; this expresses our desired minimum cadence
    private static let defaultRefreshInterval: TimeInterval = 15 * 60

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            handle(task: task as! BGAppRefreshTask)
        }
    }

    static func schedule(earliestBegin interval: TimeInterval = defaultRefreshInterval) {
        // Ensure only one pending refresh request exists for this identifier
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date().addingTimeInterval(interval)
        do { try BGTaskScheduler.shared.submit(request) } catch {
            print("BGTaskScheduler submit failed for \(taskIdentifier): \(error)")
        }
    }

    private static func handle(task: BGAppRefreshTask) {
        schedule() // schedule the next one ASAP to keep cadence

        let operation = WidgetRefreshOperation()
        let taskBox = AppRefreshTaskBox(task: task)
        operation.qualityOfService = .utility

        task.expirationHandler = {
            operation.cancel()
            taskBox.complete(success: false)
        }

        operation.completionBlock = {
            let success = !operation.isCancelled
            taskBox.complete(success: success)
        }

        WidgetRefreshOperation.enqueue(operation)
    }
}
#endif
