import Foundation

// Shared helpers between the app and the widget extension.
// Keep broadly useful WidgetKit-related utilities here (e.g., deep links, relevance helpers).

public enum DeepLinkConfig {
    public static let scheme = AppIdentity.urlScheme
    public enum Path { public static let server: String = "server" }
    public enum QueryKey { public static let id: String = "id" }
}

public enum DeepLinkBuilder {
    public static func serverID(from url: URL) -> String? {
        guard url.scheme == DeepLinkConfig.scheme,
              url.host == DeepLinkConfig.Path.server,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let serverID = components.queryItems?.first(where: { $0.name == DeepLinkConfig.QueryKey.id })?.value,
              !serverID.isEmpty else { return nil }
        return serverID
    }

    public static func serverURL(serverId: String) -> URL? {
        var components = URLComponents()
        components.scheme = DeepLinkConfig.scheme
        components.host = DeepLinkConfig.Path.server
        components.queryItems = [URLQueryItem(name: DeepLinkConfig.QueryKey.id, value: serverId)]
        return components.url
    }
}

public enum WidgetKind {
    // Widget kind identifiers shared between app and widget extension
    public static let sessionOverview: String = "SessionOverviewWidget"
}
