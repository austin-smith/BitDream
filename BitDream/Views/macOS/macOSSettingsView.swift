import SwiftUI
import Foundation

#if os(macOS)
typealias PlatformSettingsView = macOSSettingsView

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
            // File Management
            VStack(alignment: .leading, spacing: 12) {
                Text("File Management")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 4)
                FileManagementContent(config: config, editModel: editModel)
            }
            
            Divider()
                .padding(.vertical, 4)
            
            // Queue Management
            VStack(alignment: .leading, spacing: 12) {
                Text("Queue Management")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 4)
                QueueManagementContent(config: config, editModel: editModel)
            }
            
            Divider()
                .padding(.vertical, 4)
            
            // Seeding
            VStack(alignment: .leading, spacing: 12) {
                Text("Seeding")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 4)
                SeedingContent(config: config, editModel: editModel)
            }
        }
        .padding(16)
    }
}

// MARK: - macOS Wrappers for Shared Content

@ViewBuilder
func speedLimitsSection(config: TransmissionSessionResponseArguments, editModel: SessionSettingsEditModel) -> some View {
    GroupBox {
        SpeedLimitsContent(config: config, editModel: editModel)
            .padding(16)
    }
}

@ViewBuilder
func networkSection(config: TransmissionSessionResponseArguments, editModel: SessionSettingsEditModel) -> some View {
    GroupBox {
        NetworkContent(config: config, editModel: editModel)
            .padding(16)
    }
}

@ViewBuilder
func fileManagementSection(config: TransmissionSessionResponseArguments, editModel: SessionSettingsEditModel) -> some View {
    GroupBox(label: Text("File Management").font(.headline)) {
        FileManagementContent(config: config, editModel: editModel)
            .padding(16)
    }
}

@ViewBuilder
func queueManagementSection(config: TransmissionSessionResponseArguments, editModel: SessionSettingsEditModel) -> some View {
    GroupBox(label: Text("Queue Management").font(.headline)) {
        QueueManagementContent(config: config, editModel: editModel)
            .padding(16)
    }
}

@ViewBuilder
func seedingSection(config: TransmissionSessionResponseArguments, editModel: SessionSettingsEditModel) -> some View {
    GroupBox(label: Text("Seeding").font(.headline)) {
        SeedingContent(config: config, editModel: editModel)
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