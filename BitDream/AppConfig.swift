import Foundation
import SwiftUI

// Centralized application configuration and defaults
enum RatioDisplayMode: String {
    case cumulative
    case current
}

// Add startup behavior configuration
enum StartupConnectionBehavior: String, CaseIterable {
    case lastUsed
    case defaultServer
}

enum AppDefaults {
    static let accentColor: AccentColorOption = .blue
    static let themeMode: ThemeMode = .system
    static let showContentTypeIcons: Bool = true
    static let pollInterval: Double = 5.0
    static let ratioDisplayMode: RatioDisplayMode = .cumulative
    static let startupConnectionBehavior: StartupConnectionBehavior = .lastUsed
}

enum UserDefaultsKeys {
    static let pollInterval = "pollInterval"
    static let torrentListCompactMode = "torrentListCompactMode"
    static let showContentTypeIcons = "showContentTypeIcons"
    static let ratioDisplayMode = "ratioDisplayMode"
    static let selectedHost = "selectedHost"
    static let startupConnectionBehavior = "startupConnectionBehavior"
}
