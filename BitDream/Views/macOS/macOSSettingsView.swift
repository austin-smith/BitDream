import SwiftUI
import Foundation

#if os(macOS)
struct macOSSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showingThemeSettings = false
    @ObservedObject var store: Store
    @StateObject private var editModel = SessionSettingsEditModel()
    
    // Use ThemeManager instead of direct AppStorage
    @ObservedObject private var themeManager = ThemeManager.shared
    @AppStorage(UserDefaultsKeys.showContentTypeIcons) private var showContentTypeIcons: Bool = AppDefaults.showContentTypeIcons
    @AppStorage(UserDefaultsKeys.startupConnectionBehavior) private var startupBehaviorRaw: String = AppDefaults.startupConnectionBehavior.rawValue
    
    private var startupBehavior: Binding<StartupConnectionBehavior> {
        Binding<StartupConnectionBehavior>(
            get: { StartupConnectionBehavior(rawValue: startupBehaviorRaw) ?? AppDefaults.startupConnectionBehavior },
            set: { startupBehaviorRaw = $0.rawValue }
        )
    }
    
    var body: some View {
        // macOS version adapted for the Settings scene
        TabView {
            // General Tab
            VStack(alignment: .leading, spacing: 20) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Appearance")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .padding(.bottom, 4)
                            
                            // Theme selection (disabled for now)
                            HStack {
                                Text("Theme")
                                Spacer()
                                Picker("", selection: $themeManager.themeMode) {
                                    ForEach(ThemeMode.allCases, id: \.self) { mode in
                                        Text(mode.rawValue).tag(mode)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(width: 120)
                            }
                            
                            // Accent color
                            HStack {
                                Text("Accent Color")
                                Spacer()
                                Picker("", selection: $themeManager.currentAccentColorOption) {
                                    ForEach(AccentColorOption.allCases) { option in
                                        HStack {
                                            Circle()
                                                .fill(option.color)
                                                .frame(width: 12, height: 12)
                                            Text(option.name)
                                        }
                                        .tag(option)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(width: 120)
                            }
                            
                            // Color preview
                            HStack(spacing: 12) {
                                ForEach(AccentColorOption.allCases) { option in
                                    VStack {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(option.color)
                                            .frame(width: 40, height: 40)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .stroke(themeManager.currentAccentColorOption == option ? Color.primary : Color.clear, lineWidth: 2)
                                            )
                                        Text(option.rawValue)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    .onTapGesture {
                                        themeManager.setAccentColor(option)
                                    }
                                }
                            }
                            .padding(.top, 8)
                            
                            // Content Type Icons toggle
                            Toggle("Show file type icons", isOn: $showContentTypeIcons)
                        }
                        
                        Divider()
                            .padding(.vertical, 4)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Connection Settings")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .padding(.bottom, 4)
                            
                            HStack {
                                Text("Startup connection")
                                Spacer()
                                Picker("", selection: .fromRawValue(rawValue: $startupBehaviorRaw, defaultValue: AppDefaults.startupConnectionBehavior)) {
                                    Text("Last used server").tag(StartupConnectionBehavior.lastUsed)
                                    Text("Default server").tag(StartupConnectionBehavior.defaultServer)
                                }
                                .pickerStyle(.menu)
                                .frame(width: 160)
                            }
                            .help("Choose which server BitDream connects to when it launches.")
                            
                            HStack {
                                Text("Auto-refresh interval")
                                Spacer()
                                Picker("", selection: $store.pollInterval) {
                                    ForEach(SettingsView.pollIntervalOptions, id: \.self) { interval in
                                        Text(SettingsView.formatInterval(interval)).tag(interval)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(width: 120)
                            }
                        }
                        
                        Divider()
                            .padding(.vertical, 4)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Notifications")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .padding(.bottom, 4)
                            
                            Toggle("Show app badge for completed torrents", isOn: .constant(true))
                                .disabled(true)
                            
                            Toggle("Show notifications for completed torrents", isOn: .constant(false))
                                .disabled(true)
                                
                            Text("Advanced settings coming soon")
                                .font(.caption2)
                                .foregroundColor(.orange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.2))
                                .cornerRadius(4)
                        }
                        
                        Divider()
                            .padding(.vertical, 4)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Reset")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .padding(.bottom, 4)
                            
                            Button("Reset All Settings") {
                                SettingsView.resetAllSettings(store: store)
                            }
                        }
                    }
                    .padding(16)
                }
                Spacer()
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .tabItem {
                Label("General", systemImage: "gear")
            }
            
            // Torrents Tab (Files + Queues)
            VStack(alignment: .leading, spacing: 20) {
                if let config = store.sessionConfiguration {
                    torrentsTabContent(config: config, editModel: editModel)
                        .onAppear {
                            editModel.setup(store: store)
                        }
                    Spacer()
                } else {
                    ContentUnavailableView(
                        "No Server Connected",
                        systemImage: "arrow.down.circle",
                        description: Text("Torrent settings will appear when connected to a server.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .tabItem {
                Label("Torrents", systemImage: "arrow.down.circle")
            }
            
            // Speed Limits Tab
            VStack(alignment: .leading, spacing: 20) {
                if let config = store.sessionConfiguration {
                    speedLimitsSection(config: config, editModel: editModel)
                        .onAppear {
                            editModel.setup(store: store)
                        }
                    Spacer()
                } else {
                    ContentUnavailableView(
                        "No Server Connected",
                        systemImage: "speedometer",
                        description: Text("Speed limit settings will appear when connected to a server.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .tabItem {
                Label("Speed Limits", systemImage: "speedometer")
            }
            
            // Network Tab
            VStack(alignment: .leading, spacing: 20) {
                if let config = store.sessionConfiguration {
                    networkSection(config: config, editModel: editModel)
                        .onAppear {
                            editModel.setup(store: store)
                        }
                    Spacer()
                } else {
                    ContentUnavailableView(
                        "No Server Connected",
                        systemImage: "network",
                        description: Text("Network settings will appear when connected to a server.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .tabItem {
                Label("Network", systemImage: "network")
            }
        }
        .accentColor(themeManager.accentColor) // Apply the accent color to the TabView
    }
}

@ViewBuilder
func torrentsTabContent(config: TransmissionSessionResponseArguments, editModel: SessionSettingsEditModel) -> some View {
    GroupBox {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Text("File Management")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 4)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Download Directory")
                        .font(.caption)
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
                    .toggleStyle(.checkbox)
                    
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
                .toggleStyle(.checkbox)
                
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
                .toggleStyle(.checkbox)
                
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
                .toggleStyle(.checkbox)
            }
            
            Divider()
                .padding(.vertical, 4)
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Queue Management")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 4)
                
                HStack {
                    Toggle("Download queue size", isOn: Binding(
                        get: { editModel.getValue("downloadQueueEnabled", fallback: config.downloadQueueEnabled) },
                        set: { editModel.setValue("downloadQueueEnabled", $0, original: config.downloadQueueEnabled) }
                    ))
                    .toggleStyle(.checkbox)
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
                    .toggleStyle(.checkbox)
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
                    .toggleStyle(.checkbox)
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
            
            Divider()
                .padding(.vertical, 4)
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Seeding")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 4)
                
                HStack {
                    Toggle("Stop seeding at ratio", isOn: Binding(
                        get: { editModel.getValue("seedRatioLimited", fallback: config.seedRatioLimited) },
                        set: { editModel.setValue("seedRatioLimited", $0, original: config.seedRatioLimited) }
                    ))
                    .toggleStyle(.checkbox)
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
                    .toggleStyle(.checkbox)
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
        }
        .padding(16)
    }
}

#Preview {
    macOSSettingsView(store: Store())
}
#else
// Empty struct for iOS to reference - this won't be compiled on macOS but provides the type
struct macOSSettingsView: View {
    @ObservedObject var store: Store
    
    var body: some View {
        EmptyView()
    }
}
#endif 