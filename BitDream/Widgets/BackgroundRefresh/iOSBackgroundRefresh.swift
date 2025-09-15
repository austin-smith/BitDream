#if os(iOS)
import Foundation
import BackgroundTasks
import CoreData
import KeychainAccess
import WidgetKit

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

        task.expirationHandler = {
            operation.cancel()
        }

        operation.completionBlock = {
            let success = !operation.isCancelled
            task.setTaskCompleted(success: success)
        }

        OperationQueue().addOperation(operation)
    }
}
#endif


