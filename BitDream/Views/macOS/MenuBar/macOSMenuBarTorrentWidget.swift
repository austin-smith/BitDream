import SwiftUI

#if os(macOS)
struct macOSMenuBarTorrentWidget: View {
    @EnvironmentObject private var store: TransmissionStore
    @State private var torrentRowsHeight: CGFloat = 0
    @AppStorage(UserDefaultsKeys.menuBarSortMode) private var menuBarSortModeRaw: String = AppDefaults.menuBarSortMode.rawValue
    let onOpenMainWindow: () -> Void

    private let panelWidth: CGFloat = 380
    private let maxListHeight: CGFloat = 320
    private let estimatedRowHeight: CGFloat = 74

    init(
        onOpenMainWindow: @escaping () -> Void = {}
    ) {
        self.onOpenMainWindow = onOpenMainWindow
    }

    private var menuBarSortMode: MenuBarSortMode {
        MenuBarSortMode(rawValue: menuBarSortModeRaw) ?? AppDefaults.menuBarSortMode
    }

    private var activeTorrents: [Torrent] {
        menuBarActiveTorrents(from: store, sortMode: menuBarSortMode)
    }

    private var summary: MenuBarTorrentSummary {
        menuBarSummary(from: store, activeTorrents: activeTorrents)
    }

    private var isConnected: Bool {
        store.connectionStatus == .connected
    }

    private var activeCountText: String {
        isConnected ? "\(summary.activeCount) active" : "-"
    }

    private var estimatedTransferListHeight: CGFloat {
        let estimatedRowsHeight = CGFloat(activeTorrents.count) * estimatedRowHeight + 4
        return min(max(estimatedRowsHeight, 1), maxListHeight)
    }

    private var clampedTransferListHeight: CGFloat {
        let measured = torrentRowsHeight
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

                if isConnected {
                    if activeTorrents.isEmpty {
                        emptyState
                    } else {
                        transfersList
                    }
                } else {
                    unavailableState
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
                if store.connectionStatus != .connected {
                    Image(systemName: connectionStatusSymbol(for: store.connectionStatus))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(connectionStatusColor(for: store.connectionStatus))
                }

                Text(summary.serverName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)

                Spacer(minLength: 0)

                Text(activeCountText)
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
        .onPreferenceChange(TorrentRowsHeightPreferenceKey.self) { torrentRowsHeight = $0 }
    }

    private var transferRows: some View {
        LazyVStack(spacing: 8) {
            ForEach(activeTorrents, id: \.id) { torrent in
                macOSMenuBarTorrentRow(torrent: torrent) {
                    openMainWindow()
                }
            }
        }
        .padding(.vertical, 2)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: TorrentRowsHeightPreferenceKey.self, value: proxy.size.height)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No active torrents")
                .font(.system(size: 12, weight: .semibold))
            Text("Downloading, metadata retrieval, seeding, and verification appear here.")
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

            Text("Open BitDream and add or select a server to view active torrents.")
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

    private var unavailableState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(connectionStatusTitle(for: store.connectionStatus))
                .font(.system(size: 12, weight: .semibold))
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(connectionRetryText(status: store.connectionStatus, retryAt: store.nextRetryAt, at: context.date))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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

            Spacer(minLength: 0)
        }
        .font(.system(size: 11))
    }

    private func openMainWindow() {
        onOpenMainWindow()
    }
}

private struct TorrentRowsHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

#endif
