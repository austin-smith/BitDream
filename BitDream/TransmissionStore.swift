import SwiftUI
import Foundation
import SwiftData
import OSLog

#if os(macOS)
enum AddTorrentInitialMode {
    case magnet
    case file
}
#endif

@MainActor
final class TransmissionStore: NSObject, ObservableObject {
    private struct ActiveConnection: Sendable {
        let hostID: String
        let serverName: String
        let connection: TransmissionConnection
        let generation: UUID
    }

    private enum ConnectionAttemptReason {
        case hostSelection
        case hostConfigurationChange
        case manualReconnect
        case automaticRetry

        var resetsReconnectBackoff: Bool {
            switch self {
            case .automaticRetry:
                return false
            case .hostSelection, .hostConfigurationChange, .manualReconnect:
                return true
            }
        }
    }

    private struct ExponentialBackoff {
        private(set) var attempt: Int = 0
        let base: TimeInterval
        let maxDelay: TimeInterval
        let jitterRange: ClosedRange<Double>

        init(base: TimeInterval, maxDelay: TimeInterval, jitterRange: ClosedRange<Double> = 0.85...1.15) {
            self.base = base
            self.maxDelay = maxDelay
            self.jitterRange = jitterRange
        }

        mutating func nextDelay() -> TimeInterval {
            let exponentialDelay = min(base * pow(2, Double(attempt)), maxDelay)
            let jitter = Double.random(in: jitterRange)
            attempt += 1
            return Swift.max(base, exponentialDelay * jitter)
        }

        mutating func reset() {
            attempt = 0
        }
    }

    @Published var torrents: [Torrent] = []
    @Published var sessionStats: SessionStats?
    @Published var setup: Bool = false
    @Published var host: Host?

    @Published var defaultDownloadDir: String = ""

    @Published var isShowingAddAlert: Bool = false
    // When presenting Add Torrent, optional prefill for the magnet link input (macOS only used)
    @Published var addTorrentPrefill: String?
    // Queue of pending magnet links to present sequentially (macOS)
    @Published var pendingMagnetQueue: [String] = []
    // Visual indicator state for queued magnets
    @Published var magnetQueueDisplayIndex: Int = 0
    @Published var magnetQueueTotal: Int = 0
    @Published var isShowingServerAlert: Bool = false
    @Published var editServers: Bool = false
    @Published var showSettings: Bool = false

    @Published var isError: Bool = false
    @Published var debugBrief: String = ""
    @Published var debugMessage: String = ""

    enum ConnectionStatus {
        case connecting
        case connected
        case reconnecting
    }

    @Published var connectionStatus: ConnectionStatus = .connecting
    @Published var lastRefreshAt: Date?
    @Published var lastErrorMessage: String = ""
    @Published var nextRetryAt: Date?

    @Published var showConnectionErrorAlert: Bool = false

    @Published var sessionConfiguration: TransmissionSessionResponseArguments?
    @Published private(set) var settingsConnectionGeneration = UUID()

    @Published var pollInterval: Double = AppDefaults.pollInterval // Default poll interval in seconds
    @Published var shouldActivateSearch: Bool = false
    @Published var shouldToggleInspector: Bool = false
    @Published var isInspectorVisible: Bool = UserDefaults.standard.inspectorVisibility

#if os(macOS)
    // Controls how the Add Torrent flow should start when invoked from menu
    @Published var addTorrentInitialMode: AddTorrentInitialMode?
    // Triggers a global file importer from top-level window
    @Published var presentGlobalTorrentFileImporter: Bool = false
    // Global native alert state for macOS
    @Published var showGlobalAlert: Bool = false
    @Published var globalAlertTitle: String = "Error"
    @Published var globalAlertMessage: String = ""
    // Global rename dialog state for menu command
    @Published var showGlobalRenameDialog: Bool = false
    @Published var globalRenameInput: String = ""
    @Published var globalRenameTargetId: Int?
#endif

    // Confirmation dialog state for menu remove command
    @Published var showingMenuRemoveConfirmation = false

    private let connectionFactory: TransmissionConnectionFactory
    private let snapshotWriter: WidgetSnapshotWriter
    private let sleep: @Sendable (TimeInterval) async throws -> Void
    private let persistVersion: @MainActor @Sendable (String, String) async -> Void

    private var activeConnection: ActiveConnection?
    private var currentConnectionGeneration = UUID()
    private var activationTask: Task<Void, Never>?
    private var fullRefreshTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var sessionRefreshTask: Task<Void, Never>?

    private var reconnectBackoff = ExponentialBackoff(base: 1, maxDelay: 30)
    private let logger = Logger(subsystem: AppIdentity.bundleIdentifier, category: "network")

    var canAttemptReconnect: Bool {
        guard connectionStatus == .reconnecting else { return true }
        guard let nextRetryAt = nextRetryAt else { return true }
        return Date() >= nextRetryAt
    }

    init(
        connectionFactory: TransmissionConnectionFactory = TransmissionConnectionFactory(),
        snapshotWriter: WidgetSnapshotWriter = .live,
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void = TransmissionStore.liveSleep,
        persistVersion: @escaping @MainActor @Sendable (String, String) async -> Void = { serverID, version in
            await HostRepository.shared.persistVersionIfNeeded(serverID: serverID, version: version)
        }
    ) {
        self.connectionFactory = connectionFactory
        self.snapshotWriter = snapshotWriter
        self.sleep = sleep
        self.persistVersion = persistVersion
        super.init()
        // Load persisted poll interval if available
        if let saved = UserDefaults.standard.object(forKey: UserDefaultsKeys.pollInterval) as? Double {
            self.pollInterval = max(1.0, saved)
        } else {
            self.pollInterval = AppDefaults.pollInterval
        }
    }
}

@MainActor
extension TransmissionStore {
    // MARK: - Magnet Queue Helpers (macOS)
    #if os(macOS)
    func enqueueMagnet(_ magnet: String) {
        let wasEmpty = pendingMagnetQueue.isEmpty
        pendingMagnetQueue.append(magnet)
        if wasEmpty {
            // New batch
            magnetQueueTotal = pendingMagnetQueue.count
            magnetQueueDisplayIndex = 1
            if !isShowingAddAlert {
                presentNextMagnetIfAvailable()
            }
        } else {
            // Increase total while batch is in progress
            magnetQueueTotal += 1
        }
    }

    func presentNextMagnetIfAvailable() {
        guard let next = pendingMagnetQueue.first else { return }
        addTorrentPrefill = next
        addTorrentInitialMode = .magnet
        isShowingAddAlert = true
    }

    func advanceMagnetQueue() {
        if !pendingMagnetQueue.isEmpty {
            pendingMagnetQueue.removeFirst()
        }
        if !pendingMagnetQueue.isEmpty {
            // Move to next item in the same batch
            magnetQueueDisplayIndex = min(magnetQueueDisplayIndex + 1, magnetQueueTotal)
            presentNextMagnetIfAvailable()
        } else {
            // Batch complete
            magnetQueueDisplayIndex = 0
            magnetQueueTotal = 0
        }
    }
    #endif

    public func setHost(host: Host) {
        // Avoid redundant resets if host is unchanged (prevents list flash)
        if let current = self.host, current.serverID == host.serverID {
            return
        }

        replaceConnection(for: host, trigger: .hostSelection)
    }

    func applyPersistedHostUpdate(_ host: Host) {
        guard self.host?.serverID == host.serverID else {
            return
        }

        replaceConnection(for: host, trigger: .hostConfigurationChange)
    }

    func readPassword(for host: Host) -> String {
        guard let credentialKey = KeychainService.credentialKeyIfPresent(for: host) else {
            return ""
        }
        return KeychainService.readPassword(credentialKey: credentialKey)
    }

    // Method to reconnect to the server
    func reconnect() {
        guard let host = self.host else { return }

        replaceConnection(for: host, trigger: .manualReconnect)
    }

    // Method to refresh session configuration after settings changes
    func refreshSessionConfiguration() {
        guard let activeConnection else { return }

        if let existing = sessionRefreshTask {
            existing.cancel()
        }

        sessionRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.sessionRefreshTask = nil }
            await self.performSessionOnlyRefresh(for: activeConnection)
        }
    }

    func applySessionSettings(_ args: TransmissionSessionSetRequestArgs) async throws -> TransmissionSessionResponseArguments {
        let connectionState = try requireActiveConnection()
        try await connectionState.connection.setSession(args)
        try ensureCurrent(connectionState)
        return try await refreshSessionConfiguration(for: connectionState)
    }

    func checkFreeSpace(path: String) async throws -> FreeSpaceResponse {
        let connectionState = try requireActiveConnection()
        let response = try await connectionState.connection.checkFreeSpace(path: path)
        try ensureCurrent(connectionState)
        return response
    }

    func testPort(ipProtocol: String? = nil) async throws -> PortTestResponse {
        let connectionState = try requireActiveConnection()
        let response = try await connectionState.connection.testPort(ipProtocol: ipProtocol)
        try ensureCurrent(connectionState)
        return response
    }

    func updateBlocklist() async throws -> BlocklistUpdateResponse {
        let connectionState = try requireActiveConnection()
        let response = try await connectionState.connection.updateBlocklist()
        try ensureCurrent(connectionState)
        _ = try await refreshSessionConfiguration(for: connectionState)
        return response
    }

    func clearReconnectPresentationState() {
        nextRetryAt = nil
        cancelRetryTask()
        showConnectionErrorAlert = false
    }

    func clearPendingRetrySchedule() {
        nextRetryAt = nil
        retryTask = nil
    }

    func resetReconnectBackoff() {
        reconnectBackoff.reset()
    }

    func resetReconnectState() {
        clearReconnectPresentationState()
        resetReconnectBackoff()
    }

    func markConnecting() {
        connectionStatus = .connecting
    }

    func markConnected() {
        resetReconnectState()
        connectionStatus = .connected
        lastErrorMessage = ""
        lastRefreshAt = Date()
    }

    func retryNow() {
        resetReconnectState()

        if activeConnection != nil {
            requestRefresh()
            return
        }

        if let host {
            replaceConnection(for: host, trigger: .manualReconnect)
        }
    }

    // Method to handle connection errors
    func handleConnectionError(_ error: TransmissionError) {
        let now = Date()
        let wasReconnecting = connectionStatus == .reconnecting
        let presentation = TransmissionErrorPresenter.presentation(for: error)

        lastErrorMessage = presentation.message
        connectionStatus = .reconnecting

        if !wasReconnecting {
            cancelPollTask()
        }

        if let nextRetryAt, nextRetryAt > now {
            if retryTask == nil {
                let remainingDelay = nextRetryAt.timeIntervalSince(now)
                scheduleRetryTask(after: remainingDelay, generation: currentConnectionGeneration)
            }
            #if os(iOS)
            showConnectionErrorAlert = true
            #else
            showConnectionErrorAlert = false
            #endif
            return
        }

        let scheduledDelay = reconnectBackoff.nextDelay()
        scheduleRetryTask(after: scheduledDelay, generation: currentConnectionGeneration)

        #if os(iOS)
        showConnectionErrorAlert = true
        #else
        showConnectionErrorAlert = false
        #endif
    }

    // Add a method to update the poll interval and restart the timer
    func updatePollInterval(_ newInterval: Double) {
        pollInterval = max(1.0, newInterval)
        UserDefaults.standard.set(pollInterval, forKey: UserDefaultsKeys.pollInterval)

        if let activeConnection, connectionStatus == .connected {
            startPolling(for: activeConnection)
        }

        // Update the macOS background scheduler with new interval
        #if os(macOS)
        BackgroundActivityScheduler.updateInterval(newInterval)
        #endif
    }

    func clearSelectedHost() {
        currentConnectionGeneration = UUID()
        settingsConnectionGeneration = currentConnectionGeneration
        cancelRefreshLifecycle()
        resetReconnectState()

        host = nil
        activeConnection = nil

        torrents = []
        sessionStats = nil
        sessionConfiguration = nil
        defaultDownloadDir = ""

        lastRefreshAt = nil
        lastErrorMessage = ""
        connectionStatus = .connecting
    }

    // MARK: - Label Management

    /// Get all unique labels from current torrents, sorted alphabetically
    var availableLabels: [String] {
        let allLabels = torrents.flatMap { $0.labels }
        return Array(Set(allLabels)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Get count of torrents that have the specified label
    func torrentCount(for label: String) -> Int {
        return torrents.filter { torrent in
            torrent.labels.contains { torrentLabel in
                torrentLabel.lowercased() == label.lowercased()
            }
        }.count
    }

    func requestRefresh() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.refreshNow()
        }
    }

    func refreshNow() async {
        guard let activeConnection else { return }

        if let existing = fullRefreshTask {
            await existing.value
            return
        }

        cancelPollTask()

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.fullRefreshTask = nil }
            await self.performFullRefresh(for: activeConnection)
        }
        fullRefreshTask = task
        await task.value
    }

    private func replaceConnection(for host: Host, trigger: ConnectionAttemptReason) {
        if case .hostSelection = trigger,
           let current = self.host,
           current.serverID == host.serverID {
            return
        }

        let generation = UUID()
        currentConnectionGeneration = generation
        settingsConnectionGeneration = generation

        cancelRefreshLifecycle()
        markConnecting()
        self.host = host
        activeConnection = nil
        UserDefaults.standard.set(host.serverID, forKey: UserDefaultsKeys.selectedHost)
        clearReconnectPresentationState()
        if trigger.resetsReconnectBackoff {
            resetReconnectBackoff()
        }

        torrents = []
        sessionStats = nil
        sessionConfiguration = nil
        defaultDownloadDir = ""

        activationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.activationTask = nil }
            await self.activateConnection(for: host, generation: generation)
        }
    }

    private func activateConnection(for host: Host, generation: UUID) async {
        do {
            let connection = try await connectionFactory.connection(for: TransmissionConnectionDescriptor(host: host))
            guard isCurrentGeneration(generation, hostID: host.serverID) else {
                return
            }

            let serverName = host.name ?? host.server ?? "Server"
            let connectionState = ActiveConnection(
                hostID: host.serverID,
                serverName: serverName,
                connection: connection,
                generation: generation
            )
            activeConnection = connectionState
            await performFullRefresh(for: connectionState)
        } catch {
            handleReadError(error, generation: generation)
        }
    }

    private func performFullRefresh(for connectionState: ActiveConnection) async {
        do {
            let snapshot = try await connectionState.connection.fetchAppRefreshSnapshot()
            guard isCurrentGeneration(connectionState.generation, hostID: connectionState.hostID) else {
                return
            }

            apply(snapshot: snapshot, for: connectionState)
            startPolling(for: connectionState)
        } catch {
            handleReadError(error, generation: connectionState.generation)
        }
    }

    private func performPollingRefresh(for connectionState: ActiveConnection) async {
        do {
            let snapshot = try await connectionState.connection.fetchPollingSnapshot()
            guard isCurrentGeneration(connectionState.generation, hostID: connectionState.hostID) else {
                return
            }

            apply(snapshot: snapshot, for: connectionState)
        } catch {
            handleReadError(error, generation: connectionState.generation)
        }
    }

    private func performSessionOnlyRefresh(for connectionState: ActiveConnection) async {
        do {
            _ = try await refreshSessionConfiguration(for: connectionState)
        } catch {
            guard isCurrentGeneration(connectionState.generation, hostID: connectionState.hostID) else {
                return
            }

            let transmissionError = TransmissionErrorResolver.transmissionError(from: error)
            let presentation = TransmissionErrorPresenter.presentation(for: transmissionError)
            logger.error("Failed to refresh session configuration: \(presentation.message, privacy: .public)")
        }
    }

    private func apply(snapshot: TransmissionAppRefreshSnapshot, for connectionState: ActiveConnection) {
        apply(snapshot: snapshot.polling, for: connectionState)
        switch snapshot.sessionSettingsResult {
        case .success(let sessionSettings):
            apply(sessionSettings: sessionSettings, for: connectionState)
        case .failure(let error):
            let presentation = TransmissionErrorPresenter.presentation(for: error)
            logger.error("Failed to refresh session configuration during full refresh: \(presentation.message, privacy: .public)")
        }
    }

    private func apply(snapshot: TransmissionPollingSnapshot, for connectionState: ActiveConnection) {
        sessionStats = snapshot.sessionStats
        torrents = snapshot.torrents
        snapshotWriter.writeSessionSnapshot(
            connectionState.hostID,
            connectionState.serverName,
            snapshot.sessionStats,
            snapshot.torrents,
            true
        )
        markConnected()
    }

    private func startPolling(for connectionState: ActiveConnection) {
        cancelPollTask()

        pollTask = Task { @MainActor [weak self] in
            guard let self else { return }

            while self.isCurrentGeneration(connectionState.generation, hostID: connectionState.hostID) {
                do {
                    try await self.sleep(self.pollInterval)
                } catch {
                    return
                }

                guard self.isCurrentGeneration(connectionState.generation, hostID: connectionState.hostID) else {
                    return
                }

                await self.performPollingRefresh(for: connectionState)

                guard self.connectionStatus == .connected else {
                    return
                }
            }
        }
    }

    private func handleReadError(_ error: Error, generation: UUID) {
        guard generation == currentConnectionGeneration else {
            return
        }

        let transmissionError = TransmissionErrorResolver.transmissionError(from: error)
        if case .cancelled = transmissionError {
            return
        }

        handleConnectionError(transmissionError)
    }

    private func scheduleRetryTask(after delay: TimeInterval, generation: UUID) {
        cancelRetryTask()
        nextRetryAt = Date().addingTimeInterval(delay)

        retryTask = Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                try await self.sleep(delay)
            } catch {
                return
            }

            guard self.currentConnectionGeneration == generation else {
                return
            }

            self.clearPendingRetrySchedule()

            if self.activeConnection != nil {
                await self.refreshNow()
            } else if let host = self.host {
                self.replaceConnection(for: host, trigger: .automaticRetry)
            }
        }
    }

    private func cancelRefreshLifecycle() {
        activationTask?.cancel()
        activationTask = nil
        fullRefreshTask?.cancel()
        fullRefreshTask = nil
        sessionRefreshTask?.cancel()
        sessionRefreshTask = nil
        cancelPollTask()
        cancelRetryTask()
    }

    private func cancelPollTask() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func cancelRetryTask() {
        retryTask?.cancel()
        retryTask = nil
    }

    private func isCurrentGeneration(_ generation: UUID, hostID: String) -> Bool {
        currentConnectionGeneration == generation && host?.serverID == hostID
    }

    private func requireActiveConnection() throws -> ActiveConnection {
        guard let activeConnection else {
            throw CancellationError()
        }

        return activeConnection
    }

    private func ensureCurrent(_ connectionState: ActiveConnection) throws {
        guard isCurrentGeneration(connectionState.generation, hostID: connectionState.hostID) else {
            throw CancellationError()
        }
    }

    private func refreshSessionConfiguration(for connectionState: ActiveConnection) async throws -> TransmissionSessionResponseArguments {
        let sessionSettings = try await connectionState.connection.fetchSessionSettings()
        try ensureCurrent(connectionState)
        apply(sessionSettings: sessionSettings, for: connectionState)
        return sessionSettings
    }

    private func apply(sessionSettings: TransmissionSessionResponseArguments, for connectionState: ActiveConnection) {
        sessionConfiguration = sessionSettings
        defaultDownloadDir = sessionSettings.downloadDir

        Task {
            await persistVersion(connectionState.hostID, sessionSettings.version)
        }
    }

    private static func liveSleep(seconds: TimeInterval) async throws {
        let nanoseconds = UInt64(max(0, seconds) * 1_000_000_000)
        try await Task.sleep(nanoseconds: nanoseconds)
    }
}
