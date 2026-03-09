import SwiftUI

#if os(iOS)
struct iOSConnectionBannerView: View {
    @ObservedObject var store: TransmissionStore

    private var shouldShowLastError: Bool {
        store.connectionStatus == .reconnecting && !store.lastErrorMessage.isEmpty
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
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
                }

                if shouldShowLastError {
                    Text(store.lastErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            Button("Retry") {
                store.reconnect()
            }
            .buttonStyle(.bordered)
            .disabled(!store.canAttemptReconnect)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Divider()
        }
        .accessibilityElement(children: .combine)
    }
}
#endif
