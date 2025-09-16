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
                // Appearance section
                GroupBox(label: Text("Appearance").font(.headline)) {
                    VStack(alignment: .leading, spacing: 12) {
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
                        .padding(.top, 4)
                        
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
                        
                        Divider()
                            .padding(.vertical, 8)
                        
                        // Content Type Icons toggle
                        Toggle("Show file type icons", isOn: $showContentTypeIcons)
                    }
                    .padding(10)
                }
                
                // Connection Settings section
                GroupBox(label: Text("Connection Settings").font(.headline)) {
                    VStack(alignment: .leading, spacing: 12) {
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
                    .padding(10)
                }
                
                // Notifications section
                GroupBox(label: Text("Notifications").font(.headline)) {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Show app badge for completed torrents", isOn: .constant(true))
                            .disabled(true)
                            .padding(.top, 4)
                        
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
                    .padding(10)
                }
                
                // Reset section
                GroupBox(label: Text("Reset").font(.headline)) {
                    VStack {
                        Button("Reset All Settings") {
                            SettingsView.resetAllSettings(store: store)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                    }
                    .padding(10)
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
                    fileManagementSection(config: config, editModel: editModel)
                    queueManagementSection(config: config, editModel: editModel)
                    seedingSection(config: config, editModel: editModel)
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