import Foundation
import SwiftUI

#if os(macOS)
struct macOSTorrentDetail: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var store: TransmissionStore
    var torrent: Torrent

    @StateObject private var supplementalStore = TorrentDetailSupplementalStore()
    @State private var isShowingFilesSheet = false
    @State private var isShowingPeersSheet = false
    @State private var showingDeleteConfirmation = false
    @State private var showingError = false
    @State private var errorMessage = ""

    private var supplementalPayload: TorrentDetailSupplementalPayload {
        supplementalStore.payload(for: torrent.id)
    }

    private var shouldDisplaySupplementalPayload: Bool {
        supplementalStore.shouldDisplayPayload(for: torrent.id)
    }

    var body: some View {
        let details = formatTorrentDetails(torrent: torrent)
        let piecesSectionState = TorrentPiecesSectionState.resolve(
            status: supplementalStore.status,
            payload: supplementalPayload,
            shouldDisplayPayload: shouldDisplaySupplementalPayload
        )

        MacOSTorrentDetailContent(
            torrent: torrent,
            details: details,
            supplementalPayload: supplementalPayload,
            piecesSectionState: piecesSectionState,
            onShowFiles: { isShowingFilesSheet = true },
            onShowPeers: { isShowingPeersSheet = true },
            onDelete: { showingDeleteConfirmation = true }
        )
        .sheet(isPresented: $isShowingFilesSheet) {
            let totalSizeFormatted = formatByteCount(supplementalPayload.files.reduce(0) { $0 + $1.length })

            VStack(spacing: 0) {
                // Header with proper hierarchy
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Files")
                                .font(.title2)
                                .fontWeight(.semibold)

                            Text("\(torrent.name) • \(supplementalPayload.files.count) files • \(totalSizeFormatted)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        Spacer()

                        Button("Done") {
                            isShowingFilesSheet = false
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)

                Divider()

                filesSheetContent
            }
            .frame(minWidth: 1000, minHeight: 800)
        }
        .sheet(isPresented: $isShowingPeersSheet) {
            peersSheetContent
                .frame(minWidth: 1000, minHeight: 700)
        }
        .task(id: torrent.id) {
            await supplementalStore.load(for: torrent.id, using: store, showingError: $showingError, errorMessage: $errorMessage)
        }
        .toolbar {
            // Use shared toolbar
            TorrentDetailToolbar(torrent: torrent, store: store)
        }
        .alert("Delete Torrent", isPresented: $showingDeleteConfirmation) {
            Button(role: .destructive) {
                performDelete(deleteLocalData: true)
            } label: {
                Text("Delete file(s)")
            }
            Button("Remove from list only") {
                performDelete(deleteLocalData: false)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Do you want to delete the file(s) from the disk?")
        }
        .transmissionErrorAlert(isPresented: $showingError, message: errorMessage)
    }

    @MainActor
    private func applyCommittedFileStatsMutation(
        fileIndices: [Int],
        mutation: TorrentDetailFileStatsMutation
    ) {
        supplementalStore.applyCommittedFileStatsMutation(
            mutation,
            for: torrent.id,
            fileIndices: fileIndices
        )
    }

    private func performDelete(deleteLocalData: Bool) {
        performTransmissionAction(
            operation: {
                try await store.removeTorrents(
                    ids: [torrent.id],
                    deleteLocalData: deleteLocalData
                )
            },
            onSuccess: {
                dismiss()
            },
            onError: makeTransmissionBindingErrorHandler(
                isPresented: $showingError,
                message: $errorMessage
            )
        )
    }

    @ViewBuilder
    private var filesSheetContent: some View {
        if shouldDisplaySupplementalPayload {
            macOSTorrentFileDetail(
                files: supplementalPayload.files,
                fileStats: supplementalPayload.fileStats,
                torrentId: torrent.id,
                store: store,
                onCommittedFileStatsMutation: { fileIndices, mutation in
                    applyCommittedFileStatsMutation(
                        fileIndices: fileIndices,
                        mutation: mutation
                    )
                }
            )
        } else {
            TorrentDetailSupplementalPlaceholder(
                status: supplementalStore.status,
                loadingTitle: "Loading Files",
                loadingMessage: "Fetching the latest files for this torrent.",
                unavailableTitle: "Files Unavailable",
                unavailableMessage: "The latest file details could not be loaded.",
                onLoadIfIdle: { await supplementalStore.loadIfIdle(for: torrent.id, using: store, showingError: $showingError, errorMessage: $errorMessage) },
                onRetry: { Task { await supplementalStore.load(for: torrent.id, using: store, showingError: $showingError, errorMessage: $errorMessage) } }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var peersSheetContent: some View {
        if shouldDisplaySupplementalPayload {
            macOSTorrentPeerDetail(
                torrentName: torrent.name,
                torrentId: torrent.id,
                store: store,
                peers: supplementalPayload.peers,
                peersFrom: supplementalPayload.peersFrom,
                onRefresh: { await supplementalStore.load(for: torrent.id, using: store, showingError: $showingError, errorMessage: $errorMessage) },
                onDone: { isShowingPeersSheet = false }
            )
        } else {
            TorrentDetailSupplementalPlaceholder(
                status: supplementalStore.status,
                loadingTitle: "Loading Peers",
                loadingMessage: "Fetching the latest peers for this torrent.",
                unavailableTitle: "Peers Unavailable",
                unavailableMessage: "The latest peer details could not be loaded.",
                onLoadIfIdle: { await supplementalStore.loadIfIdle(for: torrent.id, using: store, showingError: $showingError, errorMessage: $errorMessage) },
                onRetry: { Task { await supplementalStore.load(for: torrent.id, using: store, showingError: $showingError, errorMessage: $errorMessage) } }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct MacOSTorrentDetailContent: View {
    let torrent: Torrent
    let details: TorrentDetailsDisplay
    let supplementalPayload: TorrentDetailSupplementalPayload
    let piecesSectionState: TorrentPiecesSectionState
    let onShowFiles: () -> Void
    let onShowPeers: () -> Void
    let onDelete: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TorrentDetailHeaderView(torrent: torrent)
                    .padding(.bottom, 4)

                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        macOSSectionHeader("General", icon: "info.circle")
                        DetailRow(label: "Name", value: torrent.name)
                        DetailRow(label: "Status") {
                            TorrentStatusBadge(torrent: torrent)
                        }
                        DetailRow(label: "Date Added", value: details.addedDate)
                        DetailRow(label: "Files") {
                            Button(action: onShowFiles) {
                                HStack(spacing: 4) {
                                    Image(systemName: "document")
                                        .font(.system(size: 12))
                                        .foregroundColor(.accentColor)
                                    Text("\(supplementalPayload.files.count)")
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .buttonStyle(.bordered)
                            .help("View files in this torrent")
                        }
                        DetailRow(label: "Peers") {
                            Button(action: onShowPeers) {
                                HStack(spacing: 4) {
                                    Image(systemName: "person.2")
                                        .font(.system(size: 12))
                                        .foregroundColor(.accentColor)
                                    Text("\(supplementalPayload.peers.count)")
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .buttonStyle(.bordered)
                            .help("View peers for this torrent")
                        }
                    }
                    .padding(.vertical, 16)
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 8)

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        macOSSectionHeader("Stats", icon: "chart.bar")
                        DetailRow(label: "Size When Done", value: details.sizeWhenDoneFormatted)
                        DetailRow(label: "Progress", value: details.percentComplete)
                        DetailRow(label: "Downloaded", value: details.downloadedFormatted)
                        DetailRow(label: "Uploaded", value: details.uploadedFormatted)
                        DetailRow(label: "Upload Ratio", value: details.uploadRatio)
                    }
                    .padding(.vertical, 16)
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 8)

                MacOSTorrentPiecesSection(state: piecesSectionState)
                    .padding(.bottom, 8)

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        macOSSectionHeader("Additional Info", icon: "doc.text")
                        DetailRow(label: "Availability", value: details.percentAvailable)
                        DetailRow(label: "Last Activity", value: details.activityDate)
                    }
                    .padding(.vertical, 16)
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 8)

                if !torrent.labels.isEmpty {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 16) {
                            macOSSectionHeader("Labels", icon: "tag")

                            FlowLayout(spacing: 6) {
                                ForEach(torrent.labels.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }, id: \.self) { label in
                                    DetailViewLabelTag(label: label, isLarge: false)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 16)
                        .padding(.horizontal, 20)
                    }
                    .padding(.bottom, 8)
                }

                HStack {
                    Spacer()
                    Button(role: .destructive, action: onDelete) {
                        Label("Delete…", systemImage: "trash")
                    }
                }
                .padding(.top, 8)
            }
            .padding(20)
        }
    }
}

private struct MacOSTorrentPiecesSection: View {
    private static let contentMinHeight: CGFloat = 96

    let state: TorrentPiecesSectionState

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                macOSSectionHeader("Pieces", icon: "square.grid.2x2")

                sectionContent
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: Self.contentMinHeight, alignment: .top)
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 20)
        }
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch state {
        case .loading:
            MacOSTorrentPiecesLoadingView()
        case .content(let payload):
            VStack(alignment: .leading, spacing: 8) {
                PiecesGridView(
                    piecesHaveSet: payload.piecesHaveSet
                )
                .frame(maxWidth: .infinity)

                Text(
                    "\(payload.piecesHaveCount) of \(payload.pieceCount) pieces • \(formatByteCount(payload.pieceSize)) each"
                )
                .font(.caption)
                .foregroundColor(.secondary)
            }
        case .empty:
            MacOSTorrentPiecesMessageView(
                title: "No Piece Data",
                message: "Piece availability is not available for this torrent."
            )
        case .failed:
            MacOSTorrentPiecesMessageView(
                title: "Pieces Unavailable",
                message: "BitDream couldn't load piece availability for this torrent."
            )
        }
    }
}

private struct MacOSTorrentPiecesLoadingView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.12))
                .frame(maxWidth: .infinity)
                .frame(height: 80)
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 4)
                            .frame(width: 180, height: 8)
                        RoundedRectangle(cornerRadius: 4)
                            .frame(maxWidth: .infinity)
                            .frame(height: 8)
                        RoundedRectangle(cornerRadius: 4)
                            .frame(width: 240, height: 8)
                    }
                    .padding(12)
                    .foregroundStyle(.secondary.opacity(0.2))
                }

            RoundedRectangle(cornerRadius: 4)
                .fill(Color.secondary.opacity(0.12))
                .frame(width: 220, height: 10)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading pieces")
    }
}

private struct MacOSTorrentPiecesMessageView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// Helper view for consistent detail rows
struct DetailRow<Content: View>: View {
    var label: String
    var content: Content

    init(label: String, value: String) where Content == Text {
        self.label = label
        self.content = Text(value).foregroundColor(.secondary)
    }

    init(label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .frame(width: 120, alignment: .leading)
                .foregroundColor(.primary)

            content

            Spacer()
        }
        .padding(.vertical, 2)
    }
}

// Native macOS-style section header component
struct macOSSectionHeader: View {
    let title: String
    let icon: String

    init(_ title: String, icon: String) {
        self.title = title
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)

            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)

            Spacer()
        }
        .padding(.bottom, 8)
    }
}
#endif
