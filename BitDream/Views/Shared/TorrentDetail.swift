import Foundation
import SwiftUI

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

internal struct TorrentDetailSupplementalPayload: Sendable, Equatable {
    let files: [TorrentFile]
    let fileStats: [TorrentFileStats]
    let peers: [Peer]
    let peersFrom: PeersFrom?
    let pieceCount: Int
    let pieceSize: Int64
    let piecesBitfieldBase64: String
    let piecesHaveCount: Int

    static let empty = TorrentDetailSupplementalPayload(
        files: [],
        fileStats: [],
        peers: [],
        peersFrom: nil,
        pieceCount: 0,
        pieceSize: 0,
        piecesBitfieldBase64: "",
        piecesHaveCount: 0
    )

    init(
        files: [TorrentFile],
        fileStats: [TorrentFileStats],
        peers: [Peer],
        peersFrom: PeersFrom?,
        pieceCount: Int,
        pieceSize: Int64,
        piecesBitfieldBase64: String,
        piecesHaveCount: Int
    ) {
        self.files = files
        self.fileStats = fileStats
        self.peers = peers
        self.peersFrom = peersFrom
        self.pieceCount = pieceCount
        self.pieceSize = pieceSize
        self.piecesBitfieldBase64 = piecesBitfieldBase64
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
            piecesBitfieldBase64: snapshot.piecesBitfieldBase64,
            piecesHaveCount: haveSet.reduce(0) { $0 + ($1 ? 1 : 0) }
        )
    }
}

internal struct TorrentDetailSupplementalState: Sendable {
    private(set) var activeTorrentID: Int?
    private(set) var activeRequestGeneration: Int = 0
    private(set) var status: TorrentDetailSupplementalLoadStatus = .idle
    private(set) var payload: TorrentDetailSupplementalPayload = .empty
    private(set) var hasLoadedPayload = false

    var shouldDisplayPayload: Bool {
        hasLoadedPayload
    }

    @discardableResult
    mutating func beginLoading(for torrentID: Int) -> Int {
        if activeTorrentID != torrentID {
            payload = .empty
            hasLoadedPayload = false
        }

        activeTorrentID = torrentID
        activeRequestGeneration += 1
        status = .loading
        return activeRequestGeneration
    }

    @discardableResult
    mutating func apply(
        snapshot: TransmissionTorrentDetailSnapshot,
        for torrentID: Int,
        generation: Int
    ) -> Bool {
        guard activeTorrentID == torrentID, activeRequestGeneration == generation else {
            return false
        }

        status = .loaded
        payload = TorrentDetailSupplementalPayload(snapshot: snapshot)
        hasLoadedPayload = true
        return true
    }

    @discardableResult
    mutating func markFailed(for torrentID: Int, generation: Int) -> Bool {
        guard activeTorrentID == torrentID, activeRequestGeneration == generation else {
            return false
        }

        status = .failed
        return true
    }
}

@MainActor
internal final class TorrentDetailSupplementalStore: ObservableObject {
    @Published private(set) var state = TorrentDetailSupplementalState()

    var payload: TorrentDetailSupplementalPayload {
        state.payload
    }

    var status: TorrentDetailSupplementalLoadStatus {
        state.status
    }

    var shouldDisplayPayload: Bool {
        state.shouldDisplayPayload
    }

    func load(
        for torrentID: Int,
        using store: TransmissionStore,
        onError: @escaping @MainActor @Sendable (String) -> Void
    ) async {
        let requestGeneration = mutateState { state in
            state.beginLoading(for: torrentID)
        }

        guard let snapshot = await performStructuredTransmissionOperation(
            operation: { try await store.loadTorrentDetail(id: torrentID) },
            onError: { [weak self] message in
                guard let self else { return }
                guard self.markFailure(for: torrentID, generation: requestGeneration) else {
                    return
                }
                onError(message)
            }
        ) else {
            return
        }

        mutateState { state in
            _ = state.apply(
                snapshot: snapshot,
                for: torrentID,
                generation: requestGeneration
            )
        }
    }

    func loadIfNeeded(
        for torrentID: Int,
        using store: TransmissionStore,
        onError: @escaping @MainActor @Sendable (String) -> Void
    ) async {
        guard !state.shouldDisplayPayload else {
            return
        }

        guard state.status != .loading else {
            return
        }

        await load(for: torrentID, using: store, onError: onError)
    }

    @discardableResult
    private func markFailure(for torrentID: Int, generation: Int) -> Bool {
        var nextState = state
        let didMarkFailure = nextState.markFailed(for: torrentID, generation: generation)
        state = nextState
        return didMarkFailure
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

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
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
    let uploadRatio = String(format: "%.2f", torrent.uploadRatio)

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
                    ratio: torrent.uploadRatio,
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
