#if os(iOS)
import SwiftUI
import Foundation
import UIKit

typealias PlatformSettingsView = iOSSettingsView

struct iOSSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.hapticFeedback) private var hapticFeedback
    @Environment(\.appUserDefaults) private var userDefaults
    @EnvironmentObject private var appIconManager: AppIconManager
    @EnvironmentObject private var themeManager: ThemeManager

    @ObservedObject var store: TransmissionStore
    @AppStorage(UserDefaultsKeys.showContentTypeIcons) private var showContentTypeIcons: Bool = AppDefaults.showContentTypeIcons
    @AppStorage(UserDefaultsKeys.startupConnectionBehavior) private var startupBehaviorRaw: String = AppDefaults.startupConnectionBehavior.rawValue
    @AppStorage(UserDefaultsKeys.hapticFeedbackEnabled) private var isHapticFeedbackEnabled = AppDefaults.hapticFeedbackEnabled

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Appearance")) {
                    Picker("Theme", selection: $themeManager.themeMode) {
                        ForEach(ThemeMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }

                    NavigationLink(destination: AccentColorPicker(selection: $themeManager.currentAccentColorOption)
                        .iOSHapticNavigationTransition()) {
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

                    NavigationLink(destination: AppIconPickerView(appIconManager: appIconManager)
                        .iOSHapticNavigationTransition()) {
                        HStack {
                            Text("App Icon")
                            Spacer()
                            CurrentAppIconPreview(appIconManager: appIconManager)
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

                Section {
                    Toggle("Haptic Feedback", isOn: $isHapticFeedbackEnabled)
                        .sensoryFeedback(.selection, trigger: isHapticFeedbackEnabled)
                } header: {
                    Text("Interaction")
                } footer: {
                    Text("Provides tactile confirmation for important actions and outcomes.")
                }

                Section(header: Text("Refresh Settings")) {
                    Picker("Poll Interval", selection: Binding(
                        get: { store.pollInterval },
                        set: { store.updatePollInterval($0) }
                    )) {
                        ForEach(SettingsView.pollIntervalOptions, id: \.self) { interval in
                            Text(SettingsView.formatInterval(interval)).tag(interval)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }

                Section(header: Text("Server Settings")) {
                    NavigationLink(destination: iOSTorrentsSettingsView(store: store)
                        .iOSHapticNavigationTransition()) {
                        Label("Torrents", systemImage: "arrow.down.circle")
                    }
                    NavigationLink(destination: iOSSpeedLimitsSettingsView(store: store)
                        .iOSHapticNavigationTransition()) {
                        Label("Speed Limits", systemImage: "speedometer")
                    }
                    NavigationLink(destination: iOSNetworkSettingsView(store: store)
                        .iOSHapticNavigationTransition()) {
                        Label("Network", systemImage: "network")
                    }
                }

                Section(header: Text("Reset")) {
                    Button("Reset All Settings") {
                        hapticFeedback.play(.actionTriggered)
                        SettingsView.resetAllSettings(
                            store: store,
                            themeManager: themeManager,
                            userDefaults: userDefaults
                        )
                        hapticFeedback.play(.operationSucceeded)
                    }
                    .foregroundColor(.accentColor)
                }

                Section(header: Text("About")) {
                    NavigationLink(destination: iOSAboutView()
                        .iOSHapticNavigationTransition()) {
                        HStack {
                            Text("About BitDream")
                            Spacer()
                            Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                                .foregroundColor(.gray)
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .onChange(of: themeManager.themeMode) {
                hapticFeedback.play(.selectionChanged)
            }
            .onChange(of: showContentTypeIcons) {
                hapticFeedback.play(.selectionChanged)
            }
            .onChange(of: startupBehaviorRaw) {
                hapticFeedback.play(.selectionChanged)
            }
            .onChange(of: store.pollInterval) {
                hapticFeedback.play(.selectionChanged)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        hapticFeedback.play(.actionTriggered)
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct AccentColorPicker: View {
    @Environment(\.hapticFeedback) private var hapticFeedback
    @EnvironmentObject private var themeManager: ThemeManager
    @Binding var selection: AccentColorOption

    var body: some View {
        List {
            ForEach(AccentColorOption.allCases) { option in
                Button {
                    guard selection != option else { return }

                    withAnimation(.easeInOut(duration: 0.1)) {
                        selection = option
                        themeManager.setAccentColor(option)
                    }
                    hapticFeedback.play(.selectionChanged)
                } label: {
                    HStack {
                        Circle()
                            .fill(option.color)
                            .frame(width: 20, height: 20)

                        Text(option.name)

                        Text(option.rawValue)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)

                        Spacer()

                        if selection == option {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle("Accent Color")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AppIconOption: Identifiable, Equatable {
    let id: String
    let key: String?
    let title: String
    let previewAssetName: String
}

private struct AppIconPickerView: View {
    @Environment(\.hapticFeedback) private var hapticFeedback
    @ObservedObject var appIconManager: AppIconManager
    @State private var options: [AppIconOption] = []

    var body: some View {
        List {
            ForEach(options) { option in
                Button {
                    selectIcon(option)
                } label: {
                    HStack(spacing: 12) {
                        PreviewThumbnail(name: option.previewAssetName)
                            .frame(width: 44, height: 44)
                            .clipShape(.rect(cornerRadius: 8, style: .continuous))
                        Text(option.title)
                        Spacer()
                        if appIconManager.currentIconName == option.key {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(appIconManager.isChanging)
            }

            if let lastError = appIconManager.lastError {
                Section {
                    Text(lastError)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("App Icon")
        .onAppear {
            reloadOptions()
            appIconManager.refreshCurrentIcon()
        }
    }

    private func reloadOptions() {
        let presentations = AppIconCatalog.presentations()
        options = presentations.map { presentation in
            AppIconOption(
                id: presentation.key ?? "__default__",
                key: presentation.key,
                title: presentation.title,
                previewAssetName: presentation.previewAssetName
            )
        }
    }

    private func selectIcon(_ option: AppIconOption) {
        appIconManager.selectIcon(name: option.key) { outcome in
            switch outcome {
            case .changed:
                hapticFeedback.play(.operationSucceeded)
            case .failed:
                hapticFeedback.play(.operationFailed)
            case .unchanged:
                break
            }
        }
    }
}

private struct PreviewThumbnail: View {
    let name: String

    var body: some View {
        if UIImage(named: name) != nil {
            Image(name)
                .resizable()
                .scaledToFill()
                .background(Color(.secondarySystemBackground))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
                Image(systemName: "app")
                    .foregroundColor(.secondary)
            }
        }
    }
}

private struct CurrentAppIconPreview: View {
    @ObservedObject var appIconManager: AppIconManager

    private var previewAssetName: String {
        if let key = appIconManager.currentIconName,
           let preset = AppIconCatalog.entries.first(where: { $0.key == key }) {
            return preset.previewAssetName
        }

        return AppIconCatalog.entries.first(where: { $0.key == nil })?.previewAssetName ?? "AppIconPreview-Default"
    }

    var body: some View {
        Image(previewAssetName)
            .resizable()
            .scaledToFill()
            .frame(width: 22, height: 22)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.secondary.opacity(0.2), lineWidth: 0.5))
    }
}

#if DEBUG
#Preview("iOS Settings") {
    PreviewContainer { environment in
        iOSSettingsView(store: environment.store)
    }
}
#endif
#endif
