//  Shared refresh logic for both iOS and macOS widget background updates.

import Foundation
import Synchronization
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
/// execution context, and fetches hosts from an app-private refresh catalog.
/// Safety invariant for `@unchecked Sendable`: operations are enqueued on a queue with
/// `maxConcurrentOperationCount = 1`, and any cross-callback mutable state is guarded by
/// `HostRefreshResultStore`'s `Mutex` (or otherwise kept operation-local).
final class WidgetRefreshOperation: Operation, @unchecked Sendable {
    private static let backgroundWaitTimeout: DispatchTimeInterval = .seconds(15)
}

private struct HostSnapshot: Sendable {
    let serverID: String
    let name: String
    let server: String
    let port: Int
    let username: String
    let isSSL: Bool
    let credentialKey: String
}

private final class HostRefreshResultStore: Sendable {
    private struct State: Sendable {
        var stats: SessionStats?
        var torrents: [Torrent] = []
    }

    private let state = Mutex(State())

    func setStats(_ value: SessionStats?) {
        state.withLock { $0.stats = value }
    }

    func setTorrents(_ value: [Torrent]) {
        state.withLock { $0.torrents = value }
    }

    func snapshot() -> (stats: SessionStats?, torrents: [Torrent]) {
        state.withLock { ($0.stats, $0.torrents) }
    }
}

extension WidgetRefreshOperation {
    override func main() {
        if isCancelled { return }

        let hosts: [HostSnapshot] = fetchHosts()
        guard !hosts.isEmpty else { return }

        let summaries = hosts.map { ServerSummary(id: $0.serverID, name: $0.name) }
        writeServersIndex(servers: summaries)

        for host in hosts {
            if isCancelled { break }
            refreshHost(host: host)
        }

        // Reload widget timelines after all hosts are updated
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.sessionOverview)
    }

    private func fetchHosts() -> [HostSnapshot] {
        let hosts = HostRefreshCatalogStore.loadRecordsSnapshot()

        return hosts.compactMap { host in
            let server = host.server.trimmingCharacters(in: .whitespacesAndNewlines)
            let credentialKey = host.credentialKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !server.isEmpty, !credentialKey.isEmpty else {
                return nil
            }

            return HostSnapshot(
                serverID: host.serverID,
                name: host.name,
                server: server,
                port: host.port,
                username: host.username,
                isSSL: host.isSSL,
                credentialKey: credentialKey
            )
        }
    }

    private func refreshHost(host: HostSnapshot) {
        // Build Transmission config/auth
        var config = TransmissionConfig()
        config.host = host.server
        config.port = Int(host.port)
        config.scheme = host.isSSL ? "https" : "http"

        let username = host.username
        let password = KeychainPasswordStore.readPassword(credentialKey: host.credentialKey)
        let auth = TransmissionAuth(username: username, password: password)

        let group = DispatchGroup()
        let results = HostRefreshResultStore()

        // Fetch session stats
        group.enter()
        // Widget refresh intentionally uses a non-@MainActor path to avoid pumping through the main actor.
        getSessionStatsForWidgetRefresh(config: config, auth: auth) { s, _ in
            results.setStats(s)
            group.leave()
        }

        // Fetch torrent list for status breakdown
        group.enter()
        getTorrentsForWidgetRefresh(config: config, auth: auth) { t, _ in
            results.setTorrents(t ?? [])
            group.leave()
        }

        // Wait with timeout to respect background limits
        let waitResult = group.wait(timeout: .now() + Self.backgroundWaitTimeout)
        if waitResult == .timedOut {
            let hostIdentifier: String = host.name.isEmpty ? host.server : host.name
            print("WidgetRefreshOperation: timed out waiting for background fetches for host \(hostIdentifier)")
            return
        }

        let snapshot = results.snapshot()
        guard let stats = snapshot.stats, !isCancelled else { return }

        let serverName = host.name
        writeSessionSnapshot(
            serverID: host.serverID,
            serverName: serverName,
            stats: stats,
            torrents: snapshot.torrents
        )
    }
}

/// Convenience function to perform a widget refresh operation
func performWidgetRefresh(completion: (@Sendable () -> Void)? = nil) {
    let operation = WidgetRefreshOperation()
    operation.qualityOfService = .utility

    operation.completionBlock = {
        completion?()
    }

    WidgetRefreshOperation.enqueue(operation)
}

extension WidgetRefreshOperation {
    static func enqueue(_ operation: WidgetRefreshOperation) {
        widgetRefreshQueue.addOperation(operation)
    }
}
