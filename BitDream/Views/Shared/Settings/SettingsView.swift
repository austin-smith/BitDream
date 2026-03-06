import SwiftUI
import Foundation
import OSLog

/// Platform-agnostic wrapper for SettingsView
/// This view simply delegates to the appropriate platform-specific implementation
struct SettingsView: View {
    @ObservedObject var store: AppStore

    // Shared poll interval options
    static let pollIntervalOptions: [Double] = [1.0, 2.0, 5.0, 10.0, 30.0, 60.0]

    // Helper to format the interval options
    static func formatInterval(_ interval: Double) -> String {
        if interval == 1.0 {
            return "1 second"
        } else if interval < 60.0 {
            return "\(Int(interval)) seconds"
        } else {
            return "\(Int(interval / 60)) minute\(interval == 60.0 ? "" : "s")"
        }
    }

    // Shared reset for both platforms
    static func resetAllSettings(store: AppStore, afterReset: () -> Void = {}) {
        let theme = ThemeManager.shared
        theme.setAccentColor(AppDefaults.accentColor)
        theme.setThemeMode(AppDefaults.themeMode)

        // Persist AppStorage-backed flags
        UserDefaults.standard.set(AppDefaults.showContentTypeIcons, forKey: UserDefaultsKeys.showContentTypeIcons)
        UserDefaults.standard.set(AppDefaults.menuBarTransferWidgetEnabled, forKey: UserDefaultsKeys.menuBarTransferWidgetEnabled)
        UserDefaults.standard.set(AppDefaults.menuBarSortMode.rawValue, forKey: UserDefaultsKeys.menuBarSortMode)
        UserDefaults.standard.set(AppDefaults.startupConnectionBehavior.rawValue, forKey: UserDefaultsKeys.startupConnectionBehavior)

        // Poll interval via AppStore API
        store.updatePollInterval(AppDefaults.pollInterval)
        afterReset()
    }

    var body: some View {
        PlatformSettingsView(store: store)
    }
}

// MARK: - Shared Server Configuration Components

@MainActor
class SessionSettingsEditModel: ObservableObject {
    @Published var values: [String: Any] = [:]
    @Published var freeSpaceInfo: String?
    @Published var isCheckingSpace = false
    @Published var portTestResult: String?
    @Published var isTestingPort = false
    @Published var blocklistUpdateResult: String?
    @Published var isUpdatingBlocklist = false
    private var saveTimer: Timer?
    var store: AppStore?
    private let logger = Logger(subsystem: AppIdentity.bundleIdentifier, category: "network")

    func setup(store: AppStore) {
        self.store = store
        // Clear info when switching servers
        freeSpaceInfo = nil
        isCheckingSpace = false
        portTestResult = nil
        isTestingPort = false
        blocklistUpdateResult = nil
        isUpdatingBlocklist = false
    }

    func setValue<T>(_ key: String, _ value: T, original: T) where T: Equatable {
        if value != original {
            values[key] = value
            scheduleAutoSave()
        } else {
            values.removeValue(forKey: key)
            if values.isEmpty {
                saveTimer?.invalidate()
            }
        }
    }

    func getValue<T>(_ key: String, fallback: T) -> T {
        return values[key] as? T ?? fallback
    }

    private func scheduleAutoSave() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.saveChanges()
            }
        }
    }

    private func saveChanges() {
        guard !values.isEmpty,
              let store = store,
              let serverInfo = store.currentServerInfo else { return }

        let args = buildSessionSetArgs()

        setSession(
            args: args,
            config: serverInfo.config,
            auth: serverInfo.auth
        ) { response in
            if response == .success {
                self.values = [:]
                store.refreshSessionConfiguration()
            } else {
                self.logger.error("Failed to save session settings: \(String(describing: response), privacy: .public)")
            }
        }
    }

    private func buildSessionSetArgs() -> TransmissionSessionSetRequestArgs {
        var args = TransmissionSessionSetRequestArgs()

        // Speed & Bandwidth
        args.speedLimitDown = values["speedLimitDown"] as? Int64
        args.speedLimitDownEnabled = values["speedLimitDownEnabled"] as? Bool
        args.speedLimitUp = values["speedLimitUp"] as? Int64
        args.speedLimitUpEnabled = values["speedLimitUpEnabled"] as? Bool
        args.altSpeedDown = values["altSpeedDown"] as? Int64
        args.altSpeedUp = values["altSpeedUp"] as? Int64
        args.altSpeedEnabled = values["altSpeedEnabled"] as? Bool
        args.altSpeedTimeBegin = values["altSpeedTimeBegin"] as? Int
        args.altSpeedTimeEnd = values["altSpeedTimeEnd"] as? Int
        args.altSpeedTimeEnabled = values["altSpeedTimeEnabled"] as? Bool
        args.altSpeedTimeDay = values["altSpeedTimeDay"] as? Int

        // File Management
        args.downloadDir = values["downloadDir"] as? String
        args.incompleteDir = values["incompleteDir"] as? String
        args.incompleteDirEnabled = values["incompleteDirEnabled"] as? Bool
        args.startAddedTorrents = values["startAddedTorrents"] as? Bool
        args.trashOriginalTorrentFiles = values["trashOriginalTorrentFiles"] as? Bool
        args.renamePartialFiles = values["renamePartialFiles"] as? Bool

        // Queue Management
        args.downloadQueueEnabled = values["downloadQueueEnabled"] as? Bool
        args.downloadQueueSize = values["downloadQueueSize"] as? Int
        args.seedQueueEnabled = values["seedQueueEnabled"] as? Bool
        args.seedQueueSize = values["seedQueueSize"] as? Int
        args.seedRatioLimited = values["seedRatioLimited"] as? Bool
        args.seedRatioLimit = values["seedRatioLimit"] as? Double
        args.idleSeedingLimit = values["idleSeedingLimit"] as? Int
        args.idleSeedingLimitEnabled = values["idleSeedingLimitEnabled"] as? Bool
        args.queueStalledEnabled = values["queueStalledEnabled"] as? Bool
        args.queueStalledMinutes = values["queueStalledMinutes"] as? Int

        // Network Settings
        args.peerPort = values["peerPort"] as? Int
        args.peerPortRandomOnStart = values["peerPortRandomOnStart"] as? Bool
        args.portForwardingEnabled = values["portForwardingEnabled"] as? Bool
        args.dhtEnabled = values["dhtEnabled"] as? Bool
        args.pexEnabled = values["pexEnabled"] as? Bool
        args.lpdEnabled = values["lpdEnabled"] as? Bool
        args.encryption = values["encryption"] as? String
        args.utpEnabled = values["utpEnabled"] as? Bool
        args.peerLimitGlobal = values["peerLimitGlobal"] as? Int
        args.peerLimitPerTorrent = values["peerLimitPerTorrent"] as? Int

        // Blocklist
        args.blocklistEnabled = values["blocklistEnabled"] as? Bool
        args.blocklistUrl = values["blocklistUrl"] as? String

        // Default Trackers
        args.defaultTrackers = values["defaultTrackers"] as? String

        // Cache
        args.cacheSizeMb = values["cacheSizeMb"] as? Int

        // Scripts
        args.scriptTorrentDoneEnabled = values["scriptTorrentDoneEnabled"] as? Bool
        args.scriptTorrentDoneFilename = values["scriptTorrentDoneFilename"] as? String
        args.scriptTorrentAddedEnabled = values["scriptTorrentAddedEnabled"] as? Bool
        args.scriptTorrentAddedFilename = values["scriptTorrentAddedFilename"] as? String
        args.scriptTorrentDoneSeedingEnabled = values["scriptTorrentDoneSeedingEnabled"] as? Bool
        args.scriptTorrentDoneSeedingFilename = values["scriptTorrentDoneSeedingFilename"] as? String

        return args
    }
}

// Intentionally empty: all platform-specific View modifiers are defined per-platform

// Shared extension for creating a Binding<StartupConnectionBehavior> from a raw String binding
extension Binding where Value == StartupConnectionBehavior {
    static func fromRawValue(rawValue: Binding<String>, defaultValue: StartupConnectionBehavior) -> Binding<StartupConnectionBehavior> {
        Binding<StartupConnectionBehavior>(
            get: { StartupConnectionBehavior(rawValue: rawValue.wrappedValue) ?? defaultValue },
            set: { rawValue.wrappedValue = $0.rawValue }
        )
    }
}

// MARK: - Helper Functions

@MainActor
func checkDirectoryFreeSpace(path: String, editModel: SessionSettingsEditModel) {
    guard let store = editModel.store,
          let serverInfo = store.currentServerInfo else { return }

    editModel.isCheckingSpace = true

    // Only show "Checking..." if we don't have previous results
    if editModel.freeSpaceInfo == nil {
        editModel.freeSpaceInfo = "Checking..."
    }

    checkFreeSpace(
        path: path,
        config: serverInfo.config,
        auth: serverInfo.auth
    ) { result in
        editModel.isCheckingSpace = false
        switch result {
        case .success(let response):
            let formatter = ByteCountFormatter()
            formatter.countStyle = .binary
            let freeSpace = formatter.string(fromByteCount: response.sizeBytes)
            let totalSpace = formatter.string(fromByteCount: response.totalSize)
            let percentUsed = 100.0 - (Double(response.sizeBytes) / Double(response.totalSize) * 100.0)
            editModel.freeSpaceInfo = "Free: \(freeSpace) of \(totalSpace) (\(String(format: "%.1f", percentUsed))% used)"
        case .failure(let error):
            editModel.freeSpaceInfo = "Error: \(error.localizedDescription)"
        }
    }
}

@MainActor
func checkPort(editModel: SessionSettingsEditModel, ipProtocol: String? = nil) {
    guard let store = editModel.store,
          let serverInfo = store.currentServerInfo else { return }

    editModel.isTestingPort = true
    editModel.portTestResult = nil

    testPort(
        ipProtocol: ipProtocol,
        config: serverInfo.config,
        auth: serverInfo.auth
    ) { result in
        editModel.isTestingPort = false
        switch result {
        case .success(let response):
            if response.portIsOpen == true {
                let protocolName = response.ipProtocol?.uppercased() ?? "IP"
                editModel.portTestResult = "Port is open (\(protocolName))"
            } else if response.portIsOpen == false {
                let protocolName = response.ipProtocol?.uppercased() ?? "IP"
                editModel.portTestResult = "Port is closed (\(protocolName))"
            } else {
                editModel.portTestResult = "Port check site is down"
            }
        case .failure(let error):
            editModel.portTestResult = "Failed to test port: \(error.localizedDescription)"
        }
    }
}

@MainActor
func updateBlocklist(editModel: SessionSettingsEditModel) {
    guard let store = editModel.store,
          let serverInfo = store.currentServerInfo else { return }

    editModel.isUpdatingBlocklist = true
    editModel.blocklistUpdateResult = nil

    updateBlocklist(
        config: serverInfo.config,
        auth: serverInfo.auth
    ) { result in
        editModel.isUpdatingBlocklist = false
        switch result {
        case .success(let response):
            editModel.blocklistUpdateResult = "Updated blocklist: \(response.blocklistSize) rules"
            // Refresh session configuration to get the updated blocklist size
            store.refreshSessionConfiguration()
        case .failure(let error):
            editModel.blocklistUpdateResult = "Failed to update blocklist: \(error.localizedDescription)"
        }
    }
}

#Preview {
    SettingsView(store: AppStore())
}
