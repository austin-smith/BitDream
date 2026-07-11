import Foundation
import SwiftUI
import Combine

struct TorrentDetail: View {
    @ObservedObject var store: TransmissionStore
    var torrent: Torrent

    var body: some View {
        #if os(iOS)
        iOSTorrentDetail(store: store, torrent: torrent)
        #elseif os(macOS)
        macOSTorrentDetail(store: store, torrent: torrent)
        #endif
    }
}

// MARK: - Shared Helpers

internal enum TorrentDetailSupplementalLoadStatus: Sendable, Equatable {
    case idle
    case loading
    case loaded
    case failed
}

internal enum TorrentDetailFileStatsMutation: Sendable, Equatable {
    case wanted(Bool)
    case priority(FilePriority)
}

internal struct TorrentDetailIdentity: Hashable, Sendable {
    let torrentID: Int
    let connectionGeneration: UUID
}

internal struct TorrentDetailSupplementalPayload: Sendable, Equatable {
    let files: [TorrentFile]
    let fileStats: [TorrentFileStats]
    let peers: [Peer]
    let peersFrom: PeersFrom?
    let pieceCount: Int
    let pieceSize: Int64
    let piecesHaveSet: [Bool]
    let piecesHaveCount: Int

    static let empty = TorrentDetailSupplementalPayload(
        files: [],
        fileStats: [],
        peers: [],
        peersFrom: nil,
        pieceCount: 0,
        pieceSize: 0,
        piecesHaveSet: [],
        piecesHaveCount: 0
    )

    init(
        files: [TorrentFile],
        fileStats: [TorrentFileStats],
        peers: [Peer],
        peersFrom: PeersFrom?,
        pieceCount: Int,
        pieceSize: Int64,
        piecesHaveSet: [Bool],
        piecesHaveCount: Int
    ) {
        self.files = files
        self.fileStats = fileStats
        self.peers = peers
        self.peersFrom = peersFrom
        self.pieceCount = pieceCount
        self.pieceSize = pieceSize
        self.piecesHaveSet = piecesHaveSet
        self.piecesHaveCount = piecesHaveCount
    }

    init(snapshot: TransmissionTorrentDetailSnapshot) {
        let haveSet = decodePiecesBitfield(
            base64String: snapshot.piecesBitfieldBase64,
            pieceCount: snapshot.pieceCount
        )

        self.init(
            files: snapshot.files,
            fileStats: snapshot.fileStats,
            peers: snapshot.peers,
            peersFrom: snapshot.peersFrom,
            pieceCount: snapshot.pieceCount,
            pieceSize: snapshot.pieceSize,
            piecesHaveSet: haveSet,
            piecesHaveCount: haveSet.reduce(0) { $0 + ($1 ? 1 : 0) }
        )
    }

    func updating(fileStats: [TorrentFileStats]) -> Self {
        Self(
            files: files,
            fileStats: fileStats,
            peers: peers,
            peersFrom: peersFrom,
            pieceCount: pieceCount,
            pieceSize: pieceSize,
            piecesHaveSet: piecesHaveSet,
            piecesHaveCount: piecesHaveCount
        )
    }

    var hasRenderablePieceData: Bool {
        pieceCount > 0 && !piecesHaveSet.isEmpty
    }
}

internal enum TorrentPiecesSectionState: Equatable {
    case loading
    case content(TorrentDetailSupplementalPayload)
    case empty
    case failed

    static func resolve(
        status: TorrentDetailSupplementalLoadStatus,
        payload: TorrentDetailSupplementalPayload,
        shouldDisplayPayload: Bool
    ) -> Self {
        guard shouldDisplayPayload else {
            return status == .failed ? .failed : .loading
        }

        switch status {
        case .failed:
            return payload.hasRenderablePieceData ? .content(payload) : .failed
        case .loaded:
            return payload.hasRenderablePieceData ? .content(payload) : .empty
        case .idle, .loading:
            return payload.hasRenderablePieceData ? .content(payload) : .loading
        }
    }
}

internal struct TorrentDetailSupplementalState: Sendable {
    private(set) var activeIdentity: TorrentDetailIdentity?
    private(set) var activeRequestGeneration: Int = 0
    private(set) var status: TorrentDetailSupplementalLoadStatus = .idle
    private(set) var payload: TorrentDetailSupplementalPayload = .empty
    private(set) var hasLoadedPayload = false
    private(set) var hasReportedInitialLoadError = false

    func shouldDisplayPayload(for identity: TorrentDetailIdentity) -> Bool {
        activeIdentity == identity && hasLoadedPayload
    }

    func visiblePayload(for identity: TorrentDetailIdentity) -> TorrentDetailSupplementalPayload {
        shouldDisplayPayload(for: identity) ? payload : .empty
    }

    func shouldReportInitialLoadError(for identity: TorrentDetailIdentity) -> Bool {
        guard !shouldDisplayPayload(for: identity) else { return false }
        return activeIdentity != identity || !hasReportedInitialLoadError
    }

    @discardableResult
    mutating func beginLoading(for identity: TorrentDetailIdentity) -> Int {
        if activeIdentity != identity {
            payload = .empty
            hasLoadedPayload = false
            hasReportedInitialLoadError = false
        }

        activeIdentity = identity
        activeRequestGeneration += 1
        status = .loading
        return activeRequestGeneration
    }

    @discardableResult
    mutating func markInitialLoadErrorReported(for identity: TorrentDetailIdentity) -> Bool {
        guard activeIdentity == identity, !hasReportedInitialLoadError else {
            return false
        }

        hasReportedInitialLoadError = true
        return true
    }

    @discardableResult
    mutating func apply(
        snapshot: TransmissionTorrentDetailSnapshot,
        for identity: TorrentDetailIdentity,
        generation: Int
    ) -> Bool {
        guard activeIdentity == identity, activeRequestGeneration == generation else {
            return false
        }

        status = .loaded
        payload = TorrentDetailSupplementalPayload(snapshot: snapshot)
        hasLoadedPayload = true
        return true
    }

    @discardableResult
    mutating func markFailed(for identity: TorrentDetailIdentity, generation: Int) -> Bool {
        guard activeIdentity == identity, activeRequestGeneration == generation else {
            return false
        }

        status = .failed
        return true
    }

    @discardableResult
    mutating func markCancelled(for identity: TorrentDetailIdentity, generation: Int) -> Bool {
        guard activeIdentity == identity, activeRequestGeneration == generation else {
            return false
        }

        guard status == .loading else {
            return false
        }

        status = hasLoadedPayload ? .loaded : .idle
        return true
    }

    @discardableResult
    mutating func applyCommittedFileStatsMutation(
        _ mutation: TorrentDetailFileStatsMutation,
        for identity: TorrentDetailIdentity,
        fileIndices: [Int]
    ) -> Bool {
        guard activeIdentity == identity, hasLoadedPayload else {
            return false
        }

        var updatedFileStats = payload.fileStats
        var didApply = false

        for fileIndex in fileIndices where updatedFileStats.indices.contains(fileIndex) {
            updatedFileStats[fileIndex] = updatedFileStats[fileIndex].applying(mutation)
            didApply = true
        }

        guard didApply else {
            return false
        }

        payload = payload.updating(fileStats: updatedFileStats)
        return true
    }
}

@MainActor
internal final class TorrentDetailSupplementalStore: ObservableObject {
    @Published private(set) var state = TorrentDetailSupplementalState()
    private var managedLoadTask: Task<Void, Never>?
    private var managedLoadGeneration = 0
    private var loadQueueTail: Task<Void, Never>?
    private var loadQueueGeneration = 0
    private var pendingLoadCounts: [TorrentDetailIdentity: Int] = [:]

    init(state: TorrentDetailSupplementalState = TorrentDetailSupplementalState()) {
        self.state = state
    }

    deinit {
        managedLoadTask?.cancel()
        loadQueueTail?.cancel()
    }

    var payload: TorrentDetailSupplementalPayload {
        state.payload
    }

    var status: TorrentDetailSupplementalLoadStatus {
        state.status
    }

    func payload(for identity: TorrentDetailIdentity) -> TorrentDetailSupplementalPayload {
        state.visiblePayload(for: identity)
    }

    func shouldDisplayPayload(for identity: TorrentDetailIdentity) -> Bool {
        state.shouldDisplayPayload(for: identity)
    }

    func replaceLoad(
        for identity: TorrentDetailIdentity,
        using store: TransmissionStore,
        onError: @escaping @MainActor @Sendable (String) -> Void
    ) {
        guard identity.connectionGeneration == store.torrentDetailRefreshTrigger.connectionGeneration else {
            return
        }

        managedLoadGeneration += 1
        let generation = managedLoadGeneration

        managedLoadTask?.cancel()
        managedLoadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.load(for: identity, using: store, onError: onError)
            self.clearManagedLoadTask(ifMatching: generation)
        }
    }

    @discardableResult
    func applyCommittedFileStatsMutation(
        _ mutation: TorrentDetailFileStatsMutation,
        for identity: TorrentDetailIdentity,
        fileIndices: [Int]
    ) -> Bool {
        mutateState { $0.applyCommittedFileStatsMutation(mutation, for: identity, fileIndices: fileIndices) }
    }

    func load(
        for identity: TorrentDetailIdentity,
        using store: TransmissionStore,
        onError: @escaping @MainActor @Sendable (String) -> Void
    ) async {
        guard identity.connectionGeneration == store.torrentDetailRefreshTrigger.connectionGeneration else {
            return
        }

        let loadTask = enqueueLoad(for: identity, using: store, onError: onError)

        await withTaskCancellationHandler {
            await loadTask.value
        } onCancel: {
            loadTask.cancel()
        }
    }

    private func performLoad(
        for identity: TorrentDetailIdentity,
        using store: TransmissionStore,
        onError: @escaping @MainActor @Sendable (String) -> Void
    ) async {
        guard identity.connectionGeneration == store.torrentDetailRefreshTrigger.connectionGeneration else {
            return
        }

        let requestGeneration = mutateState { state in
            state.beginLoading(for: identity)
        }

        guard let snapshot = await performStructuredTransmissionOperation(
            operation: { try await store.loadTorrentDetail(id: identity.torrentID) },
            onError: { [weak self] message in
                guard let self else { return }
                guard self.markFailure(for: identity, generation: requestGeneration) else {
                    return
                }
                onError(message)
            }
        ) else {
            _ = markCancellation(for: identity, generation: requestGeneration)
            return
        }

        mutateState { state in
            _ = state.apply(
                snapshot: snapshot,
                for: identity,
                generation: requestGeneration
            )
        }
    }

    private func enqueueLoad(
        for identity: TorrentDetailIdentity,
        using store: TransmissionStore,
        onError: @escaping @MainActor @Sendable (String) -> Void
    ) -> Task<Void, Never> {
        let predecessor = loadQueueTail
        loadQueueGeneration += 1
        let generation = loadQueueGeneration
        pendingLoadCounts[identity, default: 0] += 1

        let task = Task { @MainActor [weak self] in
            await predecessor?.value
            guard let self else { return }
            defer {
                self.finishPendingLoad(for: identity)
                self.clearLoadQueueTail(ifMatching: generation)
            }
            guard !Task.isCancelled else { return }

            await self.performLoad(for: identity, using: store, onError: onError)
        }

        loadQueueTail = task
        return task
    }

    func refresh(
        for identity: TorrentDetailIdentity,
        using store: TransmissionStore,
        onInitialLoadError: @escaping @MainActor @Sendable (String) -> Void
    ) async {
        await load(for: identity, using: store) { message in
            guard self.state.shouldReportInitialLoadError(for: identity) else {
                return
            }
            let didMarkReported = self.mutateState {
                $0.markInitialLoadErrorReported(for: identity)
            }
            guard didMarkReported else { return }
            onInitialLoadError(message)
        }
    }

    func observeRefreshes(
        for identity: TorrentDetailIdentity,
        using store: TransmissionStore,
        onInitialLoadError: @escaping @MainActor @Sendable (String) -> Void
    ) async {
        var processedRevision: UInt64?

        for await publishedTrigger in store.$torrentDetailRefreshTrigger.values {
            guard !Task.isCancelled else { return }
            guard publishedTrigger.connectionGeneration == identity.connectionGeneration else { return }
            guard processedRevision.map({ publishedTrigger.revision > $0 }) ?? true else {
                continue
            }

            var requestedRevision = publishedTrigger.revision

            while true {
                await refresh(
                    for: identity,
                    using: store,
                    onInitialLoadError: onInitialLoadError
                )

                guard !Task.isCancelled else { return }
                processedRevision = requestedRevision

                let latestTrigger = store.torrentDetailRefreshTrigger
                guard latestTrigger.connectionGeneration == identity.connectionGeneration else { return }
                guard latestTrigger.revision > requestedRevision else { break }

                requestedRevision = latestTrigger.revision
            }
        }
    }

    func loadIfIdle(
        for identity: TorrentDetailIdentity,
        using store: TransmissionStore,
        onError: @escaping @MainActor @Sendable (String) -> Void
    ) async {
        guard pendingLoadCounts[identity, default: 0] == 0 else {
            return
        }

        guard !state.shouldDisplayPayload(for: identity) else {
            return
        }

        guard state.status == .idle else {
            return
        }

        await load(for: identity, using: store, onError: onError)
    }

    private func finishPendingLoad(for identity: TorrentDetailIdentity) {
        guard let count = pendingLoadCounts[identity] else {
            return
        }

        if count == 1 {
            pendingLoadCounts.removeValue(forKey: identity)
        } else {
            pendingLoadCounts[identity] = count - 1
        }
    }

    @discardableResult
    private func markFailure(for identity: TorrentDetailIdentity, generation: Int) -> Bool {
        mutateState { $0.markFailed(for: identity, generation: generation) }
    }

    @discardableResult
    private func markCancellation(for identity: TorrentDetailIdentity, generation: Int) -> Bool {
        mutateState { $0.markCancelled(for: identity, generation: generation) }
    }

    private func clearManagedLoadTask(ifMatching generation: Int) {
        guard managedLoadGeneration == generation else {
            return
        }

        managedLoadTask = nil
    }

    private func clearLoadQueueTail(ifMatching generation: Int) {
        guard loadQueueGeneration == generation else {
            return
        }

        loadQueueTail = nil
    }

    @discardableResult
    private func mutateState<Result>(
        _ mutate: (inout TorrentDetailSupplementalState) -> Result
    ) -> Result {
        var nextState = state
        let result = mutate(&nextState)
        state = nextState
        return result
    }
}

private extension TorrentFileStats {
    func applying(_ mutation: TorrentDetailFileStatsMutation) -> Self {
        switch mutation {
        case .wanted(let wanted):
            TorrentFileStats(
                bytesCompleted: bytesCompleted,
                wanted: wanted,
                priority: priority
            )
        case .priority(let priority):
            TorrentFileStats(
                bytesCompleted: bytesCompleted,
                wanted: wanted,
                priority: priority.rawValue
            )
        }
    }
}

internal struct TorrentDetailSupplementalPlaceholder: View {
    let status: TorrentDetailSupplementalLoadStatus
    let loadingTitle: String
    let loadingMessage: String
    let unavailableTitle: String
    let unavailableMessage: String
    let onLoadIfIdle: @Sendable () async -> Void
    let onRetry: () -> Void

    var body: some View {
        switch status {
        case .idle:
            TorrentDetailLoadingPlaceholderView(title: loadingTitle, message: loadingMessage)
                .task { await onLoadIfIdle() }
        case .loading:
            TorrentDetailLoadingPlaceholderView(title: loadingTitle, message: loadingMessage)
        case .failed:
            TorrentDetailUnavailablePlaceholderView(
                title: unavailableTitle,
                message: unavailableMessage,
                actionTitle: "Retry",
                action: onRetry
            )
        case .loaded:
            EmptyView()
        }
    }
}

internal struct TorrentDetailLoadingPlaceholderView: View {
    let title: String
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "arrow.triangle.2.circlepath")
        } description: {
            Text(message)
        } actions: {
            ProgressView()
        }
    }
}

internal struct TorrentDetailUnavailablePlaceholderView: View {
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
        ContentUnavailableView {
            Label(title, systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
            }
        }
    }
}

// Shared function to determine torrent status color
func statusColor(for torrent: Torrent) -> Color {
    if torrent.statusCalc == TorrentStatusCalc.complete || torrent.statusCalc == TorrentStatusCalc.seeding {
        return .green.opacity(0.9)
    } else if torrent.statusCalc == TorrentStatusCalc.paused {
        return .gray
    } else if torrent.statusCalc == TorrentStatusCalc.retrievingMetadata {
        return .red.opacity(0.9)
    } else if torrent.statusCalc == TorrentStatusCalc.stalled {
        return .orange.opacity(0.9)
    } else {
        return .blue.opacity(0.9)
    }
}

struct TorrentDetailsDisplay {
    let percentComplete: String
    let percentAvailable: String
    let downloadedFormatted: String
    let sizeWhenDoneFormatted: String
    let uploadedFormatted: String
    let uploadRatio: String
    let activityDate: String
    let addedDate: String
}

// Shared function to format torrent details
func formatTorrentDetails(torrent: Torrent) -> TorrentDetailsDisplay {

    let percentComplete = String(format: "%.1f%%", torrent.percentDone * 100)
    let percentAvailable = String(format: "%.1f%%", ((Double(torrent.haveUnchecked + torrent.haveValid + torrent.desiredAvailable) / Double(torrent.sizeWhenDone))) * 100)
    let downloadedFormatted = formatByteCount(torrent.downloadedCalc)
    let sizeWhenDoneFormatted = formatByteCount(torrent.sizeWhenDone)
    let uploadedFormatted = formatByteCount(torrent.uploadedEver)
    let uploadRatio = torrent.uploadRatio.displayText

    let activityDate = formatTorrentDetailDate(torrent.activityDate)
    let addedDate = formatTorrentDetailDate(torrent.addedDate)

    return TorrentDetailsDisplay(
        percentComplete: percentComplete,
        percentAvailable: percentAvailable,
        downloadedFormatted: downloadedFormatted,
        sizeWhenDoneFormatted: sizeWhenDoneFormatted,
        uploadedFormatted: uploadedFormatted,
        uploadRatio: uploadRatio,
        activityDate: activityDate,
        addedDate: addedDate
    )
}

// Shared header view for both platforms
struct TorrentDetailHeaderView: View {
    var torrent: Torrent

    var body: some View {
        HStack {
            Spacer()

            HStack(spacing: 8) {
                RatioChip(
                    uploadRatio: torrent.uploadRatio,
                    size: .compact
                )

                SpeedChip(
                    speed: torrent.rateDownload,
                    direction: .download,
                    style: .chip,
                    size: .compact
                )

                SpeedChip(
                    speed: torrent.rateUpload,
                    direction: .upload,
                    style: .chip,
                    size: .compact
                )
            }

            Spacer()
        }
    }
}

// Shared toolbar menu for both platforms
struct TorrentDetailToolbar: ToolbarContent {
    var torrent: Torrent
    var store: TransmissionStore

    var body: some ToolbarContent {
        #if os(macOS)
        ToolbarItem {
            // In detail view, actions apply to the displayed torrent
            TorrentActionsToolbarMenu(
                store: store,
                selectedTorrents: Set([torrent])
            )
        }
        #else
        ToolbarItem {
            Menu {
                Button(action: {
                    performTransmissionAction(
                        operation: { try await store.toggleTorrentPlayback(torrent) },
                        onError: makeTransmissionDebugErrorHandler(
                            store: store,
                            context: torrent.status == TorrentStatus.stopped.rawValue
                                ? .resumeTorrents
                                : .pauseTorrents
                        )
                    )
                }, label: {
                    HStack {
                        Text(torrent.status == TorrentStatus.stopped.rawValue ? "Resume Dream" : "Pause Dream")
                    }
                })
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
        #endif
    }
}

// Shared status badge component for torrent status
struct TorrentStatusBadge: View {
    let torrent: Torrent

    var body: some View {
        Text(torrent.statusCalc.rawValue)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundColor(statusColor(for: torrent))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(statusColor(for: torrent).opacity(0.15))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(statusColor(for: torrent).opacity(0.3), lineWidth: 0.5)
            )
            .cornerRadius(6)
    }
}

// Shared label tag component for detail views
struct DetailViewLabelTag: View {
    let label: String
    var isLarge: Bool = false

    var body: some View {
        Text(label)
            .font(isLarge ? .subheadline : .caption)
            .fontWeight(.medium)
            .padding(.horizontal, isLarge ? 8 : 6)
            .padding(.vertical, isLarge ? 4 : 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.accentColor.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
            )
            .foregroundColor(.primary)
    }
}

private func formatTorrentDetailDate(_ timestamp: Int) -> String {
    let date = Date(timeIntervalSince1970: Double(timestamp))
    return date.formatted(
        Date.FormatStyle()
            .locale(Locale(identifier: "en_US_POSIX"))
            .month(.twoDigits)
            .day(.twoDigits)
            .year(.defaultDigits)
    )
}
