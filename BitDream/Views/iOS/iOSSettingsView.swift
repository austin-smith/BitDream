import SwiftUI
import Foundation

#if os(iOS)
typealias PlatformSettingsView = iOSSettingsView

struct iOSSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showingThemeSettings = false
    @ObservedObject var store: Store
    @ObservedObject private var themeManager = ThemeManager.shared
    @AppStorage(UserDefaultsKeys.showContentTypeIcons) private var showContentTypeIcons: Bool = AppDefaults.showContentTypeIcons
    @AppStorage(UserDefaultsKeys.startupConnectionBehavior) private var startupBehaviorRaw: String = AppDefaults.startupConnectionBehavior.rawValue
    
    var body: some View {
        // iOS version with standard styling
        NavigationView {
            Form {
                Section(header: Text("Appearance")) {
                    Picker("Theme", selection: $themeManager.themeMode) {
                        ForEach(ThemeMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    
                    NavigationLink(destination: AccentColorPicker(selection: $themeManager.currentAccentColorOption)) {
                        HStack {
                            Text("Accent Color")
                            Spacer()
                            Circle()
                                .fill(themeManager.currentAccentColorOption.color)
                                .frame(width: 16, height: 16)
                            Text(themeManager.currentAccentColorOption.name)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Toggle("Show file type icons", isOn: $showContentTypeIcons)
                }
                
                Section(header: Text("Startup")) {
                    Picker("Startup connection", selection: .fromRawValue(rawValue: $startupBehaviorRaw, defaultValue: AppDefaults.startupConnectionBehavior)) {
                        Text("Last used server").tag(StartupConnectionBehavior.lastUsed)
                        Text("Default server").tag(StartupConnectionBehavior.defaultServer)
                    }
                }
                
                Section(header: Text("Refresh Settings")) {
                    Picker("Poll Interval", selection: Binding(
                        get: { self.store.pollInterval },
                        set: { self.store.updatePollInterval($0) }
                    )) {
                        ForEach(SettingsView.pollIntervalOptions, id: \.self) { interval in
                            Text(SettingsView.formatInterval(interval)).tag(interval)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }

                Section(header: Text("Server Settings")) {
                    NavigationLink(destination: iOSTorrentsSettingsPage(store: store)) {
                        Label("Torrents", systemImage: "arrow.down.circle")
                    }
                    NavigationLink(destination: iOSSpeedLimitsSettingsPage(store: store)) {
                        Label("Speed Limits", systemImage: "speedometer")
                    }
                    NavigationLink(destination: iOSNetworkSettingsPage(store: store)) {
                        Label("Network", systemImage: "network")
                    }
                }
                
                Section(header: Text("Reset")) {
                    Button(action: {
                        SettingsView.resetAllSettings(store: store)
                    }) {
                        Text("Reset All Settings")
                            .foregroundColor(.accentColor)
                    }
                }
                
                Section(header: Text("About")) {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                            .foregroundColor(.gray)
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct AccentColorPicker: View {
    @Binding var selection: AccentColorOption
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        List {
            ForEach(AccentColorOption.allCases) { option in
                HStack {
                    Circle()
                        .fill(option.color)
                        .frame(width: 20, height: 20)
                    
                    Text(option.name)
                    
                    Text(option.rawValue)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if selection == option {
                        Image(systemName: "checkmark")
                            .foregroundColor(.accentColor)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.1)) {
                        selection = option
                        ThemeManager.shared.setAccentColor(option)
                    }
                }
            }
        }
        .navigationTitle("Accent Color")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - iOS Server Settings Pages (reuse shared content)

private struct iOSTorrentsSettingsPage: View {
    @ObservedObject var store: Store
    @StateObject private var editModel = SessionSettingsEditModel()
    
    var body: some View {
        Group {
            if let config = store.sessionConfiguration {
                Form {
                    Section(header: Text("File Management")) {
                        HStack {
                            Text("Download Directory")
                            Spacer()
                            Text(editModel.getValue("downloadDir", fallback: config.downloadDir))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        
                        Button("Check Free Space") {
                            checkDirectoryFreeSpace(
                                path: editModel.getValue("downloadDir", fallback: config.downloadDir),
                                editModel: editModel
                            )
                        }
                        
                        if let freeSpaceInfo = editModel.freeSpaceInfo {
                            HStack {
                                Text("Available Space")
                                Spacer()
                                if editModel.isCheckingSpace {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                } else {
                                    Text(freeSpaceInfo)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        
                        Toggle("Use separate incomplete directory", isOn: Binding(
                            get: { editModel.getValue("incompleteDirEnabled", fallback: config.incompleteDirEnabled) },
                            set: { editModel.setValue("incompleteDirEnabled", $0, original: config.incompleteDirEnabled) }
                        ))
                        
                        Toggle("Start transfers when added", isOn: Binding(
                            get: { editModel.getValue("startAddedTorrents", fallback: config.startAddedTorrents) },
                            set: { editModel.setValue("startAddedTorrents", $0, original: config.startAddedTorrents) }
                        ))
                        
                        Toggle("Delete original .torrent files", isOn: Binding(
                            get: { editModel.getValue("trashOriginalTorrentFiles", fallback: config.trashOriginalTorrentFiles) },
                            set: { editModel.setValue("trashOriginalTorrentFiles", $0, original: config.trashOriginalTorrentFiles) }
                        ))
                        
                        Toggle("Append .part to incomplete files", isOn: Binding(
                            get: { editModel.getValue("renamePartialFiles", fallback: config.renamePartialFiles) },
                            set: { editModel.setValue("renamePartialFiles", $0, original: config.renamePartialFiles) }
                        ))
                    }
                    
                    Section(header: Text("Queue Management")) {
                        Toggle("Download queue", isOn: Binding(
                            get: { editModel.getValue("downloadQueueEnabled", fallback: config.downloadQueueEnabled) },
                            set: { editModel.setValue("downloadQueueEnabled", $0, original: config.downloadQueueEnabled) }
                        ))
                        
                        HStack {
                            Text("Maximum active downloads")
                            Spacer()
                            TextField("", value: Binding(
                                get: { editModel.getValue("downloadQueueSize", fallback: config.downloadQueueSize) },
                                set: { editModel.setValue("downloadQueueSize", $0, original: config.downloadQueueSize) }
                            ), format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .disabled(!editModel.getValue("downloadQueueEnabled", fallback: config.downloadQueueEnabled))
                            .foregroundColor(editModel.getValue("downloadQueueEnabled", fallback: config.downloadQueueEnabled) ? .primary : .secondary)
                        }
                        
                        Toggle("Seed queue", isOn: Binding(
                            get: { editModel.getValue("seedQueueEnabled", fallback: config.seedQueueEnabled) },
                            set: { editModel.setValue("seedQueueEnabled", $0, original: config.seedQueueEnabled) }
                        ))
                        
                        HStack {
                            Text("Maximum active seeds")
                            Spacer()
                            TextField("", value: Binding(
                                get: { editModel.getValue("seedQueueSize", fallback: config.seedQueueSize) },
                                set: { editModel.setValue("seedQueueSize", $0, original: config.seedQueueSize) }
                            ), format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .disabled(!editModel.getValue("seedQueueEnabled", fallback: config.seedQueueEnabled))
                            .foregroundColor(editModel.getValue("seedQueueEnabled", fallback: config.seedQueueEnabled) ? .primary : .secondary)
                        }
                        
                        Toggle("Consider idle torrents as stalled", isOn: Binding(
                            get: { editModel.getValue("queueStalledEnabled", fallback: config.queueStalledEnabled) },
                            set: { editModel.setValue("queueStalledEnabled", $0, original: config.queueStalledEnabled) }
                        ))
                        
                        HStack {
                            Text("Stalled after (minutes)")
                            Spacer()
                            TextField("", value: Binding(
                                get: { editModel.getValue("queueStalledMinutes", fallback: config.queueStalledMinutes) },
                                set: { editModel.setValue("queueStalledMinutes", $0, original: config.queueStalledMinutes) }
                            ), format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .disabled(!editModel.getValue("queueStalledEnabled", fallback: config.queueStalledEnabled))
                            .foregroundColor(editModel.getValue("queueStalledEnabled", fallback: config.queueStalledEnabled) ? .primary : .secondary)
                        }
                    }
                    
                    Section(header: Text("Seeding")) {
                        Toggle("Stop seeding at ratio", isOn: Binding(
                            get: { editModel.getValue("seedRatioLimited", fallback: config.seedRatioLimited) },
                            set: { editModel.setValue("seedRatioLimited", $0, original: config.seedRatioLimited) }
                        ))
                        
                        HStack {
                            Text("Seed ratio limit")
                            Spacer()
                            TextField("", value: Binding(
                                get: { editModel.getValue("seedRatioLimit", fallback: config.seedRatioLimit) },
                                set: { editModel.setValue("seedRatioLimit", $0, original: config.seedRatioLimit) }
                            ), format: .number.precision(.fractionLength(2)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .disabled(!editModel.getValue("seedRatioLimited", fallback: config.seedRatioLimited))
                            .foregroundColor(editModel.getValue("seedRatioLimited", fallback: config.seedRatioLimited) ? .primary : .secondary)
                        }
                        
                        Toggle("Stop seeding when inactive", isOn: Binding(
                            get: { editModel.getValue("idleSeedingLimitEnabled", fallback: config.idleSeedingLimitEnabled) },
                            set: { editModel.setValue("idleSeedingLimitEnabled", $0, original: config.idleSeedingLimitEnabled) }
                        ))
                        
                        HStack {
                            Text("Inactive for (minutes)")
                            Spacer()
                            TextField("", value: Binding(
                                get: { editModel.getValue("idleSeedingLimit", fallback: config.idleSeedingLimit) },
                                set: { editModel.setValue("idleSeedingLimit", $0, original: config.idleSeedingLimit) }
                            ), format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .disabled(!editModel.getValue("idleSeedingLimitEnabled", fallback: config.idleSeedingLimitEnabled))
                            .foregroundColor(editModel.getValue("idleSeedingLimitEnabled", fallback: config.idleSeedingLimitEnabled) ? .primary : .secondary)
                        }
                    }
                }
                .navigationTitle("Torrents")
                .onAppear { editModel.setup(store: store) }
            } else {
                ContentUnavailableView(
                    "No Server Connected",
                    systemImage: "arrow.down.circle",
                    description: Text("Torrent settings will appear when connected to a server.")
                )
            }
        }
    }
}

private struct iOSSpeedLimitsSettingsPage: View {
    @ObservedObject var store: Store
    @StateObject private var editModel = SessionSettingsEditModel()
    
    var body: some View {
        Group {
            if let config = store.sessionConfiguration {
                Form {
                    Section(header: Text("Speed Limits")) {
                        Toggle("Download limit", isOn: Binding(
                            get: { editModel.getValue("speedLimitDownEnabled", fallback: config.speedLimitDownEnabled) },
                            set: { editModel.setValue("speedLimitDownEnabled", $0, original: config.speedLimitDownEnabled) }
                        ))
                        
                        HStack {
                            Text("Download speed (KB/s)")
                            Spacer()
                            TextField("", value: Binding(
                                get: { editModel.getValue("speedLimitDown", fallback: config.speedLimitDown) },
                                set: { editModel.setValue("speedLimitDown", $0, original: config.speedLimitDown) }
                            ), format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .disabled(!editModel.getValue("speedLimitDownEnabled", fallback: config.speedLimitDownEnabled))
                            .foregroundColor(editModel.getValue("speedLimitDownEnabled", fallback: config.speedLimitDownEnabled) ? .primary : .secondary)
                        }
                        
                        Toggle("Upload limit", isOn: Binding(
                            get: { editModel.getValue("speedLimitUpEnabled", fallback: config.speedLimitUpEnabled) },
                            set: { editModel.setValue("speedLimitUpEnabled", $0, original: config.speedLimitUpEnabled) }
                        ))
                        
                        HStack {
                            Text("Upload speed (KB/s)")
                            Spacer()
                            TextField("", value: Binding(
                                get: { editModel.getValue("speedLimitUp", fallback: config.speedLimitUp) },
                                set: { editModel.setValue("speedLimitUp", $0, original: config.speedLimitUp) }
                            ), format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .disabled(!editModel.getValue("speedLimitUpEnabled", fallback: config.speedLimitUpEnabled))
                            .foregroundColor(editModel.getValue("speedLimitUpEnabled", fallback: config.speedLimitUpEnabled) ? .primary : .secondary)
                        }
                    }
                    
                    Section(header: Text("Alternate Speed Limits")) {
                        Toggle("Enable alternate speeds", isOn: Binding(
                            get: { editModel.getValue("altSpeedEnabled", fallback: config.altSpeedEnabled) },
                            set: { editModel.setValue("altSpeedEnabled", $0, original: config.altSpeedEnabled) }
                        ))
                        
                        HStack {
                            Text("Download limit (KB/s)")
                            Spacer()
                            TextField("", value: Binding(
                                get: { editModel.getValue("altSpeedDown", fallback: config.altSpeedDown) },
                                set: { editModel.setValue("altSpeedDown", $0, original: config.altSpeedDown) }
                            ), format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .disabled(!editModel.getValue("altSpeedEnabled", fallback: config.altSpeedEnabled))
                            .foregroundColor(editModel.getValue("altSpeedEnabled", fallback: config.altSpeedEnabled) ? .primary : .secondary)
                        }
                        
                        HStack {
                            Text("Upload limit (KB/s)")
                            Spacer()
                            TextField("", value: Binding(
                                get: { editModel.getValue("altSpeedUp", fallback: config.altSpeedUp) },
                                set: { editModel.setValue("altSpeedUp", $0, original: config.altSpeedUp) }
                            ), format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .disabled(!editModel.getValue("altSpeedEnabled", fallback: config.altSpeedEnabled))
                            .foregroundColor(editModel.getValue("altSpeedEnabled", fallback: config.altSpeedEnabled) ? .primary : .secondary)
                        }
                        
                        Toggle("Schedule alternate speeds", isOn: Binding(
                            get: { editModel.getValue("altSpeedTimeEnabled", fallback: config.altSpeedTimeEnabled) },
                            set: { editModel.setValue("altSpeedTimeEnabled", $0, original: config.altSpeedTimeEnabled) }
                        ))
                        .disabled(!editModel.getValue("altSpeedEnabled", fallback: config.altSpeedEnabled))
                        
                        Picker("Days", selection: Binding(
                            get: { editModel.getValue("altSpeedTimeDay", fallback: config.altSpeedTimeDay) },
                            set: { editModel.setValue("altSpeedTimeDay", $0, original: config.altSpeedTimeDay) }
                        )) {
                            Text("Every Day").tag(127)
                            Text("Weekdays").tag(62)
                            Text("Weekends").tag(65)
                            Text("Sunday").tag(1)
                            Text("Monday").tag(2)
                            Text("Tuesday").tag(4)
                            Text("Wednesday").tag(8)
                            Text("Thursday").tag(16)
                            Text("Friday").tag(32)
                            Text("Saturday").tag(64)
                        }
                        .disabled(!editModel.getValue("altSpeedTimeEnabled", fallback: config.altSpeedTimeEnabled))
                        
                        DatePicker("Start Time", selection: Binding(
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
                        .disabled(!editModel.getValue("altSpeedTimeEnabled", fallback: config.altSpeedTimeEnabled))
                        
                        DatePicker("End Time", selection: Binding(
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
                        .disabled(!editModel.getValue("altSpeedTimeEnabled", fallback: config.altSpeedTimeEnabled))
                    }
                }
                .navigationTitle("Speed Limits")
                .onAppear { editModel.setup(store: store) }
            } else {
                ContentUnavailableView(
                    "No Server Connected",
                    systemImage: "speedometer",
                    description: Text("Speed limit settings will appear when connected to a server.")
                )
            }
        }
    }
}

private struct iOSNetworkSettingsPage: View {
    @ObservedObject var store: Store
    @StateObject private var editModel = SessionSettingsEditModel()
    
    var body: some View {
        Group {
            if let config = store.sessionConfiguration {
                Form {
                    Section(header: Text("Connection")) {
                        HStack {
                            Text("Peer listening port")
                            Spacer()
                            TextField("", value: Binding(
                                get: { editModel.getValue("peerPort", fallback: config.peerPort) },
                                set: { editModel.setValue("peerPort", $0, original: config.peerPort) }
                            ), format: .number.grouping(.never))
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                        }
                        
                        Button("Check Port") {
                            checkPort(editModel: editModel, ipProtocol: nil)
                        }
                        .disabled(editModel.isTestingPort)
                        
                        if editModel.isTestingPort {
                            HStack {
                                Text("Testing port...")
                                Spacer()
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        } else if let portTestResult = editModel.portTestResult {
                            HStack {
                                Text("Port Status")
                                Spacer()
                                Text(portTestResult)
                                    .foregroundColor(portTestResult.contains("open") ? .green : .orange)
                            }
                        }
                        
                        Toggle("Randomize port on launch", isOn: Binding(
                            get: { editModel.getValue("peerPortRandomOnStart", fallback: config.peerPortRandomOnStart) },
                            set: { editModel.setValue("peerPortRandomOnStart", $0, original: config.peerPortRandomOnStart) }
                        ))
                        
                        Picker("Encryption", selection: Binding(
                            get: { editModel.getValue("encryption", fallback: config.encryption) },
                            set: { editModel.setValue("encryption", $0, original: config.encryption) }
                        )) {
                            Text("Required").tag("required")
                            Text("Preferred").tag("preferred")
                            Text("Tolerated").tag("tolerated")
                        }
                    }
                    
                    Section(header: Text("Peer Exchange")) {
                        Toggle("Enable port forwarding", isOn: Binding(
                            get: { editModel.getValue("portForwardingEnabled", fallback: config.portForwardingEnabled) },
                            set: { editModel.setValue("portForwardingEnabled", $0, original: config.portForwardingEnabled) }
                        ))
                        
                        Toggle("Enable DHT", isOn: Binding(
                            get: { editModel.getValue("dhtEnabled", fallback: config.dhtEnabled) },
                            set: { editModel.setValue("dhtEnabled", $0, original: config.dhtEnabled) }
                        ))
                        
                        Toggle("Enable PEX", isOn: Binding(
                            get: { editModel.getValue("pexEnabled", fallback: config.pexEnabled) },
                            set: { editModel.setValue("pexEnabled", $0, original: config.pexEnabled) }
                        ))
                        
                        Toggle("Enable LPD", isOn: Binding(
                            get: { editModel.getValue("lpdEnabled", fallback: config.lpdEnabled) },
                            set: { editModel.setValue("lpdEnabled", $0, original: config.lpdEnabled) }
                        ))
                        
                        Toggle("Enable µTP", isOn: Binding(
                            get: { editModel.getValue("utpEnabled", fallback: config.utpEnabled) },
                            set: { editModel.setValue("utpEnabled", $0, original: config.utpEnabled) }
                        ))
                    }
                    
                    Section(header: Text("Peer Limits")) {
                        HStack {
                            Text("Maximum global peers")
                            Spacer()
                            TextField("", value: Binding(
                                get: { editModel.getValue("peerLimitGlobal", fallback: config.peerLimitGlobal) },
                                set: { editModel.setValue("peerLimitGlobal", $0, original: config.peerLimitGlobal) }
                            ), format: .number.grouping(.never))
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                        }
                        
                        HStack {
                            Text("Maximum per torrent peers")
                            Spacer()
                            TextField("", value: Binding(
                                get: { editModel.getValue("peerLimitPerTorrent", fallback: config.peerLimitPerTorrent) },
                                set: { editModel.setValue("peerLimitPerTorrent", $0, original: config.peerLimitPerTorrent) }
                            ), format: .number.grouping(.never))
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                        }
                    }
                    
                    Section(header: Text("Blocklist")) {
                        Toggle("Enable blocklist", isOn: Binding(
                            get: { editModel.getValue("blocklistEnabled", fallback: config.blocklistEnabled) },
                            set: { editModel.setValue("blocklistEnabled", $0, original: config.blocklistEnabled) }
                        ))
                        
                        HStack {
                            Text("Blocklist URL")
                            Spacer()
                            TextField("URL", text: Binding(
                                get: { editModel.getValue("blocklistUrl", fallback: config.blocklistUrl) },
                                set: { editModel.setValue("blocklistUrl", $0, original: config.blocklistUrl) }
                            ))
                            .multilineTextAlignment(.trailing)
                            .disabled(!editModel.getValue("blocklistEnabled", fallback: config.blocklistEnabled))
                            .foregroundColor(editModel.getValue("blocklistEnabled", fallback: config.blocklistEnabled) ? .primary : .secondary)
                        }
                        
                        HStack {
                            Text("Rules active")
                            Spacer()
                            if editModel.isUpdatingBlocklist {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Text("\(config.blocklistSize)")
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Button("Update Blocklist") {
                            updateBlocklist(editModel: editModel)
                        }
                        .disabled(editModel.isUpdatingBlocklist || !editModel.getValue("blocklistEnabled", fallback: config.blocklistEnabled))
                        
                        if let blocklistUpdateResult = editModel.blocklistUpdateResult {
                            Text(blocklistUpdateResult)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .navigationTitle("Network")
                .onAppear { editModel.setup(store: store) }
            } else {
                ContentUnavailableView(
                    "No Server Connected",
                    systemImage: "network",
                    description: Text("Network settings will appear when connected to a server.")
                )
            }
        }
    }
}

#Preview {
    iOSSettingsView(store: Store())
}
#else
// Empty struct for macOS to reference - this won't be compiled on macOS but provides the type
struct iOSSettingsView: View {
    @ObservedObject var store: Store
    
    var body: some View {
        EmptyView()
    }
}
#endif 