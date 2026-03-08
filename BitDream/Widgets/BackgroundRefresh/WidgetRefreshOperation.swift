//  Shared refresh logic for both iOS and macOS widget background updates.

import Foundation
import WidgetKit
import OSLog

struct WidgetRefreshHandle: Sendable {
    fileprivate let task: Task<Bool, Never>

    func cancel() {
        task.cancel()
    }

    var isCancelled: Bool {
        task.isCancelled
    }
}

struct WidgetRefreshDependencies: Sendable {
    let connectionFactory: TransmissionConnectionFactory
    let snapshotWriter: WidgetSnapshotWriter
    let loadHosts: @Sendable () -> [HostRefreshRecord]
    let sleep: @Sendable (TimeInterval) async throws -> Void

    static let live = Self(
        connectionFactory: TransmissionConnectionFactory(),
        snapshotWriter: .live,
        loadHosts: { HostRefreshCatalogStore.loadRecordsSnapshot() },
        sleep: { seconds in
            let nanoseconds = UInt64(max(0, seconds) * 1_000_000_000)
            try await Task.sleep(nanoseconds: nanoseconds)
        }
    )
}

enum WidgetRefreshRunner {
    static let backgroundWaitTimeout: TimeInterval = 15
    private static let logger = Logger(subsystem: AppIdentity.bundleIdentifier, category: "backgroundRefresh")

    static func run(
        dependencies: WidgetRefreshDependencies = .live,
        isCancelled: @Sendable () -> Bool = { Task.isCancelled }
    ) async -> Bool {
        if isCancelled() { return false }

        let hosts = fetchHosts(loadHosts: dependencies.loadHosts)
        guard !hosts.isEmpty else { return !isCancelled() }

        let summaries = hosts.map { ServerSummary(id: $0.serverID, name: $0.name) }
        dependencies.snapshotWriter.writeServerIndex(summaries)

        for host in hosts {
            if isCancelled() { return false }
            await refreshHost(host: host, dependencies: dependencies, isCancelled: isCancelled)
        }

        if isCancelled() { return false }

        dependencies.snapshotWriter.reloadTimelines()
        return true
    }

    private static func fetchHosts(
        loadHosts: @Sendable () -> [HostRefreshRecord]
    ) -> [HostRefreshRecord] {
        loadHosts().compactMap { host in
            let server = host.server.trimmingCharacters(in: .whitespacesAndNewlines)
            let credentialKey = host.credentialKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !server.isEmpty, !credentialKey.isEmpty else {
                return nil
            }

            return HostRefreshRecord(
                serverID: host.serverID,
                name: host.name,
                server: server,
                port: host.port,
                username: host.username,
                isSSL: host.isSSL,
                credentialKey: credentialKey,
                isDefault: host.isDefault,
                version: host.version
            )
        }
    }

    private static func refreshHost(
        host: HostRefreshRecord,
        dependencies: WidgetRefreshDependencies,
        isCancelled: @Sendable () -> Bool
    ) async {
        guard !isCancelled() else { return }

        let hostIdentifier = host.name.isEmpty ? host.server : host.name

        do {
            let connection = try await dependencies.connectionFactory.connection(
                for: TransmissionConnectionDescriptor(record: host)
            )
            let snapshot = try await withTimeout(
                seconds: backgroundWaitTimeout,
                sleep: dependencies.sleep
            ) {
                try await connection.fetchWidgetRefreshSnapshot()
            }

            guard !isCancelled() else { return }

            dependencies.snapshotWriter.writeSessionSnapshot(
                host.serverID,
                host.name,
                snapshot.sessionStats,
                snapshot.torrents,
                false
            )

            if let error = snapshot.torrentSummaryError {
                let presentation = TransmissionErrorPresenter.presentation(for: error)
                logger.notice(
                    "Background refresh could not refresh torrent list for host \(hostIdentifier, privacy: .public): \(presentation.message, privacy: .public)"
                )
            }
        } catch {
            guard !isCancelled() else { return }

            let transmissionError = TransmissionErrorResolver.transmissionError(from: error)
            let presentation = TransmissionErrorPresenter.presentation(for: transmissionError)
            logger.notice(
                "Background refresh failed for host \(hostIdentifier, privacy: .public): \(presentation.message, privacy: .public)"
            )
        }
    }

    private static func withTimeout<Success: Sendable>(
        seconds: TimeInterval,
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void,
        operation: @escaping @Sendable () async throws -> Success
    ) async throws -> Success {
        try await withThrowingTaskGroup(of: Success.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await sleep(seconds)
                throw TransmissionError.timeout
            }

            defer {
                group.cancelAll()
            }

            guard let result = try await group.next() else {
                throw TransmissionError.invalidResponse
            }
            return result
        }
    }
}

private enum WidgetRefreshScheduler {
    private static let state = SchedulerState()

    @discardableResult
    static func enqueue(
        dependencies: WidgetRefreshDependencies = .live,
        completion: (@Sendable (Bool) -> Void)? = nil
    ) -> WidgetRefreshHandle {
        state.enqueue(dependencies: dependencies, completion: completion)
    }

    private final class SchedulerState: @unchecked Sendable {
        private let lock = NSLock()
        private var tailTask: Task<Bool, Never>?

        func enqueue(
            dependencies: WidgetRefreshDependencies,
            completion: (@Sendable (Bool) -> Void)?
        ) -> WidgetRefreshHandle {
            lock.lock()
            let predecessor = tailTask
            let task = Task.detached(priority: .utility) { () -> Bool in
                if let predecessor {
                    _ = await predecessor.value
                }

                guard !Task.isCancelled else {
                    return false
                }

                let success = await WidgetRefreshRunner.run(dependencies: dependencies)
                guard !Task.isCancelled else {
                    return false
                }

                completion?(success)
                return success
            }
            tailTask = task
            lock.unlock()

            return WidgetRefreshHandle(task: task)
        }
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
func enqueueWidgetRefresh(
    dependencies: WidgetRefreshDependencies = .live,
    completion: (@Sendable (Bool) -> Void)? = nil
) -> WidgetRefreshHandle {
    WidgetRefreshScheduler.enqueue(dependencies: dependencies, completion: completion)
}
