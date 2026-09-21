import Foundation

/// Build-time identity shared by the app and its widget extension.
/// Configuration files supply these values independently of compiler optimization.
enum AppIdentity {
    enum Variant: String {
        case development
        case release
    }

    static let variant: Variant = {
        let value = requiredString("BitDreamVariant")
        guard let variant = Variant(rawValue: value) else {
            fatalError("Invalid BitDreamVariant: \(value)")
        }
        return variant
    }()

    static let bundleIdentifier = requiredString("CFBundleIdentifier")
    static let displayName = requiredString("BitDreamAppName")
    static let appGroupIdentifier = requiredString("BitDreamAppGroup")
    static let urlScheme = requiredString("BitDreamURLScheme")
    static let version = requiredString("CFBundleShortVersionString")
    static let buildNumber = requiredString("CFBundleVersion")

    static var isDevelopment: Bool { variant == .development }
    static var versionDescription: String { "\(version) (\(buildNumber))" }

    private static func requiredString(_ key: String) -> String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty, !value.contains("$(") else {
            fatalError("Missing or unresolved \(key) in the built bundle.")
        }
        return value
    }
}
