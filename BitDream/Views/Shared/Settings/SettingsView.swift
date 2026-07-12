import SwiftUI
import Foundation

/// Platform-agnostic wrapper for SettingsView
/// This view simply delegates to the appropriate platform-specific implementation
struct SettingsView: View {
    @ObservedObject var store: TransmissionStore
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.appUserDefaults) private var userDefaults

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
    static func resetAllSettings(
        store: TransmissionStore,
        themeManager: ThemeManager = .shared,
        userDefaults: UserDefaults = .standard,
        afterReset: () -> Void = {}
    ) {
        themeManager.setAccentColor(AppDefaults.accentColor)
        themeManager.setThemeMode(AppDefaults.themeMode)

        // Persist AppStorage-backed flags
        userDefaults.set(AppDefaults.showContentTypeIcons, forKey: UserDefaultsKeys.showContentTypeIcons)
        userDefaults.set(AppDefaults.menuBarTransferWidgetEnabled, forKey: UserDefaultsKeys.menuBarTransferWidgetEnabled)
        userDefaults.set(AppDefaults.menuBarShowActiveCount, forKey: UserDefaultsKeys.menuBarShowActiveCount)
        userDefaults.set(AppDefaults.menuBarSortMode.rawValue, forKey: UserDefaultsKeys.menuBarSortMode)
        userDefaults.set(AppDefaults.dockShowCompletedBadge, forKey: UserDefaultsKeys.dockShowCompletedBadge)
        userDefaults.set(AppDefaults.dockShowDownloadSpeed, forKey: UserDefaultsKeys.dockShowDownloadSpeed)
        userDefaults.set(AppDefaults.dockShowUploadSpeed, forKey: UserDefaultsKeys.dockShowUploadSpeed)
        userDefaults.set(AppDefaults.startupConnectionBehavior.rawValue, forKey: UserDefaultsKeys.startupConnectionBehavior)
        #if os(iOS)
        userDefaults.set(AppDefaults.hapticFeedbackEnabled, forKey: UserDefaultsKeys.hapticFeedbackEnabled)
        #endif

        // Poll interval via TransmissionStore API
        store.updatePollInterval(AppDefaults.pollInterval)
        afterReset()
    }

    var body: some View {
        PlatformSettingsView(store: store)
            .environmentObject(themeManager)
            .environment(\.appUserDefaults, userDefaults)
    }
}

// MARK: - Shared Server Configuration Components

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

#if DEBUG
#Preview("Platform Settings") {
    PreviewContainer { environment in
        SettingsView(store: environment.store)
    }
}
#endif
