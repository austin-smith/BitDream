//  Shared refresh logic for both iOS and macOS widget background updates.

import Foundation
import Synchronization
import WidgetKit

private let widgetRefreshQueue: DispatchQueue = {
    DispatchQueue(label: RuntimeDomain.widgetRefreshQueue, qos: .utility)
}()

private final class WidgetRefreshCancellationToken: Sendable {
    private let isCancelledState = Mutex(false)

    func cancel() {
        isCancelledState.withLock { $0 = true }
    }

    func isCancelled() -> Bool {
        isCancelledState.withLock { $0 }
    }
}

struct WidgetRefreshHandle: Sendable {
    fileprivate let cancellationToken: WidgetRefreshCancellationToken

    func cancel() {
        cancellationToken.cancel()
    }

    var isCancelled: Bool {
        cancellationToken.isCancelled()
    }
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

private enum WidgetRefreshRunner {
    private static let backgroundWaitTimeout: DispatchTimeInterval = .seconds(15)

    static func run(isCancelled: @Sendable () -> Bool) -> Bool {
        if isCancelled() { return false }

        let hosts: [HostSnapshot] = fetchHosts()
        guard !hosts.isEmpty else { return !isCancelled() }

        let summaries = hosts.map { ServerSummary(id: $0.serverID, name: $0.name) }
        writeServersIndex(servers: summaries)

        for host in hosts {
            if isCancelled() { return false }
            refreshHost(host: host, isCancelled: isCancelled)
        }

        if isCancelled() { return false }

        // Reload widget timelines after all hosts are updated
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.sessionOverview)
        return true
    }

    private static func fetchHosts() -> [HostSnapshot] {
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

    private static func refreshHost(host: HostSnapshot, isCancelled: @Sendable () -> Bool) {
        if isCancelled() { return }

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
        let waitResult = group.wait(timeout: .now() + backgroundWaitTimeout)
        if waitResult == .timedOut {
            let hostIdentifier: String = host.name.isEmpty ? host.server : host.name
            print("WidgetRefreshRunner: timed out waiting for background fetches for host \(hostIdentifier)")
            return
        }

        if isCancelled() { return }

        let snapshot = results.snapshot()
        guard let stats = snapshot.stats else { return }

        let serverName = host.name
        writeSessionSnapshot(
            serverID: host.serverID,
            serverName: serverName,
            stats: stats,
            torrents: snapshot.torrents
        )
    }
}

private enum WidgetRefreshScheduler {
    @discardableResult
    static func enqueue(completion: (@Sendable (Bool) -> Void)? = nil) -> WidgetRefreshHandle {
        let cancellationToken = WidgetRefreshCancellationToken()
        let handle = WidgetRefreshHandle(cancellationToken: cancellationToken)

        widgetRefreshQueue.async {
            let success = WidgetRefreshRunner.run(isCancelled: { cancellationToken.isCancelled() })
            completion?(success)
        }

        return handle
    }
}

/// Convenience function to perform a widget refresh operation.
/// Returns a handle that can be used to request cancellation.
@discardableResult
func performWidgetRefresh(completion: (@Sendable () -> Void)? = nil) -> WidgetRefreshHandle {
    enqueueWidgetRefresh { _ in
        completion?()
    }
}

@discardableResult
func enqueueWidgetRefresh(completion: (@Sendable (Bool) -> Void)? = nil) -> WidgetRefreshHandle {
    WidgetRefreshScheduler.enqueue(completion: completion)
}
