import SwiftUI
import Foundation

/// Platform-agnostic wrapper for SettingsView
/// This view simply delegates to the appropriate platform-specific implementation
struct SettingsView: View {
    @ObservedObject var store: TransmissionStore

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
    static func resetAllSettings(store: TransmissionStore, afterReset: () -> Void = {}) {
        let theme = ThemeManager.shared
        theme.setAccentColor(AppDefaults.accentColor)
        theme.setThemeMode(AppDefaults.themeMode)

        // Persist AppStorage-backed flags
        UserDefaults.standard.set(AppDefaults.showContentTypeIcons, forKey: UserDefaultsKeys.showContentTypeIcons)
        UserDefaults.standard.set(AppDefaults.menuBarTransferWidgetEnabled, forKey: UserDefaultsKeys.menuBarTransferWidgetEnabled)
        UserDefaults.standard.set(AppDefaults.menuBarSortMode.rawValue, forKey: UserDefaultsKeys.menuBarSortMode)
        UserDefaults.standard.set(AppDefaults.startupConnectionBehavior.rawValue, forKey: UserDefaultsKeys.startupConnectionBehavior)

        // Poll interval via TransmissionStore API
        store.updatePollInterval(AppDefaults.pollInterval)
        afterReset()
    }

    var body: some View {
        PlatformSettingsView(store: store)
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

#Preview {
    SettingsView(store: TransmissionStore())
}
