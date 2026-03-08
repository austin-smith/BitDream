import SwiftUI
import Foundation

#if os(macOS)
typealias PlatformSettingsView = macOSSettingsView

struct macOSSettingsView: View {
    @ObservedObject var store: TransmissionStore
    @StateObject private var editModel = SettingsViewModel()

    @ObservedObject private var themeManager = ThemeManager.shared

    var body: some View {
        TabView {
            macOSGeneralSettingsTab(store: store)
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            SettingsServerTab(
                config: store.sessionConfiguration,
                store: store,
                editModel: editModel,
                unavailableSystemImage: "arrow.down.circle",
                unavailableDescription: "Torrent settings will appear when connected to a server."
            ) { config, editModel in
                macOSTorrentSettingsTab(config: config, editModel: editModel)
            }
            .tabItem {
                Label("Torrents", systemImage: "arrow.down.circle")
            }

            SettingsServerTab(
                config: store.sessionConfiguration,
                store: store,
                editModel: editModel,
                unavailableSystemImage: "speedometer",
                unavailableDescription: "Speed limit settings will appear when connected to a server."
            ) { config, editModel in
                macOSSpeedLimitsSettingsTab(config: config, editModel: editModel)
            }
            .tabItem {
                Label("Speed Limits", systemImage: "speedometer")
            }

            SettingsServerTab(
                config: store.sessionConfiguration,
                store: store,
                editModel: editModel,
                unavailableSystemImage: "network",
                unavailableDescription: "Network settings will appear when connected to a server."
            ) { config, editModel in
                macOSNetworkSettingsTab(config: config, editModel: editModel)
            }
            .tabItem {
                Label("Network", systemImage: "network")
            }
        }
        .accentColor(themeManager.accentColor)
    }
}

private struct SettingsServerTab<Content: View>: View {
    let config: TransmissionSessionResponseArguments?
    let store: TransmissionStore
    let editModel: SettingsViewModel
    let unavailableSystemImage: String
    let unavailableDescription: String
    let content: (TransmissionSessionResponseArguments, SettingsViewModel) -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let config {
                content(config, editModel)
                SettingsSaveStateView(state: editModel.saveState)
                Spacer()
            } else {
                ContentUnavailableView(
                    "No Server Connected",
                    systemImage: unavailableSystemImage,
                    description: Text(unavailableDescription)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .bindSettingsViewModel(editModel, to: store)
    }
}

#Preview {
    macOSSettingsView(store: TransmissionStore())
        .environmentObject(AppUpdater())
}
#endif
