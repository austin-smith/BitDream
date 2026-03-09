import Foundation
import SwiftUI

#if os(iOS)
struct iOSTorrentDetail: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var store: TransmissionStore
    var torrent: Torrent

    @StateObject private var supplementalStore = TorrentDetailSupplementalStore()
    @State private var showingDeleteConfirmation = false
    @State private var labelDialog = false
    @State private var labelInput: String = ""
    @State private var renameDialog = false
    @State private var renameInput: String = ""
    @State private var moveDialog = false
    @State private var movePath: String = ""
    @State private var moveShouldMove = true
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

        IOSTorrentDetailContent(
            torrent: torrent,
            details: details,
            supplementalPayload: supplementalPayload,
            piecesSectionState: piecesSectionState,
            filesDestination: filesDestination,
            peersDestination: peersDestination,
            onDelete: { showingDeleteConfirmation = true },
            onRetryPiecesLoad: {
                Task {
                    await supplementalStore.load(
                        for: torrent.id,
                        using: store,
                        showingError: $showingError,
                        errorMessage: $errorMessage
                    )
                }
            }
        )
        .task(id: torrent.id) {
            await supplementalStore.load(for: torrent.id, using: store, showingError: $showingError, errorMessage: $errorMessage)
        }
        .toolbar {
            detailToolbar
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
        .sheet(isPresented: $renameDialog, content: renameSheet)
        .sheet(isPresented: $moveDialog, content: moveSheet)
        .sheet(isPresented: $labelDialog, content: labelSheet)
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

    private var detailToolbar: some ToolbarContent {
        ToolbarItem {
            Menu {
                IOSTorrentActionsMenu(
                    torrent: torrent,
                    store: store,
                    onShowMove: showMoveDialog,
                    onShowRename: showRenameDialog,
                    onShowLabels: showLabelDialog,
                    onShowDelete: { showingDeleteConfirmation = true },
                    onError: presentError
                )
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    private func renameSheet() -> some View {
        NavigationView {
            IOSTorrentRenameSheet(
                torrent: torrent,
                store: store,
                renameInput: $renameInput,
                isPresented: $renameDialog,
                onError: presentError
            )
        }
    }

    private func moveSheet() -> some View {
        NavigationView {
            IOSTorrentMoveSheet(
                torrent: torrent,
                store: store,
                movePath: $movePath,
                moveShouldMove: $moveShouldMove,
                isPresented: $moveDialog,
                onError: presentError
            )
        }
    }

    private func labelSheet() -> some View {
        NavigationView {
            iOSLabelEditView(
                labelInput: $labelInput,
                existingLabels: torrent.labels,
                store: store,
                torrentId: torrent.id
            )
        }
    }

    private func showRenameDialog() {
        renameInput = torrent.name
        renameDialog = true
    }

    private func showMoveDialog() {
        movePath = store.defaultDownloadDir
        moveDialog = true
    }

    private func showLabelDialog() {
        labelInput = torrent.labels.joined(separator: ", ")
        labelDialog = true
    }

    private func presentError(_ error: String) {
        errorMessage = error
        showingError = true
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

    @ViewBuilder
    private var filesDestination: some View {
        if shouldDisplaySupplementalPayload {
            iOSTorrentFileDetail(
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
            .navigationBarTitleDisplayMode(.inline)
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
            .navigationTitle("Files")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private var peersDestination: some View {
        if shouldDisplaySupplementalPayload {
            iOSTorrentPeerDetail(
                torrentName: torrent.name,
                torrentId: torrent.id,
                store: store,
                peers: supplementalPayload.peers,
                peersFrom: supplementalPayload.peersFrom,
                onRefresh: { await supplementalStore.load(for: torrent.id, using: store, showingError: $showingError, errorMessage: $errorMessage) },
                onDone: { /* no-op in push */ }
            )
            .navigationBarTitleDisplayMode(.inline)
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
            .navigationTitle("Peers")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct IOSTorrentDetailContent<FilesDestination: View, PeersDestination: View>: View {
    let torrent: Torrent
    let details: TorrentDetailsDisplay
    let supplementalPayload: TorrentDetailSupplementalPayload
    let piecesSectionState: TorrentPiecesSectionState
    let filesDestination: FilesDestination
    let peersDestination: PeersDestination
    let onDelete: () -> Void
    let onRetryPiecesLoad: () -> Void

    var body: some View {
        NavigationStack {
            VStack {
                TorrentDetailHeaderView(torrent: torrent)

                Form {
                    Section(header: Text("General")) {
                        HStack(alignment: .top) {
                            Text("Name")
                            Spacer(minLength: 50)
                            Text(torrent.name)
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.trailing)
                                .lineLimit(5)
                        }
                        HStack {
                            Text("Status")
                            Spacer()
                            TorrentStatusBadge(torrent: torrent)
                        }
                        HStack {
                            Text("Date Added")
                            Spacer()
                            Text(details.addedDate)
                                .foregroundColor(.gray)
                        }

                        NavigationLink {
                            filesDestination
                        } label: {
                            LabeledContent(
                                "Files",
                                value: NumberFormatter.localizedString(
                                    from: NSNumber(value: supplementalPayload.files.count),
                                    number: .decimal
                                )
                            )
                        }

                        NavigationLink {
                            peersDestination
                        } label: {
                            LabeledContent("Peers", value: "\(supplementalPayload.peers.count)")
                        }
                    }

                    Section(header: Text("Stats")) {
                        HStack {
                            Text("Size When Done")
                            Spacer()
                            Text(details.sizeWhenDoneFormatted)
                                .foregroundColor(.gray)
                        }
                        HStack {
                            Text("Progress")
                            Spacer()
                            Text(details.percentComplete)
                                .foregroundColor(.gray)
                        }
                        HStack {
                            Text("Downloaded")
                            Spacer()
                            Text(details.downloadedFormatted)
                                .foregroundColor(.gray)
                        }
                        HStack {
                            Text("Uploaded")
                            Spacer()
                            Text(details.uploadedFormatted)
                                .foregroundColor(.gray)
                        }
                        HStack {
                            Text("Upload Ratio")
                            Spacer()
                            Text(details.uploadRatio)
                                .foregroundColor(.gray)
                        }
                    }

                    Section(header: Text("Pieces")) {
                        IOSTorrentPiecesSectionContent(
                            state: piecesSectionState,
                            onRetry: onRetryPiecesLoad
                        )
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }

                    Section(header: Text("Additional Info")) {
                        HStack {
                            Text("Availability")
                            Spacer()
                            Text(details.percentAvailable)
                                .foregroundColor(.gray)
                        }
                        HStack {
                            Text("Last Activity")
                            Spacer()
                            Text(details.activityDate)
                                .foregroundColor(.gray)
                        }
                    }

                    if !torrent.labels.isEmpty {
                        Section(header: Text("Labels")) {
                            FlowLayout(spacing: 6) {
                                ForEach(torrent.labels.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }, id: \.self) { label in
                                    DetailViewLabelTag(label: label, isLarge: false)
                                }
                            }
                            .padding(.vertical, 8)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        }
                    }

                    Button(role: .destructive, action: onDelete) {
                        HStack {
                            HStack {
                                Image(systemName: "trash")
                                Text("Delete…")
                                Spacer()
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct IOSTorrentPiecesSectionContent: View {
    let state: TorrentPiecesSectionState
    let onRetry: () -> Void

    var body: some View {
        switch state {
        case .loading:
            IOSTorrentPiecesLoadingView()
        case .content(let payload):
            VStack(alignment: .leading, spacing: 6) {
                PiecesGridView(
                    piecesHaveSet: payload.piecesHaveSet
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(
                    "\(payload.piecesHaveCount) of \(payload.pieceCount) pieces • \(formatByteCount(payload.pieceSize)) each"
                )
                .font(.caption)
                .foregroundColor(.secondary)
            }
        case .empty:
            IOSTorrentPiecesMessageView(
                title: "No Piece Data",
                message: "Piece availability is not available for this torrent."
            )
        case .failed:
            IOSTorrentPiecesMessageView(
                title: "Pieces Unavailable",
                message: "BitDream couldn't load piece availability for this torrent.",
                actionTitle: "Retry",
                action: onRetry
            )
        }
    }
}

private struct IOSTorrentPiecesLoadingView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.12))
                .frame(maxWidth: .infinity)
                .frame(height: 80)
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 4)
                            .frame(width: 140, height: 8)
                        RoundedRectangle(cornerRadius: 4)
                            .frame(maxWidth: .infinity)
                            .frame(height: 8)
                        RoundedRectangle(cornerRadius: 4)
                            .frame(width: 200, height: 8)
                    }
                    .padding(12)
                    .foregroundStyle(.secondary.opacity(0.2))
                }

            RoundedRectangle(cornerRadius: 4)
                .fill(Color.secondary.opacity(0.12))
                .frame(width: 220, height: 10)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading pieces")
    }
}

private struct IOSTorrentPiecesMessageView: View {
    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?

    init(
        title: String,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)

            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.caption.weight(.semibold))
            }
        }
        .padding(.vertical, 4)
    }
}

#endif
