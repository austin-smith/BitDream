import Foundation
import SwiftUI

#if os(iOS)
struct iOSTorrentDetail: View {
    @Environment(\.hapticFeedback) private var hapticFeedback

    @ObservedObject var store: TransmissionStore
    var torrent: Torrent

    @ObservedObject private var supplementalStore: TorrentDetailSupplementalStore
    @Bindable private var state: iOSTorrentDetailState
    let route: iOSTorrentDetailRoute

    init(
        store: TransmissionStore,
        torrent: Torrent,
        state: iOSTorrentDetailState,
        route: iOSTorrentDetailRoute = .overview
    ) {
        self.store = store
        self.torrent = torrent
        self.state = state
        self.supplementalStore = state.supplementalStore
        self.route = route
    }

    private var supplementalPayload: TorrentDetailSupplementalPayload {
        supplementalStore.payload(for: supplementalIdentity)
    }

    private var shouldDisplaySupplementalPayload: Bool {
        supplementalStore.shouldDisplayPayload(for: supplementalIdentity)
    }

    private var supplementalIdentity: TorrentDetailIdentity {
        TorrentDetailIdentity(
            torrentID: torrent.id,
            connectionGeneration: store.torrentDetailRefreshTrigger.connectionGeneration
        )
    }

    private func replaceSupplementalLoad() {
        hapticFeedback.play(.actionTriggered)
        supplementalStore.replaceLoad(
            for: supplementalIdentity,
            using: store,
            showingError: $state.showingError,
            errorMessage: $state.errorMessage
        )
    }

    var body: some View {
        Group {
            switch route {
            case .overview:
                overview
            case .files:
                filesDestination
            case .peers:
                peersDestination
            }
        }
        .task(id: supplementalIdentity) {
            guard route == .overview else { return }
            await supplementalStore.observeRefreshes(
                for: supplementalIdentity,
                using: store,
                showingInitialLoadError: $state.showingError,
                errorMessage: $state.errorMessage
            )
        }
        .toolbar {
            if route == .overview { detailToolbar }
        }

    }

    private var overview: some View {
        let details = formatTorrentDetails(torrent: torrent)
        let piecesSectionState = TorrentPiecesSectionState.resolve(
            status: supplementalStore.status,
            payload: supplementalPayload,
            shouldDisplayPayload: shouldDisplaySupplementalPayload
        )
        return IOSTorrentDetailContent(
            torrent: torrent,
            details: details,
            supplementalPayload: supplementalPayload,
            piecesSectionState: piecesSectionState,
            onDelete: {
                hapticFeedback.play(.actionTriggered)
                state.showingDeleteConfirmation = true
            },
            onRetryPiecesLoad: {
                replaceSupplementalLoad()
            }
        )
        .navigationTitle("Torrent Details")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ToolbarContentBuilder
    private var detailToolbar: some ToolbarContent {
        if #available(iOS 27, *) {
            ToolbarOverflowMenu {
                torrentActions
            }
        } else {
            ToolbarItem(placement: .topBarTrailing) {
                Menu("Torrent Actions", systemImage: "ellipsis") {
                    torrentActions
                }
                .iOSHapticControlActivation()
            }
        }
    }

    private var torrentActions: some View {
        IOSTorrentActionsMenu(
            torrent: torrent,
            store: store,
            onShowMove: showMoveDialog,
            onShowRename: showRenameDialog,
            onShowLabels: showLabelDialog,
            onShowDelete: showDeleteDialog,
            onError: presentError
        )
    }

    private func showRenameDialog() {
        hapticFeedback.play(.actionTriggered)
        state.renameInput = torrent.name
        state.renameDialog = true
    }

    private func showMoveDialog() {
        hapticFeedback.play(.actionTriggered)
        state.movePath = store.defaultDownloadDir
        state.moveDialog = true
    }

    private func showLabelDialog() {
        hapticFeedback.play(.actionTriggered)
        state.labelInput = torrent.labels.joined(separator: ", ")
        state.labelDialog = true
    }

    private func showDeleteDialog() {
        hapticFeedback.play(.actionTriggered)
        state.showingDeleteConfirmation = true
    }

    private func presentError(_ error: String) {
        hapticFeedback.play(.operationFailed)
        state.errorMessage = error
        state.showingError = true
    }

}

extension iOSTorrentDetail {
    @MainActor
    private func applyCommittedFileStatsMutation(
        fileIndices: [Int],
        mutation: TorrentDetailFileStatsMutation
    ) {
        supplementalStore.applyCommittedFileStatsMutation(
            mutation,
            for: supplementalIdentity,
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
                state: state.files,
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
                onLoadIfIdle: { @MainActor in await supplementalStore.loadIfIdle(for: supplementalIdentity, using: store, showingError: $state.showingError, errorMessage: $state.errorMessage) },
                onRetry: { replaceSupplementalLoad() }
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
                onRefresh: { await supplementalStore.load(for: supplementalIdentity, using: store, showingError: $state.showingError, errorMessage: $state.errorMessage) },
                searchText: $state.peerSearchText
            )
            .navigationBarTitleDisplayMode(.inline)
        } else {
            TorrentDetailSupplementalPlaceholder(
                status: supplementalStore.status,
                loadingTitle: "Loading Peers",
                loadingMessage: "Fetching the latest peers for this torrent.",
                unavailableTitle: "Peers Unavailable",
                unavailableMessage: "The latest peer details could not be loaded.",
                onLoadIfIdle: { @MainActor in await supplementalStore.loadIfIdle(for: supplementalIdentity, using: store, showingError: $state.showingError, errorMessage: $state.errorMessage) },
                onRetry: { replaceSupplementalLoad() }
            )
            .navigationTitle("Peers")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// Presentation lives above the adaptive navigation containers so folding cannot
// dismiss an editor or discard its draft.
struct IOSTorrentDetailPresentation: ViewModifier {
    @Environment(\.hapticFeedback) private var hapticFeedback
    let store: TransmissionStore
    let torrent: Torrent?
    @Bindable var state: iOSTorrentDetailState

    func body(content: Content) -> some View {
        content
        .alert("Delete Torrent", isPresented: $state.showingDeleteConfirmation) {
            Button(role: .destructive) {
                performDelete(deleteLocalData: true)
            } label: {
                Text("Delete file(s)")
            }
            Button("Remove from list only") {
                performDelete(deleteLocalData: false)
            }
            Button("Cancel", role: .cancel) {
                hapticFeedback.play(.actionTriggered)
            }
        } message: {
            Text("Do you want to delete the file(s) from the disk?")
        }
        .transmissionErrorAlert(isPresented: $state.showingError, message: state.errorMessage)
        .sheet(isPresented: $state.renameDialog, content: renameSheet)
        .sheet(isPresented: $state.moveDialog, content: moveSheet)
        .sheet(isPresented: $state.labelDialog, content: labelSheet)
    }

    private func performDelete(deleteLocalData: Bool) {
        guard let torrent else { return }
        hapticFeedback.play(.actionTriggered)
        performTransmissionAction(
            operation: {
                try await store.removeTorrents(
                    ids: [torrent.id],
                    deleteLocalData: deleteLocalData
                )
            },
            onSuccess: {
                hapticFeedback.play(.operationSucceeded)
            },
            onError: presentError
        )
    }

    private func renameSheet() -> some View {
        NavigationStack {
            if let torrent {
                IOSTorrentRenameSheet(
                    torrent: torrent,
                    store: store,
                    renameInput: $state.renameInput,
                    isPresented: $state.renameDialog,
                    onError: presentError
                )
            }
        }
    }

    private func moveSheet() -> some View {
        NavigationStack {
            if let torrent {
                IOSTorrentMoveSheet(
                    torrent: torrent,
                    store: store,
                    movePath: $state.movePath,
                    moveShouldMove: $state.moveShouldMove,
                    isPresented: $state.moveDialog,
                    onError: presentError
                )
            }
        }
    }

    private func labelSheet() -> some View {
        NavigationStack {
            if let torrent {
                iOSLabelEditView(
                    labelInput: $state.labelInput,
                    existingLabels: torrent.labels,
                    store: store,
                    torrentId: torrent.id
                )
            }
        }
    }

    private func presentError(_ message: String) {
        hapticFeedback.play(.operationFailed)
        state.errorMessage = message
        state.showingError = true
    }
}

private struct IOSTorrentDetailContent: View {
    let torrent: Torrent
    let details: TorrentDetailsDisplay
    let supplementalPayload: TorrentDetailSupplementalPayload
    let piecesSectionState: TorrentPiecesSectionState
    let onDelete: () -> Void
    let onRetryPiecesLoad: () -> Void

    var body: some View {
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

                    NavigationLink(value: iOSTorrentDetailRoute.files) {
                        LabeledContent(
                            "Files",
                            value: NumberFormatter.localizedString(
                                from: NSNumber(value: supplementalPayload.files.count),
                                number: .decimal
                            )
                        )
                    }

                    NavigationLink(value: iOSTorrentDetailRoute.peers) {
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

#if os(iOS) && DEBUG
#Preview("iOS Torrent Detail") {
    PreviewContainer { environment in
        NavigationStack {
            TorrentDetail(store: environment.store, torrent: PreviewFixtures.torrents[0])
        }
    }
}
#endif
