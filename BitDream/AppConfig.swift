import Foundation
import SwiftUI

// Centralized application configuration and defaults
enum AppDefaults {
    static let accentColor: AccentColorOption = .blue
    static let themeMode: ThemeMode = .system
    static let showContentTypeIcons: Bool = true
    static let pollInterval: Double = 5.0
}

enum UserDefaultsKeys {
    static let pollInterval = "pollIntervalKey"
    static let showContentTypeIcons = "showContentTypeIcons"
}
