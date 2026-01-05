//  Shared refresh logic for both iOS and macOS widget background updates.

import Foundation
import CoreData
import KeychainAccess
import WidgetKit

private let widgetRefreshQueue: OperationQueue = {
    let queue = OperationQueue()
    queue.name = "com.bitdream.widgetRefreshQueue"
    queue.maxConcurrentOperationCount = 1
    queue.qualityOfService = .utility
    return queue
}()

/// Shared operation that fetches data for all servers and writes widget snapshots.
/// Concurrency: Runs on an `OperationQueue`, confines mutable state to the operation's
/// execution context, and uses a private Core Data background context.
final class WidgetRefreshOperation: Operation, @unchecked Sendable {
    private let context: NSManagedObjectContext
    private let keychain = Keychain(service: "crapshack.BitDream")
    private static let backgroundWaitTimeout: DispatchTimeInterval = .seconds(15)

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
            refreshHost(host: host)
        }

        // Reload widget timelines after all hosts are updated
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.sessionOverview)
    }

    private func fetchHosts() -> [Host] {
        let request = NSFetchRequest<Host>(entityName: "Host")
        request.includesPendingChanges = false
        return (try? context.fetch(request)) ?? []
    }

    private func refreshHost(host: Host) {
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

        // Wait with timeout to respect background limits
        let waitResult = group.wait(timeout: .now() + Self.backgroundWaitTimeout)
        if waitResult == .timedOut {
            let hostIdentifier: String = host.name ?? host.server ?? "Server"
            print("WidgetRefreshOperation: timed out waiting for background fetches for host \(hostIdentifier)")
            return
        }

        guard let stats = stats, !isCancelled else { return }

        // Write snapshots using temporary store
        let tmpStore = Store()
        tmpStore.host = host
        tmpStore.torrents = torrents
        writeServersIndex(store: tmpStore)
        writeSessionSnapshot(store: tmpStore, stats: stats)
    }
}

/// Convenience function to perform a widget refresh operation
func performWidgetRefresh(completion: (() -> Void)? = nil) {
    let operation = WidgetRefreshOperation()
    operation.qualityOfService = .utility

    operation.completionBlock = {
        DispatchQueue.main.async {
            completion?()
        }
    }

    WidgetRefreshOperation.enqueue(operation)
}

extension WidgetRefreshOperation {
    static func enqueue(_ operation: WidgetRefreshOperation) {
        widgetRefreshQueue.addOperation(operation)
    }
}
