import SwiftUI
import Foundation

#if os(macOS)
struct macOSSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showingThemeSettings = false
    
    var body: some View {
        // macOS version with custom styling to match the screenshot
        VStack(spacing: 0) {
            // Header
            Text("Settings")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 12)
                .background(Color(white: 0.25))
            
            // Content
            VStack(alignment: .leading, spacing: 16) {
                // Appearance section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Appearance")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    HStack(spacing: 8) {
                        Button("Theme Settings") {
                            // Disabled for now
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(true)
                        
                        Text("Coming Soon")
                            .font(.caption2)
                            .foregroundColor(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.2))
                            .cornerRadius(4)
                    }
                }
                
                Divider()
                    .background(Color.gray.opacity(0.5))
                
                // About section
                VStack(alignment: .leading, spacing: 8) {
                    Text("About")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                            .foregroundColor(.gray)
                    }
                }
                
                Spacer()
                
                // Done button
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 8)
            }
            .padding()
            .frame(width: 400)
            .background(Color(white: 0.2))
        }
        .background(Color(white: 0.2))
        .cornerRadius(8)
    }
}

#Preview {
    macOSSettingsView()
}
#else
// Empty struct for iOS to reference - this won't be compiled on iOS but provides the type
struct macOSSettingsView: View {
    var body: some View {
        EmptyView()
    }
}
#endif 