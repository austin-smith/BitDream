//  Shared refresh logic for both iOS and macOS widget background updates.

import Foundation
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
            let hostIdentifier: String = host.name.isEmpty ? host.server : host.name
            print("WidgetRefreshOperation: timed out waiting for background fetches for host \(hostIdentifier)")
            return
        }

        guard let stats = stats, !isCancelled else { return }

        let serverName = host.name
        writeSessionSnapshot(
            serverID: host.serverID,
            serverName: serverName,
            stats: stats,
            torrents: torrents
        )
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
