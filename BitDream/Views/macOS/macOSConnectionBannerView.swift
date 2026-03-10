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
                Text(connectionStatusTitle(for: store.connectionStatus))
                    .font(.subheadline.weight(.semibold))
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
            Spacer()
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
