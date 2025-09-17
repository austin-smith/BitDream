import SwiftUI
import Foundation
import KeychainAccess

/// Platform-agnostic wrapper for SettingsView
/// This view simply delegates to the appropriate platform-specific implementation
struct SettingsView: View {
    @ObservedObject var store: Store
    
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
    static func resetAllSettings(store: Store) {
        let theme = ThemeManager.shared
        theme.setAccentColor(AppDefaults.accentColor)
        theme.setThemeMode(AppDefaults.themeMode)
        
        // Persist AppStorage-backed flags
        UserDefaults.standard.set(AppDefaults.showContentTypeIcons, forKey: UserDefaultsKeys.showContentTypeIcons)
        UserDefaults.standard.set(AppDefaults.startupConnectionBehavior.rawValue, forKey: UserDefaultsKeys.startupConnectionBehavior)
        
        // Poll interval via Store API
        store.updatePollInterval(AppDefaults.pollInterval)
    }
    
    var body: some View {
        #if os(iOS)
        iOSSettingsView(store: store)
        #elseif os(macOS)
        macOSSettingsView(store: store)
        #endif
    }
}

// MARK: - Shared Server Configuration Components

class SessionSettingsEditModel: ObservableObject {
    @Published var values: [String: Any] = [:]
    @Published var freeSpaceInfo: String?
    @Published var isCheckingSpace = false
    @Published var portTestResult: String?
    @Published var isTestingPort = false
    @Published var blocklistUpdateResult: String?
    @Published var isUpdatingBlocklist = false
    private var saveTimer: Timer?
    var store: Store?
    
    func setup(store: Store) {
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
        saveTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { _ in
            self.saveChanges()
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
            DispatchQueue.main.async {
                switch response {
                case .success:
                    self.values = [:]
                    store.refreshSessionConfiguration()
                case .unauthorized, .configError, .failed:
                    print("Failed to save session settings: \(response)")
                }
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

// Note: serverConfigurationContent removed - each section is now a separate tab in macOSSettingsView

// MARK: - Settings Sections

@ViewBuilder
func speedLimitsSection(config: TransmissionSessionResponseArguments, editModel: SessionSettingsEditModel) -> some View {
    GroupBox {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Speed Limits")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 4)
                
            HStack {
                Toggle("Download limit", isOn: Binding(
                    get: { editModel.getValue("speedLimitDownEnabled", fallback: config.speedLimitDownEnabled) },
                    set: { editModel.setValue("speedLimitDownEnabled", $0, original: config.speedLimitDownEnabled) }
                ))
                .platformToggleStyle()
                Spacer()
                TextField("KB/s", value: Binding(
                    get: { editModel.getValue("speedLimitDown", fallback: config.speedLimitDown) },
                    set: { editModel.setValue("speedLimitDown", $0, original: config.speedLimitDown) }
                ), format: .number)
                .frame(width: 100)
                .textFieldStyle(.roundedBorder)
                .disabled(!editModel.getValue("speedLimitDownEnabled", fallback: config.speedLimitDownEnabled))
                Text("KB/s")
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Toggle("Upload limit", isOn: Binding(
                    get: { editModel.getValue("speedLimitUpEnabled", fallback: config.speedLimitUpEnabled) },
                    set: { editModel.setValue("speedLimitUpEnabled", $0, original: config.speedLimitUpEnabled) }
                ))
                .platformToggleStyle()
                Spacer()
                TextField("KB/s", value: Binding(
                    get: { editModel.getValue("speedLimitUp", fallback: config.speedLimitUp) },
                    set: { editModel.setValue("speedLimitUp", $0, original: config.speedLimitUp) }
                ), format: .number)
                .frame(width: 100)
                .textFieldStyle(.roundedBorder)
                .disabled(!editModel.getValue("speedLimitUpEnabled", fallback: config.speedLimitUpEnabled))
                Text("KB/s")
                    .foregroundColor(.secondary)
            }
            }
            
            Divider()
                .padding(.vertical, 4)
            
            VStack(alignment: .leading, spacing: 12) {
                Label("Alternate Speed Limits", systemImage: "tortoise")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 4)
                
                Toggle("Enable alternate speeds", isOn: Binding(
                    get: { editModel.getValue("altSpeedEnabled", fallback: config.altSpeedEnabled) },
                    set: { editModel.setValue("altSpeedEnabled", $0, original: config.altSpeedEnabled) }
                ))
                .platformToggleStyle()
                
                HStack {
                    Text("Download limit")
                    Spacer()
                    TextField("KB/s", value: Binding(
                        get: { editModel.getValue("altSpeedDown", fallback: config.altSpeedDown) },
                        set: { editModel.setValue("altSpeedDown", $0, original: config.altSpeedDown) }
                    ), format: .number)
                    .frame(width: 100)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!editModel.getValue("altSpeedEnabled", fallback: config.altSpeedEnabled))
                    Text("KB/s")
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Upload limit")
                    Spacer()
                    TextField("KB/s", value: Binding(
                        get: { editModel.getValue("altSpeedUp", fallback: config.altSpeedUp) },
                        set: { editModel.setValue("altSpeedUp", $0, original: config.altSpeedUp) }
                    ), format: .number)
                    .frame(width: 100)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!editModel.getValue("altSpeedEnabled", fallback: config.altSpeedEnabled))
                    Text("KB/s")
                        .foregroundColor(.secondary)
                }
                
                Toggle("Schedule alternate speeds", isOn: Binding(
                    get: { editModel.getValue("altSpeedTimeEnabled", fallback: config.altSpeedTimeEnabled) },
                    set: { editModel.setValue("altSpeedTimeEnabled", $0, original: config.altSpeedTimeEnabled) }
                ))
                .platformToggleStyle()
                .padding(.top, 8)
                
                HStack(spacing: 12) {
                        Picker("", selection: Binding(
                            get: { editModel.getValue("altSpeedTimeDay", fallback: config.altSpeedTimeDay) },
                            set: { editModel.setValue("altSpeedTimeDay", $0, original: config.altSpeedTimeDay) }
                        )) {
                            // Transmission uses bitmask for days: Sunday=1, Monday=2, Tuesday=4, Wednesday=8, Thursday=16, Friday=32, Saturday=64
                            Text("Every Day").tag(127)  // All days: 1+2+4+8+16+32+64
                            Text("Weekdays").tag(62)   // Mon-Fri: 2+4+8+16+32
                            Text("Weekends").tag(65)   // Sat+Sun: 64+1
                            Divider()
                            Text("Sunday").tag(1)
                            Text("Monday").tag(2)
                            Text("Tuesday").tag(4)
                            Text("Wednesday").tag(8)
                            Text("Thursday").tag(16)
                            Text("Friday").tag(32)
                            Text("Saturday").tag(64)
                        }
                        .pickerStyle(.menu)
                        .disabled(!editModel.getValue("altSpeedTimeEnabled", fallback: config.altSpeedTimeEnabled))
                        
                        Text("from")
                            .foregroundColor(.secondary)
                        
                        DatePicker("", selection: Binding(
                            get: {
                                let minutes = editModel.getValue("altSpeedTimeBegin", fallback: config.altSpeedTimeBegin)
                                let calendar = Calendar.current
                                return calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
                            },
                            set: { date in
                                let calendar = Calendar.current
                                let components = calendar.dateComponents([.hour, .minute], from: date)
                                let minutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
                                editModel.setValue("altSpeedTimeBegin", minutes, original: config.altSpeedTimeBegin)
                            }
                        ), displayedComponents: .hourAndMinute)
                        .datePickerStyle(.compact)
                        .labelsHidden()
                        .disabled(!editModel.getValue("altSpeedTimeEnabled", fallback: config.altSpeedTimeEnabled))
                        
                        Text("to")
                            .foregroundColor(.secondary)
                        
                        DatePicker("", selection: Binding(
                            get: {
                                let minutes = editModel.getValue("altSpeedTimeEnd", fallback: config.altSpeedTimeEnd)
                                let calendar = Calendar.current
                                return calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
                            },
                            set: { date in
                                let calendar = Calendar.current
                                let components = calendar.dateComponents([.hour, .minute], from: date)
                                let minutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
                                editModel.setValue("altSpeedTimeEnd", minutes, original: config.altSpeedTimeEnd)
                            }
                        ), displayedComponents: .hourAndMinute)
                        .datePickerStyle(.compact)
                        .labelsHidden()
                        .disabled(!editModel.getValue("altSpeedTimeEnabled", fallback: config.altSpeedTimeEnabled))
                        
                        Spacer()
                    }
                    .disabled(!editModel.getValue("altSpeedTimeEnabled", fallback: config.altSpeedTimeEnabled))
            }
        }
        .padding(16)
    }
}

@ViewBuilder
func networkSection(config: TransmissionSessionResponseArguments, editModel: SessionSettingsEditModel) -> some View {
    GroupBox {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Connection")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 4)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Peer listening port")
                        Spacer()
                        TextField("Port", value: Binding(
                            get: { editModel.getValue("peerPort", fallback: config.peerPort) },
                            set: { editModel.setValue("peerPort", $0, original: config.peerPort) }
                        ), format: .number.grouping(.never))
                        .frame(width: 60)
                        .textFieldStyle(.roundedBorder)
                        
                        Button("Check Port") {
                            checkPort(editModel: editModel, ipProtocol: nil)
                        }
                        .disabled(editModel.isTestingPort)
                    }
                    Text("Port number for incoming peer connections")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if editModel.isTestingPort {
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.3)
                                .frame(width: 8, height: 8)
                            Text("Testing port...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else if let portTestResult = editModel.portTestResult {
                        Text(portTestResult)
                            .font(.caption)
                            .foregroundColor(portTestResult.contains("open") ? .green : .orange)
                    }
                }
                
                Toggle("Randomize port on launch", isOn: Binding(
                    get: { editModel.getValue("peerPortRandomOnStart", fallback: config.peerPortRandomOnStart) },
                    set: { editModel.setValue("peerPortRandomOnStart", $0, original: config.peerPortRandomOnStart) }
                ))
                .platformToggleStyle()
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Encryption")
                        Spacer()
                        Picker("", selection: Binding(
                            get: { editModel.getValue("encryption", fallback: config.encryption) },
                            set: { editModel.setValue("encryption", $0, original: config.encryption) }
                        )) {
                            Text("Required").tag("required")
                            Text("Preferred").tag("preferred") 
                            Text("Tolerated").tag("tolerated")
                        }
                        .pickerStyle(.menu)
                        .frame(width: 100)
                    }
                    Text("How strictly to enforce encrypted peer connections")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Divider()
                .padding(.vertical, 4)
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Peer Exchange")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 4)
                
                Toggle("Enable port forwarding", isOn: Binding(
                    get: { editModel.getValue("portForwardingEnabled", fallback: config.portForwardingEnabled) },
                    set: { editModel.setValue("portForwardingEnabled", $0, original: config.portForwardingEnabled) }
                ))
                .platformToggleStyle()
                
                Toggle("Enable DHT (Distributed Hash Table)", isOn: Binding(
                    get: { editModel.getValue("dhtEnabled", fallback: config.dhtEnabled) },
                    set: { editModel.setValue("dhtEnabled", $0, original: config.dhtEnabled) }
                ))
                .platformToggleStyle()
                
                Toggle("Enable PEX (Peer Exchange)", isOn: Binding(
                    get: { editModel.getValue("pexEnabled", fallback: config.pexEnabled) },
                    set: { editModel.setValue("pexEnabled", $0, original: config.pexEnabled) }
                ))
                .platformToggleStyle()
                
                Toggle("Enable LPD (Local Peer Discovery)", isOn: Binding(
                    get: { editModel.getValue("lpdEnabled", fallback: config.lpdEnabled) },
                    set: { editModel.setValue("lpdEnabled", $0, original: config.lpdEnabled) }
                ))
                .platformToggleStyle()
                
                Toggle("Enable µTP (Micro Transport Protocol)", isOn: Binding(
                    get: { editModel.getValue("utpEnabled", fallback: config.utpEnabled) },
                    set: { editModel.setValue("utpEnabled", $0, original: config.utpEnabled) }
                ))
                .platformToggleStyle()
            }
            
            Divider()
                .padding(.vertical, 4)
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Peer Limits")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 4)
                
                HStack {
                    Text("Maximum global peers")
                    Spacer()
                    TextField("", value: Binding(
                        get: { editModel.getValue("peerLimitGlobal", fallback: config.peerLimitGlobal) },
                        set: { editModel.setValue("peerLimitGlobal", $0, original: config.peerLimitGlobal) }
                    ), format: .number.grouping(.never))
                    .frame(width: 60)
                    .textFieldStyle(.roundedBorder)
                }
                
                HStack {
                    Text("Maximum per torrent peers")
                    Spacer()
                    TextField("", value: Binding(
                        get: { editModel.getValue("peerLimitPerTorrent", fallback: config.peerLimitPerTorrent) },
                        set: { editModel.setValue("peerLimitPerTorrent", $0, original: config.peerLimitPerTorrent) }
                    ), format: .number.grouping(.never))
                    .frame(width: 60)
                    .textFieldStyle(.roundedBorder)
                }
            }
            
            Divider()
                .padding(.vertical, 4)
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Blocklist")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 4)
                
                Toggle("Enable blocklist", isOn: Binding(
                    get: { editModel.getValue("blocklistEnabled", fallback: config.blocklistEnabled) },
                    set: { editModel.setValue("blocklistEnabled", $0, original: config.blocklistEnabled) }
                ))
                .platformToggleStyle()
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Blocklist URL")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("URL", text: Binding(
                        get: { editModel.getValue("blocklistUrl", fallback: config.blocklistUrl) },
                        set: { editModel.setValue("blocklistUrl", $0, original: config.blocklistUrl) }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .disabled(!editModel.getValue("blocklistEnabled", fallback: config.blocklistEnabled))
                }
                
                HStack {
                    Text("Blocklist rules active")
                    Spacer()
                    if editModel.isUpdatingBlocklist {
                        ProgressView()
                            .scaleEffect(0.3)
                            .frame(width: 8, height: 8)
                        Text("Updating...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("\(config.blocklistSize)")
                            .foregroundColor(.secondary)
                            .font(.system(.body, design: .monospaced))
                    }
                    Button("Update") {
                        updateBlocklist(editModel: editModel)
                    }
                    .disabled(editModel.isUpdatingBlocklist || !editModel.getValue("blocklistEnabled", fallback: config.blocklistEnabled))
                }
                
                if let blocklistUpdateResult = editModel.blocklistUpdateResult {
                    Text(blocklistUpdateResult)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
            }
            
            Divider()
                .padding(.vertical, 4)
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Default Public Trackers")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 4)
                
                Text("Trackers added to all public torrents")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                TextEditor(text: Binding(
                    get: { editModel.getValue("defaultTrackers", fallback: config.defaultTrackers) },
                    set: { editModel.setValue("defaultTrackers", $0, original: config.defaultTrackers) }
                ))
                .font(.system(.caption, design: .monospaced))
                .frame(minHeight: 80)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
                
                Text("To add a backup URL, add it on the next line after a primary URL.\nTo add a new primary URL, add it after a blank line.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
    }
}

@ViewBuilder
func queueManagementSection(config: TransmissionSessionResponseArguments, editModel: SessionSettingsEditModel) -> some View {
    GroupBox(label: Text("Queue Management").font(.headline)) {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Toggle("Download queue size", isOn: Binding(
                    get: { editModel.getValue("downloadQueueEnabled", fallback: config.downloadQueueEnabled) },
                    set: { editModel.setValue("downloadQueueEnabled", $0, original: config.downloadQueueEnabled) }
                ))
                .platformToggleStyle()
                Spacer()
                TextField("", value: Binding(
                    get: { editModel.getValue("downloadQueueSize", fallback: config.downloadQueueSize) },
                    set: { editModel.setValue("downloadQueueSize", $0, original: config.downloadQueueSize) }
                ), format: .number)
                .frame(width: 60)
                .textFieldStyle(.roundedBorder)
                .disabled(!editModel.getValue("downloadQueueEnabled", fallback: config.downloadQueueEnabled))
                Text("active downloads")
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Toggle("Seed queue size", isOn: Binding(
                    get: { editModel.getValue("seedQueueEnabled", fallback: config.seedQueueEnabled) },
                    set: { editModel.setValue("seedQueueEnabled", $0, original: config.seedQueueEnabled) }
                ))
                .platformToggleStyle()
                Spacer()
                TextField("", value: Binding(
                    get: { editModel.getValue("seedQueueSize", fallback: config.seedQueueSize) },
                    set: { editModel.setValue("seedQueueSize", $0, original: config.seedQueueSize) }
                ), format: .number)
                .frame(width: 60)
                .textFieldStyle(.roundedBorder)
                .disabled(!editModel.getValue("seedQueueEnabled", fallback: config.seedQueueEnabled))
                Text("active seeds")
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Toggle("Consider idle torrents as stalled after", isOn: Binding(
                    get: { editModel.getValue("queueStalledEnabled", fallback: config.queueStalledEnabled) },
                    set: { editModel.setValue("queueStalledEnabled", $0, original: config.queueStalledEnabled) }
                ))
                .platformToggleStyle()
                Spacer()
                TextField("", value: Binding(
                    get: { editModel.getValue("queueStalledMinutes", fallback: config.queueStalledMinutes) },
                    set: { editModel.setValue("queueStalledMinutes", $0, original: config.queueStalledMinutes) }
                ), format: .number)
                .frame(width: 50)
                .textFieldStyle(.roundedBorder)
                .disabled(!editModel.getValue("queueStalledEnabled", fallback: config.queueStalledEnabled))
                Text("minutes")
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
    }
}

@ViewBuilder
func fileManagementSection(config: TransmissionSessionResponseArguments, editModel: SessionSettingsEditModel) -> some View {
    GroupBox(label: Text("File Management").font(.headline)) {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Download Directory")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                HStack {
                    TextField("Path", text: Binding(
                        get: { editModel.getValue("downloadDir", fallback: config.downloadDir) },
                        set: { editModel.setValue("downloadDir", $0, original: config.downloadDir) }
                    ))
                    .textFieldStyle(.roundedBorder)
                    
                    Button("Check Space") {
                        checkDirectoryFreeSpace(
                            path: editModel.getValue("downloadDir", fallback: config.downloadDir),
                            editModel: editModel
                        )
                    }
                }
                if let freeSpaceInfo = editModel.freeSpaceInfo {
                    HStack(spacing: 6) {
                        Text(freeSpaceInfo)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if editModel.isCheckingSpace {
                            ProgressView()
                                .scaleEffect(0.3)
                                .frame(width: 8, height: 8)
                        }
                    }
                }
            }
            
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Use separate incomplete directory", isOn: Binding(
                    get: { editModel.getValue("incompleteDirEnabled", fallback: config.incompleteDirEnabled) },
                    set: { editModel.setValue("incompleteDirEnabled", $0, original: config.incompleteDirEnabled) }
                ))
                .platformToggleStyle()
                
                TextField("Incomplete directory path", text: Binding(
                    get: { editModel.getValue("incompleteDir", fallback: config.incompleteDir) },
                    set: { editModel.setValue("incompleteDir", $0, original: config.incompleteDir) }
                ))
                .textFieldStyle(.roundedBorder)
                .disabled(!editModel.getValue("incompleteDirEnabled", fallback: config.incompleteDirEnabled))
                .padding(.leading, 20)
            }
            
            Toggle("Start transfers when added", isOn: Binding(
                get: { editModel.getValue("startAddedTorrents", fallback: config.startAddedTorrents) },
                set: { editModel.setValue("startAddedTorrents", $0, original: config.startAddedTorrents) }
            ))
            .platformToggleStyle()
            
            Toggle(isOn: Binding(
                get: { editModel.getValue("trashOriginalTorrentFiles", fallback: config.trashOriginalTorrentFiles) },
                set: { editModel.setValue("trashOriginalTorrentFiles", $0, original: config.trashOriginalTorrentFiles) }
            )) {
                HStack(spacing: 0) {
                    Text("Delete original ")
                    Text(".torrent")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.15))
                        .cornerRadius(2)
                    Text(" files")
                }
            }
            .platformToggleStyle()
            
            Toggle(isOn: Binding(
                get: { editModel.getValue("renamePartialFiles", fallback: config.renamePartialFiles) },
                set: { editModel.setValue("renamePartialFiles", $0, original: config.renamePartialFiles) }
            )) {
                HStack(spacing: 0) {
                    Text("Append ")
                    Text(".part")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.15))
                        .cornerRadius(2)
                    Text(" to incomplete files")
                }
            }
            .platformToggleStyle()
        }
        .padding(16)
    }
}

@ViewBuilder
func seedingSection(config: TransmissionSessionResponseArguments, editModel: SessionSettingsEditModel) -> some View {
    GroupBox(label: Text("Seeding").font(.headline)) {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Toggle("Stop seeding at ratio", isOn: Binding(
                    get: { editModel.getValue("seedRatioLimited", fallback: config.seedRatioLimited) },
                    set: { editModel.setValue("seedRatioLimited", $0, original: config.seedRatioLimited) }
                ))
                .platformToggleStyle()
                Spacer()
                TextField("", value: Binding(
                    get: { editModel.getValue("seedRatioLimit", fallback: config.seedRatioLimit) },
                    set: { editModel.setValue("seedRatioLimit", $0, original: config.seedRatioLimit) }
                ), format: .number.precision(.fractionLength(2)))
                .frame(width: 60)
                .textFieldStyle(.roundedBorder)
                .disabled(!editModel.getValue("seedRatioLimited", fallback: config.seedRatioLimited))
            }
            
            HStack {
                Toggle("Stop seeding when inactive for", isOn: Binding(
                    get: { editModel.getValue("idleSeedingLimitEnabled", fallback: config.idleSeedingLimitEnabled) },
                    set: { editModel.setValue("idleSeedingLimitEnabled", $0, original: config.idleSeedingLimitEnabled) }
                ))
                .platformToggleStyle()
                Spacer()
                TextField("", value: Binding(
                    get: { editModel.getValue("idleSeedingLimit", fallback: config.idleSeedingLimit) },
                    set: { editModel.setValue("idleSeedingLimit", $0, original: config.idleSeedingLimit) }
                ), format: .number)
                .frame(width: 50)
                .textFieldStyle(.roundedBorder)
                .disabled(!editModel.getValue("idleSeedingLimitEnabled", fallback: config.idleSeedingLimitEnabled))
                Text("minutes")
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
    }
}

// Platform-specific toggle styling
extension View {
    func platformToggleStyle() -> some View {
        #if os(macOS)
        self.toggleStyle(.checkbox)
        #elseif os(iOS)
        self.toggleStyle(.switch)
        #endif
    }
}

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
        DispatchQueue.main.async {
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
}

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
        DispatchQueue.main.async {
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
}

func updateBlocklist(editModel: SessionSettingsEditModel) {
    guard let store = editModel.store,
          let serverInfo = store.currentServerInfo else { return }
    
    editModel.isUpdatingBlocklist = true
    editModel.blocklistUpdateResult = nil
    
    updateBlocklist(
        config: serverInfo.config,
        auth: serverInfo.auth
    ) { result in
        DispatchQueue.main.async {
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
}

#Preview {
    SettingsView(store: Store())
} 