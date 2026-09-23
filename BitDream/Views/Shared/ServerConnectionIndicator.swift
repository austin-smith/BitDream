import SwiftUI

/// Compact status for the current server. Saved, inactive servers have no known status.
struct ServerConnectionIndicator: View {
    let state: TransmissionConnectionState
    @ScaledMetric private var dotSize: CGFloat

    init(state: TransmissionConnectionState, size: CGFloat = 6) {
        self.state = state
        _dotSize = ScaledMetric(wrappedValue: size, relativeTo: .body)
    }

    var body: some View {
        Circle()
            .fill(statusColor)
            .frame(width: dotSize, height: dotSize)
            .help(state.serverStatusLabel)
            // The containing row announces its status as an accessibility value.
            .accessibilityHidden(true)
    }

    private var statusColor: Color {
        switch state {
        case .connected: .green
        case .connecting, .retrying: .orange
        case .failed, .requiresAction: .red
        }
    }
}

extension TransmissionConnectionState {
    var serverStatusLabel: String {
        switch self {
        case .connected: "Connected"
        case .connecting: "Connecting…"
        case .retrying: "Retrying…"
        case .failed(_, .some): "Connection failed, waiting to retry"
        case .failed(_, .none): "Connection failed"
        case .requiresAction: "Connection needs attention"
        }
    }
}

#if DEBUG
#Preview("Server connection states") {
    VStack(alignment: .leading) {
        ForEach(Array([
            TransmissionConnectionState.connected,
            .connecting,
            .retrying(.timeout),
            .failed(.timeout, retryAt: .now),
            .failed(.timeout, retryAt: nil),
            .requiresAction(.unauthorized)
        ].enumerated()), id: \.offset) { _, state in
            HStack {
                Image(systemName: "server.rack")
                    .overlay(alignment: .topTrailing) {
                        ServerConnectionIndicator(state: state)
                    }
                Text(state.serverStatusLabel)
            }
        }
    }
    .padding()
}
#endif
