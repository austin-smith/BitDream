import SwiftUI
import Foundation

// Define available theme modes
enum ThemeMode: String, CaseIterable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"
}

// Theme manager class
@MainActor
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    @Published var themeMode: ThemeMode {
        didSet {
            userDefaults.set(themeMode.rawValue, forKey: themeModeKey)
        }
    }

    private let themeModeKey = "themeModeKey"
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.themeMode = userDefaults.string(forKey: themeModeKey)
            .flatMap(ThemeMode.init(rawValue:)) ?? .system
        userDefaults.removeObject(forKey: "accentColorKey")
    }

    func setThemeMode(_ mode: ThemeMode) {
        themeMode = mode
    }

    func cycleThemeMode() {
        switch themeMode {
        case .system:
            setThemeMode(.light)
        case .light:
            setThemeMode(.dark)
        case .dark:
            setThemeMode(.system)
        }
    }

    // Helper to convert ThemeMode to ColorScheme
    func colorScheme() -> ColorScheme? {
        switch themeMode {
        case .light:
            return .light
        case .dark:
            return .dark
        case .system:
            return nil
        }
    }

}

// View modifier for immediate theme application
struct ImmediateThemeModifier: ViewModifier {
    @ObservedObject var themeManager: ThemeManager

    func body(content: Content) -> some View {
        content
            .preferredColorScheme(themeManager.colorScheme())
            .animation(.none, value: themeManager.themeMode)
    }
}

extension View {
    func immediateTheme(manager: ThemeManager) -> some View {
        modifier(ImmediateThemeModifier(themeManager: manager))
    }
}
