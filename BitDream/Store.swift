import SwiftUI
import Foundation
import KeychainAccess

#if os(macOS)
enum AddTorrentInitialMode {
    case magnet
    case file
}
#endif

struct Server {
    var config: TransmissionConfig
    var auth: TransmissionAuth
}

class Store: NSObject, ObservableObject {
    @Published var torrents: [Torrent] = []
    @Published var sessionStats: SessionStats?
    @Published var setup: Bool = false
    @Published var server: Server?
    @Published var host: Host?

    @Published var defaultDownloadDir: String = ""

    @Published var isShowingAddAlert: Bool = false
    // When presenting Add Torrent, optional prefill for the magnet link input (macOS only used)
    @Published var addTorrentPrefill: String? = nil
    // Queue of pending magnet links to present sequentially (macOS)
    @Published var pendingMagnetQueue: [String] = []
    // Visual indicator state for queued magnets
    @Published var magnetQueueDisplayIndex: Int = 0
    @Published var magnetQueueTotal: Int = 0
    @Published var isShowingServerAlert: Bool = false
    @Published var editServers: Bool = false {
        didSet {
            // Set the editing flag when server settings are being edited
            isEditingServerSettings = editServers
        }
    }
    @Published var showSettings: Bool = false

    @Published var isError: Bool = false
    @Published var debugBrief: String = ""
    @Published var debugMessage: String = ""

    @Published var connectionError: Bool = false
    @Published var connectionErrorMessage: String = ""

    @Published var showConnectionErrorAlert: Bool = false
    @Published var isEditingServerSettings: Bool = false  // Flag to pause reconnection attempts

    @Published var sessionConfiguration: TransmissionSessionResponseArguments?

    @Published var pollInterval: Double = AppDefaults.pollInterval // Default poll interval in seconds
    @Published var shouldActivateSearch: Bool = false
    @Published var shouldToggleInspector: Bool = false
    @Published var isInspectorVisible: Bool = UserDefaults.standard.inspectorVisibility

#if os(macOS)
    // Controls how the Add Torrent flow should start when invoked from menu
    @Published var addTorrentInitialMode: AddTorrentInitialMode? = nil
    // Triggers a global file importer from top-level window
    @Published var presentGlobalTorrentFileImporter: Bool = false
    // Global native alert state for macOS
    @Published var showGlobalAlert: Bool = false
    @Published var globalAlertTitle: String = "Error"
    @Published var globalAlertMessage: String = ""
    // Global rename dialog state for menu command
    @Published var showGlobalRenameDialog: Bool = false
    @Published var globalRenameInput: String = ""
    @Published var globalRenameTargetId: Int? = nil
#endif

    // Confirmation dialog state for menu remove command
    @Published var showingMenuRemoveConfirmation = false

    var timer: Timer = Timer()

    override init() {
        super.init()
        // Load persisted poll interval if available
        if let saved = UserDefaults.standard.object(forKey: UserDefaultsKeys.pollInterval) as? Double {
            self.pollInterval = max(1.0, saved)
        } else {
            self.pollInterval = AppDefaults.pollInterval
        }
    }

    // MARK: - Magnet Queue Helpers (macOS)
    #if os(macOS)
    func enqueueMagnet(_ magnet: String) {
        DispatchQueue.main.async {
            let wasEmpty = self.pendingMagnetQueue.isEmpty
            self.pendingMagnetQueue.append(magnet)
            if wasEmpty {
                // New batch
                self.magnetQueueTotal = self.pendingMagnetQueue.count
                self.magnetQueueDisplayIndex = 1
                if !self.isShowingAddAlert {
                    self.presentNextMagnetIfAvailable()
                }
            } else {
                // Increase total while batch is in progress
                self.magnetQueueTotal += 1
            }
        }
    }

    func presentNextMagnetIfAvailable() {
        guard let next = pendingMagnetQueue.first else { return }
        addTorrentPrefill = next
        addTorrentInitialMode = .magnet
        isShowingAddAlert = true
    }

    func advanceMagnetQueue() {
        DispatchQueue.main.async {
            if !self.pendingMagnetQueue.isEmpty {
                self.pendingMagnetQueue.removeFirst()
            }
            if !self.pendingMagnetQueue.isEmpty {
                // Move to next item in the same batch
                self.magnetQueueDisplayIndex = min(self.magnetQueueDisplayIndex + 1, self.magnetQueueTotal)
                self.presentNextMagnetIfAvailable()
            } else {
                // Batch complete
                self.magnetQueueDisplayIndex = 0
                self.magnetQueueTotal = 0
            }
        }
    }
    #endif

    public func setHost(host: Host) {
        // Avoid redundant resets if host is unchanged (prevents list flash)
        if let current = self.host, current.objectID == host.objectID {
            return
        }
        var config = TransmissionConfig()
        config.host = host.server
        config.port = Int(host.port)
        config.scheme = host.isSSL ? "https" : "http"

        let auth = TransmissionAuth(username: host.username!, password: readPassword(name: host.name!))
        self.server = Server(config: config, auth: auth)
        self.host = host

        // Clear all local state so UI/actions can't use stale data from the previous host
        self.torrents = []
        self.sessionStats = nil
        self.sessionConfiguration = nil
        self.defaultDownloadDir = ""

        // Kick off refresh loop immediately; refreshTransmissionData handles torrents,
        // session stats, and session info (including defaultDownloadDir) with retry logic
        timer.invalidate()
        refreshTransmissionData(store: self)
        startTimer()
    }

    func readPassword(name: String) -> String {
        let keychain = Keychain(service: "crapshack.BitDream")
        if let password = keychain[name] {
            return password
        }
        else {
            return "Whoopsie!"
        }
    }

    func startTimer() {
        self.timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true, block: { _ in
            // Skip updates if user is actively editing server settings
            if self.isEditingServerSettings {
                return
            }

            DispatchQueue.main.async {
                updateList(store: self, update: { vals in
                    DispatchQueue.main.async {
                        // Setting @Published properties automatically triggers objectWillChange
                        self.torrents = vals
                    }
                })
                updateSessionStats(store: self, update: { vals in
                    DispatchQueue.main.async {
                        // Setting @Published properties automatically triggers objectWillChange
                        self.sessionStats = vals
                    }
                })
            }
        })
    }

    // Method to reconnect to the server
    func reconnect() {
        // Before attempting reconnection, make sure the alert is dismissed
        self.showConnectionErrorAlert = false

        if let host = self.host {
            // Try to reconnect to the current host
            self.setHost(host: host)
        }
    }

    // Computed property to provide current server info for session-set calls
    var currentServerInfo: (config: TransmissionConfig, auth: TransmissionAuth)? {
        guard let server = self.server else { return nil }
        return (config: server.config, auth: server.auth)
    }

    // Method to refresh session configuration after settings changes
    func refreshSessionConfiguration() {
        guard let serverInfo = currentServerInfo else { return }

        getSession(config: serverInfo.config, auth: serverInfo.auth, onResponse: { sessionInfo in
            DispatchQueue.main.async {
                self.sessionConfiguration = sessionInfo
                self.defaultDownloadDir = sessionInfo.downloadDir
            }
        }, onError: { error in
            print("Failed to refresh session info: \(error)")
        })
    }

    // Method to handle connection errors
    func handleConnectionError(message: String) {
        DispatchQueue.main.async {
            self.connectionError = true
            self.connectionErrorMessage = message
            self.showConnectionErrorAlert = true
            self.timer.invalidate()
        }
    }

    // Add a method to update the poll interval and restart the timer
    func updatePollInterval(_ newInterval: Double) {
        // Ensure the interval is at least 1 second
        pollInterval = max(1.0, newInterval)
        // Persist the new interval
        UserDefaults.standard.set(pollInterval, forKey: UserDefaultsKeys.pollInterval)

        // Stop the current timer
        timer.invalidate()

        // Start a new timer with the updated interval
        startTimer()

        // Update the macOS background scheduler with new interval
        #if os(macOS)
        BackgroundActivityScheduler.updateInterval(newInterval)
        #endif
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
}
