import SwiftUI
import Foundation
import KeychainAccess

/// Platform-agnostic wrapper for SettingsView
/// This view simply delegates to the appropriate platform-specific implementation
struct SettingsView: View {
    var body: some View {
        #if os(iOS)
        iOSSettingsView()
        #elseif os(macOS)
        macOSSettingsView()
        #endif
    }
}

#Preview {
    SettingsView()
} 