import SwiftUI
#if os(macOS)
import AppKit
#endif

#if os(macOS)
struct macOSMenuBarTransferWidget: View {
    @EnvironmentObject private var store: Store
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    private let panelWidth: CGFloat = 380
    private let maxListHeight: CGFloat = 320

    private var activeTransfers: [Torrent] {
        store.torrents.sortedActiveTransfersByActivity()
    }

    private var summary: MenuBarTransferSummary {
        menuBarSummary(from: store)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if store.host == nil {
                noServerState
            } else {
                connectionState

                if activeTransfers.isEmpty {
                    emptyState
                } else {
                    transfersList
                }
            }

            footer
        }
        .padding(12)
        .frame(width: panelWidth)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: connectionStatusSymbol(store.connectionStatus))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(connectionStatusColor(store.connectionStatus))

                Text(summary.serverName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)

                Spacer(minLength: 0)

                Text("\(summary.activeCount) active")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                SpeedChip(speed: summary.downloadSpeed, direction: .download, style: .chip, size: .compact)
                SpeedChip(speed: summary.uploadSpeed, direction: .upload, style: .chip, size: .compact)
                RatioChip(ratio: summary.ratio, size: .compact)
                Spacer(minLength: 0)
            }
        }
    }

    private var connectionState: some View {
        Group {
            if store.connectionStatus != .connected {
                HStack(spacing: 8) {
                    Image(systemName: connectionStatusSymbol(store.connectionStatus))
                        .foregroundStyle(connectionStatusColor(store.connectionStatus))
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(connectionBannerText(at: context.date))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.orange.opacity(0.12))
                )
            }
        }
    }

    private var transfersList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(activeTransfers, id: \.id) { torrent in
                    macOSMenuBarTransferRow(torrent: torrent) {
                        openAppWindow(id: "main")
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .frame(maxHeight: maxListHeight)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No active transfers")
                .font(.system(size: 12, weight: .semibold))
            Text("Downloads, metadata retrieval, seeding, and verification appear here.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    private var noServerState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No server selected")
                .font(.system(size: 12, weight: .semibold))

            Text("Open BitDream and add or select a server to view active transfers.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button("Open BitDream") {
                    openAppWindow(id: "main")
                }
                .buttonStyle(.borderedProminent)

                Button("Settings") {
                    openSettings()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button("Open BitDream") {
                openAppWindow(id: "main")
            }

            Button("Refresh Now") {
                refreshTransmissionData(store: store)
            }

            Spacer(minLength: 0)
        }
        .font(.system(size: 11))
    }

    private func connectionBannerText(at date: Date) -> String {
        if store.connectionStatus == .connecting {
            return "Connecting..."
        }
        guard let retryAt = store.nextRetryAt else { return "Retrying now..." }
        let remaining = max(0, Int(retryAt.timeIntervalSince(date)))
        if remaining > 0 {
            return "Next retry in \(remaining)s"
        }
        return "Retrying now..."
    }

    private func openAppWindow(id: String) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: id)
    }

    private func connectionStatusColor(_ status: Store.ConnectionStatus) -> Color {
        switch status {
        case .connecting:
            return .blue
        case .connected:
            return .green
        case .reconnecting:
            return .orange
        }
    }

    private func connectionStatusSymbol(_ status: Store.ConnectionStatus) -> String {
        switch status {
        case .connecting:
            return "arrow.trianglehead.2.clockwise"
        case .connected:
            return "checkmark.circle.fill"
        case .reconnecting:
            return "wifi.exclamationmark"
        }
    }
}

struct macOSMenuBarExtraLabel: View {
    var body: some View {
        Image("MenuBarIcon")
            .renderingMode(.template)
        .help("BitDream Transfers")
    }
}

#endif
