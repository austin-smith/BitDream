import SwiftUI

#if os(macOS)
struct macOSConnectionBannerView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var store: TransmissionStore

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: connectionStatusSymbol(for: store.connectionStatus))
                .foregroundStyle(connectionStatusColor(for: store.connectionStatus))
                .font(.system(size: 16, weight: .semibold))
            VStack(alignment: .leading, spacing: 2) {
                Text(store.connectionTitle)
                    .font(.subheadline.weight(.semibold))
                if store.nextRetryAt != nil {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(
                            connectionRetryText(
                                status: store.connectionStatus,
                                retryAt: store.nextRetryAt,
                                at: context.date
                            )
                        )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
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
