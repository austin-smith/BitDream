import SwiftUI
import Foundation

#if os(macOS)
struct macOSGeneralSettingsTab: View {
    @EnvironmentObject private var appUpdater: AppUpdater
    @ObservedObject var store: TransmissionStore

    @ObservedObject private var themeManager = ThemeManager.shared
    @AppStorage(UserDefaultsKeys.showContentTypeIcons) private var showContentTypeIcons: Bool = AppDefaults.showContentTypeIcons
    @AppStorage(UserDefaultsKeys.menuBarTransferWidgetEnabled) private var menuBarTransferWidgetEnabled: Bool = AppDefaults.menuBarTransferWidgetEnabled
    @AppStorage(UserDefaultsKeys.menuBarSortMode) private var menuBarSortModeRaw: String = AppDefaults.menuBarSortMode.rawValue
    @AppStorage(UserDefaultsKeys.startupConnectionBehavior) private var startupBehaviorRaw: String = AppDefaults.startupConnectionBehavior.rawValue

    private var menuBarSortMode: Binding<MenuBarSortMode> {
        Binding<MenuBarSortMode>(
            get: { MenuBarSortMode(rawValue: menuBarSortModeRaw) ?? AppDefaults.menuBarSortMode },
            set: { menuBarSortModeRaw = $0.rawValue }
        )
    }

    private var automaticallyChecksForUpdatesBinding: Binding<Bool> {
        Binding<Bool>(
            get: { appUpdater.automaticallyChecksForUpdates },
            set: { appUpdater.automaticallyChecksForUpdates = $0 }
        )
    }

    private var lastUpdateCheckText: String {
        guard let date = appUpdater.lastUpdateCheckDate else { return "Never" }
        return date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            GroupBox {
                VStack(alignment: .leading, spacing: 16) {
                    settingsSection("Appearance") {
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

                        Toggle("Show file type icons", isOn: $showContentTypeIcons)
                    }

                    divider

                    settingsSection("Menu Bar") {
                        Toggle("Show BitDream in menu bar", isOn: $menuBarTransferWidgetEnabled)

                        HStack {
                            Text("Sort torrents by")
                            Spacer()
                            Picker("", selection: menuBarSortMode) {
                                ForEach(MenuBarSortMode.allCases, id: \.self) { mode in
                                    Text(mode.label).tag(mode)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }

                    divider

                    settingsSection("Connection Settings") {
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

                    divider

                    settingsSection("Updates") {
                        Toggle("Automatically check for updates", isOn: automaticallyChecksForUpdatesBinding)

                        HStack(alignment: .firstTextBaseline) {
                            Button("Check for Updates…") {
                                appUpdater.checkForUpdates()
                            }
                            .disabled(!appUpdater.canCheckForUpdates)

                            Spacer()

                            Text("Last checked: \(lastUpdateCheckText)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    divider

                    settingsSection("Notifications") {
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

                    divider

                    settingsSection("Reset") {
                        Button("Reset All Settings") {
                            SettingsView.resetAllSettings(store: store) {
                                appUpdater.resetToDefaults()
                            }
                        }
                    }
                }
                .padding(16)
            }
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.bottom, 4)
            content()
        }
    }

    private var divider: some View {
        Divider()
            .padding(.vertical, 4)
    }
}
#endif
