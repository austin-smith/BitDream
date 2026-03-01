import SwiftUI

#if os(macOS)
struct macOSMenuBarTransferWidget: View {
    @EnvironmentObject private var store: Store
    @State private var transferRowsHeight: CGFloat = 0
    let onOpenMainWindow: () -> Void
    let onOpenSettingsWindow: () -> Void

    private let panelWidth: CGFloat = 380
    private let maxListHeight: CGFloat = 320
    private let estimatedRowHeight: CGFloat = 74

    init(
        onOpenMainWindow: @escaping () -> Void = {},
        onOpenSettingsWindow: @escaping () -> Void = {}
    ) {
        self.onOpenMainWindow = onOpenMainWindow
        self.onOpenSettingsWindow = onOpenSettingsWindow
    }

    private var activeTransfers: [Torrent] {
        store.torrents.sortedActiveTransfersByActivity()
    }

    private var summary: MenuBarTransferSummary {
        menuBarSummary(from: store, activeTransfers: activeTransfers)
    }

    private var estimatedTransferListHeight: CGFloat {
        let estimatedRowsHeight = CGFloat(activeTransfers.count) * estimatedRowHeight + 4
        return min(max(estimatedRowsHeight, 1), maxListHeight)
    }

    private var clampedTransferListHeight: CGFloat {
        let measured = transferRowsHeight
        let fallback = estimatedTransferListHeight
        let resolvedHeight = measured > 1 ? measured : fallback
        return min(max(resolvedHeight, 1), maxListHeight)
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
                Image(systemName: connectionStatusSymbol(for: store.connectionStatus))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(connectionStatusColor(for: store.connectionStatus))

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
                    Image(systemName: connectionStatusSymbol(for: store.connectionStatus))
                        .foregroundStyle(connectionStatusColor(for: store.connectionStatus))
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(connectionRetryText(status: store.connectionStatus, retryAt: store.nextRetryAt, at: context.date))
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
            transferRows
        }
        .frame(height: clampedTransferListHeight)
        .onPreferenceChange(TransferRowsHeightPreferenceKey.self) { transferRowsHeight = $0 }
    }

    private var transferRows: some View {
        LazyVStack(spacing: 8) {
            ForEach(activeTransfers, id: \.id) { torrent in
                macOSMenuBarTransferRow(torrent: torrent) {
                    openMainWindow()
                }
            }
        }
        .padding(.vertical, 2)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: TransferRowsHeightPreferenceKey.self, value: proxy.size.height)
            }
        }
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
                    openMainWindow()
                }
                .buttonStyle(.borderedProminent)

                Button("Settings") {
                    onOpenSettingsWindow()
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
            Button {
                openMainWindow()
            } label: {
                Label("Open BitDream", systemImage: "arrow.up.forward.app")
            }

            Button {
                refreshTransmissionData(store: store)
            } label: {
                Label("Refresh Now", systemImage: "arrow.clockwise")
            }

            Spacer(minLength: 0)
        }
        .font(.system(size: 11))
    }

    private func openMainWindow() {
        onOpenMainWindow()
    }
}

private struct TransferRowsHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

#endif
