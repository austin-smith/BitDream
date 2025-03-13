import SwiftUI

// Define app themes
struct AppTheme: Identifiable, Equatable {
    var id = UUID()
    var name: String
    var primaryColor: Color
    var secondaryColor: Color
    var accentColor: Color
    var backgroundColor: Color
    var textColor: Color
    
    // Predefined themes
    static let standard = AppTheme(
        name: "Standard",
        primaryColor: .blue,
        secondaryColor: .green,
        accentColor: .orange,
        backgroundColor: Color.primary.opacity(0.05),
        textColor: Color.primary
    )
    
    static let midnight = AppTheme(
        name: "Midnight Dream",
        primaryColor: .purple,
        secondaryColor: .blue,
        accentColor: .pink,
        backgroundColor: Color.black,
        textColor: .white
    )
    
    static let sunset = AppTheme(
        name: "Sunset",
        primaryColor: .orange,
        secondaryColor: .yellow,
        accentColor: .red,
        backgroundColor: Color(red: 0.1, green: 0.1, blue: 0.2),
        textColor: .white
    )
    
    static let forest = AppTheme(
        name: "Forest",
        primaryColor: .green,
        secondaryColor: Color(red: 0.2, green: 0.5, blue: 0.3),
        accentColor: .yellow,
        backgroundColor: Color(red: 0.1, green: 0.2, blue: 0.1),
        textColor: .white
    )
    
    static let ocean = AppTheme(
        name: "Ocean",
        primaryColor: .blue,
        secondaryColor: .cyan,
        accentColor: .teal,
        backgroundColor: Color(red: 0.0, green: 0.1, blue: 0.2),
        textColor: .white
    )
    
    static let allThemes = [standard, midnight, sunset, forest, ocean]
}

// Theme manager class
class ThemeManager: ObservableObject {
    @Published var currentTheme: AppTheme
    
    // Key for storing theme preference
    private let themeKey = "selectedTheme"
    
    init() {
        // Load saved theme or use standard
        if let themeName = UserDefaults.standard.string(forKey: themeKey),
           let savedTheme = AppTheme.allThemes.first(where: { $0.name == themeName }) {
            self.currentTheme = savedTheme
        } else {
            self.currentTheme = AppTheme.standard
        }
    }
    
    func setTheme(_ theme: AppTheme) {
        currentTheme = theme
        UserDefaults.standard.set(theme.name, forKey: themeKey)
    }
}

// Environment key for theme
struct ThemeKey: EnvironmentKey {
    static let defaultValue: AppTheme = AppTheme.standard
}

extension EnvironmentValues {
    var theme: AppTheme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

// Theme picker view
struct ThemePicker: View {
    @ObservedObject var themeManager: ThemeManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                ForEach(AppTheme.allThemes) { theme in
                    Button(action: {
                        themeManager.setTheme(theme)
                    }) {
                        HStack {
                            Text(theme.name)
                                .foregroundColor(theme.textColor)
                            
                            Spacer()
                            
                            if themeManager.currentTheme.name == theme.name {
                                Image(systemName: "checkmark")
                                    .foregroundColor(theme.accentColor)
                            }
                            
                            // Theme color preview
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(theme.primaryColor)
                                    .frame(width: 16, height: 16)
                                Circle()
                                    .fill(theme.secondaryColor)
                                    .frame(width: 16, height: 16)
                                Circle()
                                    .fill(theme.accentColor)
                                    .frame(width: 16, height: 16)
                            }
                        }
                        .padding(.vertical, 8)
                        .listRowBackground(theme.backgroundColor)
                    }
                }
            }
            .navigationTitle("Choose Theme")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// Preview
#Preview {
    ThemePicker(themeManager: ThemeManager())
} 
