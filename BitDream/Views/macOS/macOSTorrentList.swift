import Foundation
import SwiftUI

#if os(macOS)

struct LinearTorrentProgressStyle: ProgressViewStyle {
    let color: Color
    let trackOpacity: Double
    let height: CGFloat

    init(color: Color, trackOpacity: Double = 0.25, height: CGFloat = 6) {
        self.color = color
        self.trackOpacity = trackOpacity
        self.height = height
    }

    func makeBody(configuration: Configuration) -> some View {
        GeometryReader { geometry in
            let fractionCompleted = max(0, min(1, configuration.fractionCompleted ?? 0))
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(Color.secondary.opacity(trackOpacity))

                RoundedRectangle(cornerRadius: height / 2)
                    .fill(color)
                    .frame(width: geometry.size.width * CGFloat(fractionCompleted))
            }
        }
        .frame(height: height)
        .padding(.vertical, 2)
    }
}

@MainActor
struct TorrentRowModifier: ViewModifier {
    var torrent: Torrent
    var selectedTorrents: Set<Torrent>
    let store: TransmissionStore
    @Binding var deleteDialog: Bool
    @Binding var labelDialog: Bool
    @Binding var labelInput: String
    @Binding var shouldSave: Bool
    @Binding var showingError: Bool
    @Binding var errorMessage: String
    @Binding var renameDialog: Bool
    @Binding var renameInput: String
    @Binding var renameTargetId: Int?
    @State private var moveDialog: Bool = false
    @State private var movePath: String = ""
    @State private var moveShouldMove: Bool = true

    private var affectedTorrents: Set<Torrent> {
        if selectedTorrents.isEmpty {
            return Set([torrent])
        }
        return selectedTorrents.contains(torrent) ? selectedTorrents : Set([torrent])
    }

    private var dialogState: TorrentActionDialogState {
        TorrentActionDialogState(
            labelInput: $labelInput,
            labelDialog: $labelDialog,
            deleteDialog: $deleteDialog,
            renameInput: $renameInput,
            renameDialog: $renameDialog,
            renameTargetId: $renameTargetId,
            movePath: $movePath,
            moveDialog: $moveDialog,
            moveShouldMove: $moveShouldMove,
            showingError: $showingError,
            errorMessage: $errorMessage
        )
    }

    func body(content: Content) -> some View {
        content
            .contextMenu {
                TorrentContextMenu(
                    torrents: affectedTorrents,
                    store: store,
                    dialogState: dialogState
                )
            }
            .tint(.primary)
            .id(torrent.id)
            .sheet(isPresented: $labelDialog, content: labelSheet)
            .torrentDeleteAlert(
                isPresented: $deleteDialog,
                selectedTorrents: { affectedTorrents },
                store: store,
                showingError: $showingError,
                errorMessage: $errorMessage
            )
            .interactiveDismissDisabled(false)
            .transmissionErrorAlert(isPresented: $showingError, message: errorMessage)
            .sheet(isPresented: $renameDialog, content: renameSheet)
            .sheet(isPresented: $moveDialog, content: moveSheet)
    }

    private func labelSheet() -> some View {
        LabelEditSheetContent(
            store: store,
            selectedTorrents: affectedTorrents,
            labelInput: $labelInput,
            shouldSave: $shouldSave,
            isPresented: $labelDialog,
            showingError: $showingError,
            errorMessage: $errorMessage
        )
        .frame(width: 400)
    }

    private func renameSheet() -> some View {
        RenameSheetContent(
            store: store,
            selectedTorrents: affectedTorrents,
            renameInput: $renameInput,
            renameTargetId: $renameTargetId,
            isPresented: $renameDialog,
            showingError: $showingError,
            errorMessage: $errorMessage
        )
        .frame(width: 420)
        .padding()
    }

    private func moveSheet() -> some View {
        MoveSheetContent(
            store: store,
            selectedTorrents: affectedTorrents,
            movePath: $movePath,
            moveShouldMove: $moveShouldMove,
            isPresented: $moveDialog,
            showingError: $showingError,
            errorMessage: $errorMessage
        )
        .frame(width: 480)
        .padding()
    }
}

#endif
