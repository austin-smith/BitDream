import SwiftUI

#if os(iOS)
struct iOSConnectionBannerView: View {
    @Environment(\.hapticFeedback) private var hapticFeedback
    @ObservedObject var store: TransmissionStore

    private var shouldShowLastError: Bool {
        store.connectionStatus == .reconnecting && !store.lastErrorMessage.isEmpty
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ConnectionStatusIndicator(status: store.connectionStatus, isAttempting: store.connectionState.isAttempting)

            VStack(alignment: .leading, spacing: 2) {
                Text(store.connectionTitle)
                    .font(.subheadline.weight(.semibold))

                ConnectionRetryStatusView(state: store.connectionState)
                if shouldShowLastError {
                    Text(store.lastErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()

            if store.needsConnectionSettings {
                Button("Settings") { store.editServers = true }
                    .buttonStyle(.bordered)
            } else if store.connectionState.failure != nil {
                Button("Retry") {
                    hapticFeedback.play(.actionTriggered)
                    store.retryNow()
                }
                .buttonStyle(.bordered)
                .disabled(!store.canAttemptReconnect)
            }
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

#if os(iOS) && DEBUG
#Preview("iOS Reconnecting Banner", traits: .sizeThatFitsLayout) {
    PreviewContainer(scenario: .reconnecting) { environment in
        iOSConnectionBannerView(store: environment.store)
            .frame(width: 420)
    }
}
#endif
