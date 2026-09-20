import SwiftUI

struct TailscaleServerHelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    helpSection("1. Set up Tailscale") {
                        Text("Your Transmission server must be connected to your Tailscale network.")
                        Link("Tailscale server setup", destination: URL(string: "https://tailscale.com/docs/quickstart")!)
                    }
                    helpSection("2. Enable Transmission remote access") {
                        Text("Enable remote access in Transmission. Note the port and any required username and password.")
                    }
                    helpSection("3. Add the server in BitDream") {
                        Text("Choose Tailscale and sign in. Select your server or enter its Tailscale address, then enter the port and credentials. Select Test Connection to check your settings.")
                        Text("Turn on Use SSL if your server uses HTTPS.")
                    }
                    helpSection("Privacy") {
                        Text("BitDream registers its own device with Tailscale and shares the connection metadata needed to reach your server. Diagnostic log uploads are disabled.")
                        Link("Tailscale Privacy Policy", destination: URL(string: "https://tailscale.com/privacy-policy")!)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
            .navigationTitle("Tailscale Server Setup")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, idealWidth: 600, minHeight: 400, idealHeight: 600)
        #endif
    }

    private func helpSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .lineLimit(nil)
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#if DEBUG
#Preview("Tailscale Server Setup") {
    TailscaleServerHelpView()
}
#endif
