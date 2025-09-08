import Foundation
import SwiftUI

// Centralized application configuration and defaults
enum RatioDisplayMode: String {
    case cumulative
    case current
}

enum AppDefaults {
    static let accentColor: AccentColorOption = .blue
    static let themeMode: ThemeMode = .system
    static let showContentTypeIcons: Bool = true
    static let pollInterval: Double = 5.0
    static let ratioDisplayMode: RatioDisplayMode = .cumulative
}

enum UserDefaultsKeys {
    static let pollInterval = "pollIntervalKey"
    static let showContentTypeIcons = "showContentTypeIcons"
    static let ratioDisplayMode = "ratioDisplayMode"
}
