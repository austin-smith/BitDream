#if BITDREAM_SAMPLE_SUPPORT
import SwiftUI

/// Optional capture presentation, applied by the composition root to a demo session.
/// DemoSession itself has no dependency on screenshot configuration.
struct ScreenshotConfiguration {
    let appearance: ThemeMode
    let compact: Bool
    var referenceDate: Date { SampleLibrary.referenceDate }
    var windowSize: CGSize { CGSize(width: 1200, height: 900) }
    var dynamicTypeSize: DynamicTypeSize { .large }

    enum ConfigurationError: Error { case requiresDemo, unknownAppearance(String) }

    static func fromProcess(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> Self? {
        guard AppIdentity.isDevelopment, environment["BITDREAM_SCREENSHOT"] == "1" else { return nil }
        guard environment["BITDREAM_DEMO"] == "1" else { throw ConfigurationError.requiresDemo }
        let name = environment["BITDREAM_SCREENSHOT_APPEARANCE"] ?? "light"
        guard ["light", "dark"].contains(name) else { throw ConfigurationError.unknownAppearance(name) }
        return Self(appearance: name == "dark" ? .dark : .light,
                    compact: environment["BITDREAM_SCREENSHOT_COMPACT"] == "1")
    }

    func makeUserDefaults(suiteName: String = "\(AppIdentity.bundleIdentifier).screenshots") -> UserDefaults {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Unable to create screenshot preferences.")
        }
        defaults.removePersistentDomain(forName: suiteName)
        defaults.registerViewStateDefaults()
        defaults.set(appearance.rawValue, forKey: "themeModeKey")
        defaults.set(compact, forKey: UserDefaultsKeys.torrentListCompactMode)
        defaults.set(false, forKey: "inspectorVisibility")
        defaults.set(false, forKey: UserDefaultsKeys.menuBarTransferWidgetEnabled)
        return defaults
    }
}
#endif
