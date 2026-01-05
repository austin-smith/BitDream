#if os(macOS)
import SwiftUI

struct macOSAboutView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.openURL) var openURL

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    private var copyrightYear: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy"
        return formatter.string(from: Date())
    }

    var body: some View {
        VStack(spacing: 12) {
            // App Icon and Title
            VStack(spacing: 12) {
                // App Icon
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 128, height: 128)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 6)

                // App Name and Tagline
                VStack(spacing: 4) {
                    Text("BitDream")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text("Remote Control for Transmission")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            // Description
            VStack(spacing: 16) {
                Text("BitDream is a native and feature-rich remote control client for Transmission web server. It provides a modern interface to manage your Transmission server from anywhere.")
                    .font(.system(size: 11))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)

                // Version Information - Ghostty style
                VStack(spacing: 2) {
                    HStack(spacing: 8) {
                        Text("Version")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(appVersion)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.primary)
                    }

                    // Copyright
                    Text("© \(copyrightYear) Austin Smith")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 12)
                }
            }

            // Transmission Acknowledgment - cleaner integration
            VStack(spacing: 8) {
                Divider()
                    .padding(.horizontal, 24)

                HStack(spacing: 4) {
                    Text("Powered by")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)

                    Button("Transmission") {
                        if let url = URL(string: "https://transmissionbt.com/") {
                            openURL(url)
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(themeManager.accentColor)
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 0))
    }
}

#endif
