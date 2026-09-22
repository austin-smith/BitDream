import Foundation
import SwiftUI

enum ConnectionRetryTextStyle {
    case verbose
    case compact
}

struct ConnectionRetryStatusView: View {
    @Environment(\.presentationDate) private var presentationDate
    let state: TransmissionConnectionState

    var body: some View {
        Group {
            switch state {
            case .retrying:
                Text("Retrying…")
            case .failed(_, let retryAt?):
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(connectionRetryText(status: .reconnecting, retryAt: retryAt, at: presentationDate ?? context.date))
                        .monospacedDigit()
                }
            default:
                EmptyView()
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
}

struct ConnectionStatusIndicator: View {
    let status: TransmissionStore.ConnectionStatus
    let isAttempting: Bool

    var body: some View {
        Group {
            if isAttempting {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.small)
                    .tint(connectionStatusColor(for: status))
                    .accessibilityLabel(status == .connecting ? "Connecting" : "Retrying")
            } else {
                Image(systemName: connectionStatusSymbol(for: status))
                    .foregroundStyle(connectionStatusColor(for: status))
                    .font(.system(size: 16, weight: .semibold))
                    .accessibilityHidden(true)
            }
        }
        .frame(width: 20, height: 20)
    }
}

#if DEBUG
#Preview("Connection activity") {
    HStack(spacing: 20) {
        ConnectionStatusIndicator(status: .connecting, isAttempting: true)
        ConnectionStatusIndicator(status: .reconnecting, isAttempting: true)
        ConnectionStatusIndicator(status: .reconnecting, isAttempting: false)
    }
    .padding()
}
#endif

func connectionStatusSymbol(for status: TransmissionStore.ConnectionStatus) -> String {
    switch status {
    case .connecting:
        return "arrow.trianglehead.2.clockwise"
    case .connected:
        return "checkmark.circle.fill"
    case .reconnecting:
        return "wifi.exclamationmark"
    }
}

func connectionStatusColor(for status: TransmissionStore.ConnectionStatus) -> Color {
    switch status {
    case .connecting:
        return .blue
    case .connected:
        return .green
    case .reconnecting:
        return .orange
    }
}

func connectionRetryText(
    status: TransmissionStore.ConnectionStatus,
    retryAt: Date?,
    at date: Date,
    style: ConnectionRetryTextStyle = .verbose
) -> String {
    switch style {
    case .verbose:
        if status == .connecting {
            return "Connecting..."
        }
        guard let retryAt else { return "" }
        let remaining = max(0, Int(retryAt.timeIntervalSince(date)))
        if remaining > 0 {
            return "Next retry in \(remaining)s"
        }
        return "Retrying now..."

    case .compact:
        guard let retryAt else {
            return "—"
        }
        let remaining = max(0, Int(retryAt.timeIntervalSince(date)))
        if remaining > 0 {
            return "\(remaining)s"
        }
        return "—"
    }
}
