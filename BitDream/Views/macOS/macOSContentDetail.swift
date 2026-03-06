import Foundation
import SwiftUI
import Synchronization
import UniformTypeIdentifiers
import OSLog

#if os(macOS)

struct macOSContentDetail: View {
    let store: AppStore
    let torrents: [Torrent]
    let isCompactMode: Bool
    @Binding var selectedTorrentIds: Set<Int>
    @Binding var sortProperty: SortProperty
    @Binding var sortOrder: SortOrder
    let selectedTorrents: Set<Torrent>
    let showContentTypeIcons: Bool
    let accentColor: Color
    @Binding var isDropTargeted: Bool
    @Binding var draggedTorrentInfo: [TorrentInfo]
    let focusedTarget: FocusState<macOSContentView.FocusTarget?>.Binding

    var body: some View {
        VStack(spacing: 0) {
            StatsHeaderView(store: store)

            if store.connectionStatus == .reconnecting {
                ConnectionBannerView(status: store.connectionStatus, retryAt: store.nextRetryAt)
            }

            VStack {
                if torrents.isEmpty {
                    emptyState
                } else {
                    torrentList
                }
            }
            .onDrop(of: [.fileURL], delegate: TorrentDropDelegate(
                isDropTargeted: $isDropTargeted,
                draggedTorrentInfo: $draggedTorrentInfo,
                store: store
            ))
            .overlay(dropTargetOverlay)
            .overlay(torrentPreviewOverlay)
            .onChange(of: isDropTargeted) { _, newValue in
                if !newValue {
                    draggedTorrentInfo = []
                }
            }
        }
    }

    private var emptyState: some View {
        VStack {
            Spacer()

            if isDropTargeted {
                VStack(spacing: 12) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 48))
                        .foregroundColor(accentColor)
                    Text("Drop .torrent files here to add")
                        .font(.title2)
                        .foregroundColor(accentColor)
                }
            } else {
                VStack(spacing: 12) {
                    Text("💭")
                        .font(.system(size: 40))
                    Text("No dreams available")
                        .foregroundColor(.gray)
                    Text("Drag .torrent files here or use the + button")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
    }

    private var torrentList: some View {
        Group {
            if isCompactMode {
                macOSTorrentListCompact(
                    torrents: torrents,
                    selection: $selectedTorrentIds,
                    sortProperty: $sortProperty,
                    sortOrder: $sortOrder,
                    store: store,
                    showContentTypeIcons: showContentTypeIcons
                )
                .focusable(true)
                .focused(focusedTarget, equals: .contentList)
            } else {
                List(selection: $selectedTorrentIds) {
                    ForEach(torrents, id: \.id) { torrent in
                        TorrentListRow(
                            torrent: torrent,
                            store: store,
                            selectedTorrents: selectedTorrents,
                            showContentTypeIcons: showContentTypeIcons
                        )
                        .tag(torrent.id)
                        .listRowSeparator(.visible)
                    }
                }
                .listStyle(.plain)
                .tint(accentColor)
                .focusable(true)
                .focused(focusedTarget, equals: .contentList)
            }
        }
    }

    private var dropTargetOverlay: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(accentColor.opacity(isDropTargeted ? 0.1 : 0))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(accentColor, lineWidth: isDropTargeted ? 2.5 : 0)
                    .opacity(isDropTargeted ? 0.8 : 0)
            )
            .animation(.easeInOut(duration: 0.2), value: isDropTargeted)
    }

    private var torrentPreviewOverlay: some View {
        Group {
            if isDropTargeted && !draggedTorrentInfo.isEmpty {
                torrentPreviewCard
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isDropTargeted)
    }

    private var torrentPreviewCard: some View {
        let totalSize = draggedTorrentInfo.reduce(0) { $0 + $1.totalSize }
        let totalFiles = draggedTorrentInfo.reduce(0) { $0 + $1.fileCount }
        let formattedTotalSize = formatByteCount(totalSize)
        let fileCountText = totalFiles == 1 ? "1 file" : "\(totalFiles) files"

        let displayTitle: String = {
            if draggedTorrentInfo.count == 1 {
                if let name = draggedTorrentInfo.first?.name, !name.isEmpty {
                    return name
                } else {
                    return "1 Torrent"
                }
            } else {
                return "\(draggedTorrentInfo.count) Torrents"
            }
        }()

        return HStack(spacing: 16) {
            Image(systemName: "document.badge.plus")
                .foregroundColor(.secondary)
                .font(.system(size: 40))
                .frame(width: 50, height: 50)

            VStack(alignment: .leading, spacing: 4) {
                Text(displayTitle)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .truncationMode(.middle)

                HStack(spacing: 8) {
                    Text(formattedTotalSize)
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundColor(.secondary)
                    Text("•")
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundColor(.secondary)
                    Text(fileCountText)
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThickMaterial)
                .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 6)
        )
        .frame(maxWidth: 400, minHeight: 80)
    }
}

struct macOSContentInspector: View {
    let store: AppStore
    let selectedTorrent: Torrent?

    var body: some View {
        Group {
            if let selectedTorrent {
                TorrentDetail(store: store, torrent: selectedTorrent)
                    .id(selectedTorrent.id)
            } else {
                VStack {
                    Spacer()
                    Text("💭")
                        .font(.system(size: 40))
                        .padding(.bottom, 8)
                    Text("Select a Dream")
                        .font(.title2)
                        .foregroundColor(.gray)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

private struct ConnectionBannerView: View {
    @Environment(\.openWindow) private var openWindow

    let status: AppStore.ConnectionStatus
    let retryAt: Date?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: connectionStatusSymbol(for: status))
                .foregroundColor(connectionStatusColor(for: status))
                .font(.system(size: 16, weight: .semibold))
            VStack(alignment: .leading, spacing: 2) {
                Text(connectionStatusTitle(for: status))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(connectionRetryText(status: status, retryAt: retryAt, at: context.date))
                        .font(.caption)
                        .foregroundColor(.secondary)
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
        .overlay(Divider(), alignment: .bottom)
    }
}

private final class TorrentInfoAccumulator: Sendable {
    private let values = Mutex<[TorrentInfo]>([])

    func append(_ value: TorrentInfo) {
        values.withLock { $0.append(value) }
    }

    var snapshot: [TorrentInfo] {
        values.withLock { $0 }
    }
}

struct TorrentDropDelegate: DropDelegate {
    @Binding var isDropTargeted: Bool
    @Binding var draggedTorrentInfo: [TorrentInfo]
    let store: AppStore
    private nonisolated static let logger = Logger(subsystem: AppIdentity.bundleIdentifier, category: "ui")

    private nonisolated static func readTorrentData(from url: URL) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            var didAccess = false
            if url.isFileURL {
                didAccess = url.startAccessingSecurityScopedResource()
            }
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            return try Data(contentsOf: url)
        }.value
    }

    func dropEntered(info: DropInfo) {
        isDropTargeted = true

        let providers = info.itemProviders(for: [.fileURL])
        let parsedInfos = TorrentInfoAccumulator()
        let group = DispatchGroup()

        for provider in providers where provider.canLoadObject(ofClass: URL.self) {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, loadError in
                defer { group.leave() }
                guard let url else {
                    if let loadError {
                        Self.logger.error("Failed to load dropped file URL: \(loadError.localizedDescription)")
                    }
                    return
                }
                guard url.pathExtension.lowercased() == "torrent" else { return }

                do {
                    var didAccess = false
                    if url.isFileURL {
                        didAccess = url.startAccessingSecurityScopedResource()
                    }
                    defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

                    let data = try Data(contentsOf: url)
                    if let torrentInfo = parseTorrentInfo(from: data) {
                        parsedInfos.append(torrentInfo)
                    }
                } catch {
                    Self.logger.error("Failed to parse dropped torrent metadata from \(url.lastPathComponent): \(error.localizedDescription)")
                }
            }
        }

        group.notify(queue: .main) {
            draggedTorrentInfo = parsedInfos.snapshot
        }
    }

    func dropExited(info: DropInfo) {
        isDropTargeted = false
        draggedTorrentInfo = []
    }

    func performDrop(info: DropInfo) -> Bool {
        isDropTargeted = false

        for provider in info.itemProviders(for: [.fileURL]) where provider.canLoadObject(ofClass: URL.self) {
            _ = provider.loadObject(ofClass: URL.self) { url, loadError in
                guard let url else {
                    if let loadError {
                        Self.logger.error("Failed to load dropped file URL: \(loadError.localizedDescription)")
                    }
                    return
                }
                guard url.pathExtension.lowercased() == "torrent" else { return }
                Task { @MainActor in
                    do {
                        let data = try await Self.readTorrentData(from: url)
                        addTorrentFromFileData(data, store: store)
                    } catch {
                        Self.logger.error("Failed to read dropped torrent file \(url.lastPathComponent): \(error.localizedDescription)")
                    }
                }
            }
        }

        return true
    }

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.fileURL])
    }
}

#endif
