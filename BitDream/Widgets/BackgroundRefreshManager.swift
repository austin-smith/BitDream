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

        let operation = RefreshOperation()

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

private final class RefreshOperation: Operation, @unchecked Sendable {
    private let context: NSManagedObjectContext
    private let keychain = Keychain(service: "crapshack.BitDream")

    override init() {
        self.context = PersistenceController.shared.container.newBackgroundContext()
        self.context.mergePolicy = NSMergeByPropertyStoreTrumpMergePolicy
        super.init()
    }

    override func main() {
        if isCancelled { return }

        let hosts: [Host] = fetchHosts()
        guard !hosts.isEmpty else { return }

        for host in hosts {
            if isCancelled { break }
            refresh(host: host)
        }
        WidgetCenter.shared.reloadTimelines(ofKind: "SessionOverviewWidget")
    }

    private func fetchHosts() -> [Host] {
        let request = NSFetchRequest<Host>(entityName: "Host")
        request.includesPendingChanges = false
        return (try? context.fetch(request)) ?? []
    }

    private func refresh(host: Host) {
        // Build Transmission config/auth
        var config = TransmissionConfig()
        config.host = host.server
        config.port = Int(host.port)
        config.scheme = host.isSSL ? "https" : "http"

        let username = host.username ?? ""
        let password: String = {
            if let name = host.name, let stored = keychain[name] { return stored }
            return ""
        }()
        let auth = TransmissionAuth(username: username, password: password)

        let group = DispatchGroup()
        var stats: SessionStats?
        var torrents: [Torrent] = []

        // Fetch session stats
        group.enter()
        getSessionStats(config: config, auth: auth) { s, _ in
            stats = s
            group.leave()
        }

        // Fetch torrent list for status breakdown
        group.enter()
        getTorrents(config: config, auth: auth) { t, _ in
            torrents = t ?? []
            group.leave()
        }

        // Wait with timeout to respect BG limits
        _ = group.wait(timeout: .now() + 15)

        guard let stats = stats, !isCancelled else { return }

        // Write snapshots
        let tmpStore = Store()
        tmpStore.host = host
        tmpStore.torrents = torrents  // Populate with fetched torrents
        writeServersIndex(store: tmpStore)
        writeSessionSnapshot(store: tmpStore, stats: stats)
    }
}
#endif


