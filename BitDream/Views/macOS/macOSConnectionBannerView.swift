import SwiftUI

#if os(macOS)
struct macOSConnectionBannerView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var store: TransmissionStore

    var body: some View {
        HStack(spacing: 12) {
            ConnectionStatusIndicator(status: store.connectionStatus, isAttempting: store.connectionState.isAttempting)
            VStack(alignment: .leading, spacing: 2) {
                Text(store.connectionTitle)
                    .font(.subheadline.weight(.semibold))
                ConnectionRetryStatusView(state: store.connectionState)
                if !store.lastErrorMessage.isEmpty {
                    Text(store.lastErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            if store.needsConnectionSettings {
                Button("Settings") { openWindow(id: "manage-servers") }
                    .buttonStyle(.bordered)
            }
            Button("Connection Info") {
                openWindow(id: "connection-info")
            }
            .buttonStyle(.bordered)
            .help("Open Connection Info window")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}
#endif

#if os(macOS) && DEBUG
#Preview("macOS Reconnecting Banner", traits: .fixedLayout(width: 720, height: 70)) {
    PreviewContainer(scenario: .reconnecting) { environment in
        macOSConnectionBannerView(store: environment.store)
    }
}
#endif
