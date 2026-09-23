import Foundation
import SwiftUI
import XCTest
@testable import BitDream

@MainActor
final class ThemeManagerTests: XCTestCase {
    func testSettingsBindingPersistsEveryAppearance() throws {
        let suite = "ThemeManagerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let manager = ThemeManager(userDefaults: defaults)

        for mode in [ThemeMode.light, .dark, .system] {
            manager.themeMode = mode
            XCTAssertEqual(ThemeManager(userDefaults: defaults).themeMode, mode)
        }
    }

    func testRetiringAccentPreferencePreservesAppearanceAndOtherSettings() throws {
        let suite = "ThemeManagerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("#f8b7cd", forKey: "accentColorKey")
        defaults.set("Dark", forKey: "themeModeKey")
        defaults.set(true, forKey: "unrelatedSetting")

        let manager = ThemeManager(userDefaults: defaults)

        XCTAssertNil(defaults.object(forKey: "accentColorKey"))
        XCTAssertEqual(manager.themeMode, .dark)
        XCTAssertTrue(defaults.bool(forKey: "unrelatedSetting"))
        manager.cycleThemeMode()
        XCTAssertEqual(ThemeManager(userDefaults: defaults).themeMode, .system)
    }

    func testAccentAssetPreservesOriginalBlueInBothAppearances() {
        for scheme in [ColorScheme.light, .dark] {
            var environment = EnvironmentValues()
            environment.colorScheme = scheme
            let accent = Color("AccentColor", bundle: Bundle(for: ThemeManager.self))
                .resolve(in: environment)
            let original = Color(.sRGB, red: 0.404, green: 0.639, blue: 0.851, opacity: 1)
                .resolve(in: environment)
            XCTAssertEqual(accent.red, original.red, accuracy: 0.0001)
            XCTAssertEqual(accent.green, original.green, accuracy: 0.0001)
            XCTAssertEqual(accent.blue, original.blue, accuracy: 0.0001)
            XCTAssertEqual(accent.opacity, original.opacity)
        }
    }
}
