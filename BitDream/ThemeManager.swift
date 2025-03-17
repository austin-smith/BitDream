import SwiftUI
import Foundation

// Define the available accent colors
enum AccentColorOption: String, CaseIterable, Identifiable {
    case blue = "#0671b7"
    case pink = "#f8b7cd"
    case lightBlue = "#67a3d9"
    case lightPink = "#fdd0e0"
    case paleBlue = "#c8e7f5"
    
    var id: String { self.rawValue }
    
    var name: String {
        switch self {
        case .blue: return "Blue"
        case .pink: return "Pink"
        case .lightBlue: return "Light Blue"
        case .lightPink: return "Light Pink"
        case .paleBlue: return "Pale Blue"
        }
    }
    
    var color: Color {
        Color(hex: self.rawValue)
    }
    
    static var defaultColor: AccentColorOption {
        return .blue
    }
}

// Define available theme modes
enum ThemeMode: String, CaseIterable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"
}

// Theme manager class
class ThemeManager: ObservableObject {
    static let shared = ThemeManager()
    
    @Published var accentColor: Color
    @Published var currentAccentColorOption: AccentColorOption
    @Published var themeMode: ThemeMode
    
    // Keys for storing preferences
    private let accentColorKey = "accentColorKey"
    private let themeModeKey = "themeModeKey"
    
    init() {
        // Load saved accent color from UserDefaults or use default
        let savedHex = UserDefaults.standard.string(forKey: accentColorKey) ?? AccentColorOption.defaultColor.rawValue
        
        // Initialize with default values first
        self.currentAccentColorOption = .blue
        self.accentColor = Color(hex: AccentColorOption.defaultColor.rawValue)
        
        // Load saved theme mode or use system default
        if let savedThemeMode = UserDefaults.standard.string(forKey: themeModeKey),
           let mode = ThemeMode(rawValue: savedThemeMode) {
            self.themeMode = mode
        } else {
            self.themeMode = .system
        }
        
        // Then update accent color if we have a saved value
        if let option = AccentColorOption.allCases.first(where: { $0.rawValue == savedHex }) {
            self.currentAccentColorOption = option
            self.accentColor = option.color
        }
    }
    
    func setAccentColor(_ option: AccentColorOption) {
        self.currentAccentColorOption = option
        self.accentColor = option.color
        
        // Save to UserDefaults
        UserDefaults.standard.set(option.rawValue, forKey: accentColorKey)
    }
    
    func setThemeMode(_ mode: ThemeMode) {
        self.themeMode = mode
        
        // Save to UserDefaults
        UserDefaults.standard.set(mode.rawValue, forKey: themeModeKey)
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
    
    func setAccentColorFromHex(_ hex: String) {
        if let option = AccentColorOption.allCases.first(where: { $0.rawValue == hex }) {
            setAccentColor(option)
        } else {
            // If hex doesn't match any predefined option, create a custom color
            self.accentColor = Color(hex: hex)
            UserDefaults.standard.set(hex, forKey: accentColorKey)
        }
    }
}

// Extension to create Color from hex string
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
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
