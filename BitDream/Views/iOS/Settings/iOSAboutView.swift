#if os(iOS)
import SwiftUI

struct iOSAboutView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.openURL) var openURL

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var copyrightYear: String {
        String(Calendar.current.component(.year, from: Date()))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // App Icon
                Image("AppIconPreview-Default")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 100, height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 6)

                // App Name and Tagline
                VStack(spacing: 4) {
                    Text("BitDream")
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                        .foregroundStyle(.primary)

                    Text("Remote Control for Transmission")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                // Description
                Text("BitDream is a native and feature-rich remote control client for Transmission web server. It provides a modern interface to manage your Transmission server from anywhere.")
                    .font(.system(size: 14))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)

                // Version Information
                VStack(spacing: 2) {
                    HStack(spacing: 8) {
                        Text("Version")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(appVersion)
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundStyle(.primary)
                    }

                    // Copyright
                    Text("© \(copyrightYear) Austin Smith")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 12)
                }

                // Transmission Acknowledgment
                VStack(spacing: 8) {
                    Divider()
                        .padding(.horizontal, 24)

                    HStack(spacing: 4) {
                        Text("Powered by")
                            .font(.system(size: 14))
                            .foregroundStyle(.tertiary)

                        Button("Transmission") {
                            if let url = URL(string: "https://transmissionbt.com/") {
                                openURL(url)
                            }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(themeManager.accentColor)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 32)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationView {
        iOSAboutView()
            .environmentObject(ThemeManager.shared)
    }
}
#endif
