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

enum MenuBarSortMode: String, CaseIterable {
    case activity
    case name
    case eta

    var label: String {
        switch self {
        case .activity:
            return "Activity"
        case .name:
            return "Name"
        case .eta:
            return "ETA"
        }
    }
}

enum AppDefaults {
    static let accentColor: AccentColorOption = .blue
    static let themeMode: ThemeMode = .system
    static let showContentTypeIcons: Bool = true
    static let menuBarTransferWidgetEnabled: Bool = true
    static let menuBarSortMode: MenuBarSortMode = .activity
    static let pollInterval: Double = 5.0
    static let ratioDisplayMode: RatioDisplayMode = .cumulative
    static let startupConnectionBehavior: StartupConnectionBehavior = .lastUsed
}

enum AppIdentity {
    static let bundleIdentifier: String = {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier, !bundleIdentifier.isEmpty else {
            fatalError("Missing CFBundleIdentifier on main bundle.")
        }
        return bundleIdentifier
    }()
}

enum UserDefaultsKeys {
    static let pollInterval = "pollInterval"
    static let torrentListCompactMode = "torrentListCompactMode"
    static let showContentTypeIcons = "showContentTypeIcons"
    static let menuBarTransferWidgetEnabled = "menuBarTransferWidgetEnabled"
    static let menuBarSortMode = "menuBarSortMode"
    static let ratioDisplayMode = "ratioDisplayMode"
    static let selectedHost = "selectedHost"
    static let startupConnectionBehavior = "startupConnectionBehavior"
    static let persistenceSchemaVersion = "persistenceSchemaVersion"
}
