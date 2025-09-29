#if os(iOS)
import Foundation

/// Presentation model for an app icon choice.
public struct AppIconPresentation {
    /// CFBundleAlternateIcons key; nil means primary/default icon
    public let key: String?
    /// Friendly title you control
    public let title: String
    /// Name of preview image in the main app asset catalog
    public let previewAssetName: String
    /// Ordering hint (lower first)
    public let order: Int

    public init(key: String?, title: String, previewAssetName: String, order: Int) {
        self.key = key
        self.title = title
        self.previewAssetName = previewAssetName
        self.order = order
    }
}

/// Single source of truth for app icon names and preview assets (iOS-only).
public enum AppIconCatalog {
    public static let entries: [AppIconPresentation] = [
        AppIconPresentation(key: nil, title: "Byte-sized Dreams", previewAssetName: "AppIconPreview-Default", order: 0),
        AppIconPresentation(key: "BitDreamAppIconPink", title: "Blue Clouds", previewAssetName: "AppIconPreview-Blue", order: 10),
        AppIconPresentation(key: "BitDreamAppIconPinkBg", title: "Pink Sky", previewAssetName: "AppIconPreview-PinkBG", order: 20),
        AppIconPresentation(key: "BitDreamAppIconPixelyClouds", title: "Cloudy Day", previewAssetName: "AppIconPreview-PixelyClouds", order: 30),
        AppIconPresentation(key: "AppIcon-OG", title: "The O.G.", previewAssetName: "AppIconPreview-OG", order: 40)
    ]

    // Return the icons exactly as defined in `entries`
    public static func presentations() -> [AppIconPresentation] {
        var result: [AppIconPresentation] = []
        // Default first (use provided default if present, otherwise fallback)
        if let def = entries.first(where: { $0.key == nil }) {
            result.append(def)
        } else {
            result.append(AppIconPresentation(key: nil, title: "Default", previewAssetName: "AppIconPreview-Default", order: Int.min))
        }

        // Then all alternates exactly as defined
        result.append(contentsOf: entries.filter { $0.key != nil })

        return result.sorted { lhs, rhs in
            if lhs.order != rhs.order { return lhs.order < rhs.order }
            switch (lhs.key, rhs.key) {
            case (nil, nil): return false
            case (nil, _): return true
            case (_, nil): return false
            case let (l?, r?): return l < r
            }
        }
    }
}
#endif
