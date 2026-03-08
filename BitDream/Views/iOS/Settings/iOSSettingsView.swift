#if os(iOS)
import SwiftUI
import Foundation
import UIKit

typealias PlatformSettingsView = iOSSettingsView

struct iOSSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var store: TransmissionStore

    @ObservedObject private var themeManager = ThemeManager.shared
    @StateObject private var appIconManager = AppIconManager.shared
    @AppStorage(UserDefaultsKeys.showContentTypeIcons) private var showContentTypeIcons: Bool = AppDefaults.showContentTypeIcons
    @AppStorage(UserDefaultsKeys.startupConnectionBehavior) private var startupBehaviorRaw: String = AppDefaults.startupConnectionBehavior.rawValue

    var body: some View {
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

                    NavigationLink(destination: AppIconPickerView(appIconManager: appIconManager)) {
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
                    NavigationLink(destination: iOSTorrentsSettingsView(store: store)) {
                        Label("Torrents", systemImage: "arrow.down.circle")
                    }
                    NavigationLink(destination: iOSSpeedLimitsSettingsView(store: store)) {
                        Label("Speed Limits", systemImage: "speedometer")
                    }
                    NavigationLink(destination: iOSNetworkSettingsView(store: store)) {
                        Label("Network", systemImage: "network")
                    }
                }

                Section(header: Text("Reset")) {
                    Button("Reset All Settings") {
                        SettingsView.resetAllSettings(store: store)
                    }
                    .foregroundColor(.accentColor)
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

private struct AccentColorPicker: View {
    @Binding var selection: AccentColorOption

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

private struct AppIconOption: Identifiable, Equatable {
    let id: String
    let key: String?
    let title: String
    let previewAssetName: String
}

private struct AppIconPickerView: View {
    @ObservedObject var appIconManager: AppIconManager
    @State private var options: [AppIconOption] = []

    var body: some View {
        List {
            ForEach(options) { option in
                HStack(spacing: 12) {
                    PreviewThumbnail(name: option.previewAssetName)
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    Text(option.title)
                    Spacer()
                    if appIconManager.currentIconName == option.key {
                        Image(systemName: "checkmark")
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    appIconManager.selectIcon(name: option.key)
                }
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

#Preview {
    iOSSettingsView(store: TransmissionStore())
}
#endif
