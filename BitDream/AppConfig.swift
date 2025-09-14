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

// MARK: - Deep Link Config
enum DeepLinkConfig {
    static let scheme: String = "bitdream"
    enum Path {
        static let server: String = "server"
    }
    enum QueryKey {
        static let id: String = "id"
    }
}

enum DeepLinkBuilder {
    static func serverURL(serverId: String) -> URL? {
        var components = URLComponents()
        components.scheme = DeepLinkConfig.scheme
        components.host = DeepLinkConfig.Path.server
        components.queryItems = [URLQueryItem(name: DeepLinkConfig.QueryKey.id, value: serverId)]
        return components.url
    }
}

enum UserDefaultsKeys {
    static let pollInterval = "pollInterval"
    static let torrentListCompactMode = "torrentListCompactMode"
    static let showContentTypeIcons = "showContentTypeIcons"
    static let ratioDisplayMode = "ratioDisplayMode"
    static let selectedHost = "selectedHost"
    static let startupConnectionBehavior = "startupConnectionBehavior"
}
