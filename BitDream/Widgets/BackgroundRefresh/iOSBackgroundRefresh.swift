#if os(iOS)
import Foundation
import BackgroundTasks
import CoreData
import KeychainAccess
import WidgetKit

enum BackgroundRefreshManager {
    static let taskIdentifier = "crapshack.BitDream.refresh"

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            handle(task: task as! BGAppRefreshTask)
        }
    }

    static func schedule(earliestBegin interval: TimeInterval = 30 * 60) {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date().addingTimeInterval(interval)
        do { try BGTaskScheduler.shared.submit(request) } catch { }
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


