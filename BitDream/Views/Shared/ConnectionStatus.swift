import Foundation
import SwiftUI

enum ConnectionRetryTextStyle {
    case verbose
    case compact
}

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
