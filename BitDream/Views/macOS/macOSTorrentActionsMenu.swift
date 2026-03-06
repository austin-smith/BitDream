import Foundation
import SwiftUI

#if os(macOS)

struct TorrentActionDialogState {
    let labelInput: Binding<String>
    let labelDialog: Binding<Bool>
    let deleteDialog: Binding<Bool>
    let renameInput: Binding<String>
    let renameDialog: Binding<Bool>
    let renameTargetId: Binding<Int?>
    let movePath: Binding<String>
    let moveDialog: Binding<Bool>
    let moveShouldMove: Binding<Bool>
    let showingError: Binding<Bool>
    let errorMessage: Binding<String>

    func presentError(_ message: String) {
        errorMessage.wrappedValue = message
        showingError.wrappedValue = true
    }
}

@MainActor
struct TorrentContextMenu: View {
    let torrents: Set<Torrent>
    let store: AppStore
    let dialogState: TorrentActionDialogState

    private var firstTorrent: Torrent? {
        torrents.first
    }

    private var torrentIDs: [Int] {
        Array(torrents.map(\.id))
    }

    var body: some View {
        if let firstTorrent {
            playbackSection
            Divider()
            prioritySection
            queueSection
            Divider()
            locationButton
            renameButton(for: firstTorrent)
            editLabelsButton
            Divider()
            copyMagnetLinkButton(for: firstTorrent)
            Divider()
            reannounceButton
            verifyButton
            Divider()
            deleteButton
        }
    }

    private var playbackSection: some View {
        Group {
            Button(action: pauseTorrentsAction) {
                Label("Pause", systemImage: "pause")
            }
            .disabled(torrents.shouldDisablePause)

            Button(action: resumeTorrentsAction) {
                Label("Resume", systemImage: "play")
            }
            .disabled(torrents.shouldDisableResume)

            Button(action: resumeNowAction) {
                Label("Resume Now", systemImage: "play.fill")
            }
            .disabled(torrents.shouldDisableResume)
        }
    }

    private var prioritySection: some View {
        Menu("Update Priority", systemImage: "flag.badge.ellipsis") {
            Button("High", systemImage: "arrow.up") {
                updatePriority(.high)
            }
            Button("Normal", systemImage: "minus") {
                updatePriority(.normal)
            }
            Button("Low", systemImage: "arrow.down") {
                updatePriority(.low)
            }
        }
    }

    private var queueSection: some View {
        Menu("Move in Queue", systemImage: "line.3.horizontal") {
            Button("Move to Front", systemImage: "arrow.up.to.line") {
                queueMoveTopAction()
            }
            Button("Move Up", systemImage: "arrow.up") {
                queueMoveUpAction()
            }
            Button("Move Down", systemImage: "arrow.down") {
                queueMoveDownAction()
            }
            Button("Move to Back", systemImage: "arrow.down.to.line") {
                queueMoveBottomAction()
            }
        }
    }

    private var locationButton: some View {
        Button(action: showMoveDialog) {
            Label("Set Location…", systemImage: "folder.badge.gearshape")
        }
    }

    private func renameButton(for torrent: Torrent) -> some View {
        Button(action: {
            dialogState.renameInput.wrappedValue = torrent.name
            dialogState.renameTargetId.wrappedValue = torrent.id
            dialogState.renameDialog.wrappedValue = true
        }, label: {
            Label("Rename…", systemImage: "pencil")
        })
        .disabled(torrents.count != 1)
    }

    private var editLabelsButton: some View {
        Button(action: showLabelDialog, label: {
            Label("Edit Labels…", systemImage: "tag")
        })
    }

    private func copyMagnetLinkButton(for torrent: Torrent) -> some View {
        Button(action: {
            copyMagnetLinkToClipboard(torrent.magnetLink)
        }, label: {
            Label("Copy Magnet Link", systemImage: "document.on.document")
        })
        .disabled(torrents.count != 1)
    }

    private var reannounceButton: some View {
        Button(action: reannounceTorrentsAction, label: {
            Label("Ask For More Peers", systemImage: "arrow.left.arrow.right")
        })
    }

    private var verifyButton: some View {
        Button(action: verifyTorrentsAction) {
            Label("Verify Local Data", systemImage: "checkmark.arrow.trianglehead.counterclockwise")
        }
    }

    private var deleteButton: some View {
        Button(role: .destructive, action: {
            dialogState.deleteDialog.wrappedValue.toggle()
        }, label: {
            Label("Delete…", systemImage: "trash")
        })
    }

    private func pauseTorrentsAction() {
        TorrentActionExecutor.pause(ids: torrentIDs, store: store) { error in
            dialogState.presentError(error)
        }
    }

    private func resumeTorrentsAction() {
        TorrentActionExecutor.resume(ids: torrentIDs, store: store) { error in
            dialogState.presentError(error)
        }
    }

    private func resumeNowAction() {
        TorrentActionExecutor.resumeNow(torrents: Array(torrents), store: store) { error in
            dialogState.presentError(error)
        }
    }

    private func updatePriority(_ priority: TorrentPriority) {
        let info = makeConfig(store: store)
        updateTorrent(
            args: TorrentSetRequestArgs(ids: torrentIDs, priority: priority),
            info: info,
            onComplete: { _ in }
        )
    }

    private func queueMoveTopAction() {
        TorrentActionExecutor.moveInQueue(.top, ids: torrentIDs, store: store) { error in
            dialogState.presentError(error)
        }
    }

    private func queueMoveUpAction() {
        TorrentActionExecutor.moveInQueue(.upward, ids: torrentIDs, store: store) { error in
            dialogState.presentError(error)
        }
    }

    private func queueMoveDownAction() {
        TorrentActionExecutor.moveInQueue(.downward, ids: torrentIDs, store: store) { error in
            dialogState.presentError(error)
        }
    }

    private func queueMoveBottomAction() {
        TorrentActionExecutor.moveInQueue(.bottom, ids: torrentIDs, store: store) { error in
            dialogState.presentError(error)
        }
    }

    private func showMoveDialog() {
        dialogState.movePath.wrappedValue = store.defaultDownloadDir
        dialogState.moveDialog.wrappedValue = true
    }

    private func showLabelDialog() {
        if torrents.count == 1 {
            dialogState.labelInput.wrappedValue = firstTorrent?.labels.joined(separator: ", ") ?? ""
        } else {
            dialogState.labelInput.wrappedValue = ""
        }
        dialogState.labelDialog.wrappedValue.toggle()
    }

    private func verifyTorrentsAction() {
        TorrentActionExecutor.verify(torrents: Array(torrents), store: store) { error in
            dialogState.presentError(error)
        }
    }

    private func reannounceTorrentsAction() {
        TorrentActionExecutor.reannounce(torrents: Array(torrents), store: store) { error in
            dialogState.presentError(error)
        }
    }
}

struct TorrentActionsToolbarMenu: View {
    let store: AppStore
    let selectedTorrents: Set<Torrent>

    // Shared state used by the context menu builder
    @State private var deleteDialog: Bool = false
    @State private var labelDialog: Bool = false
    @State private var labelInput: String = ""
    @State private var shouldSave: Bool = false
    @State private var showingError: Bool = false
    @State private var errorMessage: String = ""
    @State private var renameDialog: Bool = false
    @State private var renameInput: String = ""
    @State private var renameTargetId: Int?
    @State private var moveDialog: Bool = false
    @State private var movePath: String = ""
    @State private var moveShouldMove: Bool = true

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

    var body: some View {
        Menu {
            if selectedTorrents.isEmpty {
                Text("Select a Dream")
                    .foregroundColor(.secondary)
                    .disabled(true)
            } else {
                TorrentContextMenu(
                    torrents: selectedTorrents,
                    store: store,
                    dialogState: dialogState
                )
            }
        } label: {
            Label("Actions", systemImage: "ellipsis.circle")
        }
        .sheet(isPresented: $labelDialog) {
            let torrents = selectedTorrents
            let titleSuffix = torrents.count > 1 ? " (\(torrents.count) torrents)" : ""
            VStack(spacing: 16) {
                Text("Edit Labels\(titleSuffix)")
                    .font(.headline)

                LabelEditView(
                    labelInput: $labelInput,
                    existingLabels: torrents.count == 1 ? Array(torrents.first!.labels) : [],
                    store: store,
                    selectedTorrents: torrents,
                    shouldSave: $shouldSave
                )

                HStack {
                    Button("Cancel") {
                        labelDialog = false
                    }
                    .keyboardShortcut(.escape)

                    Button("Save") {
                        shouldSave = true
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .frame(width: 400)
        }
        .alert(
            "Delete \(selectedTorrents.count > 1 ? "\(selectedTorrents.count) Torrents" : "Torrent")",
            isPresented: $deleteDialog) {
                Button(role: .destructive) {
                    let info = makeConfig(store: store)
                    for torrent in selectedTorrents {
                        deleteTorrent(torrent: torrent, erase: true, config: info.config, auth: info.auth, onDel: { response in
                            handleTransmissionResponse(response,
                                onSuccess: {
                                    // Success - torrent deleted
                                },
                                onError: { error in
                                    errorMessage = error
                                    showingError = true
                                }
                            )
                        })
                    }
                    deleteDialog.toggle()
                } label: {
                    Text("Delete file(s)")
                }
                Button("Remove from list only") {
                    let info = makeConfig(store: store)
                    for torrent in selectedTorrents {
                        deleteTorrent(torrent: torrent, erase: false, config: info.config, auth: info.auth, onDel: { response in
                            handleTransmissionResponse(response,
                                onSuccess: {
                                    // Success - torrent removed from list
                                },
                                onError: { error in
                                    errorMessage = error
                                    showingError = true
                                }
                            )
                        })
                    }
                    deleteDialog.toggle()
                }
            } message: {
                Text("Do you want to delete the file(s) from the disk?")
            }
        .transmissionErrorAlert(isPresented: $showingError, message: errorMessage)
        .sheet(isPresented: $renameDialog) {
            // Resolve target torrent using captured id or current selection
            let targetTorrent: Torrent? = {
                if let id = renameTargetId {
                    return store.torrents.first { $0.id == id }
                }
                return selectedTorrents.first
            }()
            if let targetTorrent {
                RenameSheetView(
                    title: "Rename Torrent",
                    name: $renameInput,
                    currentName: targetTorrent.name,
                    onCancel: {
                        renameDialog = false
                    },
                    onSave: { newName in
                        if let validation = validateNewName(newName, current: targetTorrent.name) {
                            errorMessage = validation
                            showingError = true
                            return
                        }
                        renameTorrentRoot(torrent: targetTorrent, to: newName, store: store) { err in
                            if let err = err {
                                errorMessage = err
                                showingError = true
                            } else {
                                renameDialog = false
                            }
                        }
                    }
                )
                .frame(width: 420)
                .padding()
            }
        }
        .sheet(isPresented: $moveDialog) {
            MoveSheetContent(
                store: store,
                selectedTorrents: selectedTorrents,
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
}

// MARK: - Shared Presenters for Sheets/Alerts

struct LabelEditSheetContent: View {
    let store: AppStore
    let selectedTorrents: Set<Torrent>
    @Binding var labelInput: String
    @Binding var shouldSave: Bool
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 16) {
            Text("Edit Labels\(selectedTorrents.count > 1 ? " (\(selectedTorrents.count) torrents)" : "")")
                .font(.headline)

            LabelEditView(
                labelInput: $labelInput,
                existingLabels: selectedTorrents.count == 1 ? Array(selectedTorrents.first!.labels) : [],
                store: store,
                selectedTorrents: selectedTorrents,
                shouldSave: $shouldSave
            )

            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.escape)

                Button("Save") {
                    shouldSave = true
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }
}

struct RenameSheetContent: View {
    let store: AppStore
    let selectedTorrents: Set<Torrent>
    @Binding var renameInput: String
    @Binding var renameTargetId: Int?
    @Binding var isPresented: Bool
    @Binding var showingError: Bool
    @Binding var errorMessage: String

    var body: some View {
        let targetTorrent: Torrent? = {
            if let id = renameTargetId {
                return store.torrents.first { $0.id == id }
            }
            return selectedTorrents.count == 1 ? selectedTorrents.first : nil
        }()
        Group {
            if let targetTorrent {
                RenameSheetView(
                    title: "Rename Torrent",
                    name: $renameInput,
                    currentName: targetTorrent.name,
                    onCancel: {
                        isPresented = false
                    },
                    onSave: { newName in
                        if let validation = validateNewName(newName, current: targetTorrent.name) {
                            errorMessage = validation
                            showingError = true
                            return
                        }
                        renameTorrentRoot(torrent: targetTorrent, to: newName, store: store) { err in
                            if let err = err {
                                errorMessage = err
                                showingError = true
                            } else {
                                isPresented = false
                            }
                        }
                    }
                )
            }
        }
    }
}

extension View {
    func torrentDeleteAlert(
        isPresented: Binding<Bool>,
        selectedTorrents: @escaping () -> Set<Torrent>,
        store: AppStore,
        showingError: Binding<Bool>,
        errorMessage: Binding<String>
    ) -> some View {
        let set = selectedTorrents()
        let title = "Delete \(set.count > 1 ? "\(set.count) Torrents" : "Torrent")"
        return self.alert(
            title,
            isPresented: isPresented
        ) {
            Button(role: .destructive) {
                let info = makeConfig(store: store)
                for torrent in set {
                    deleteTorrent(torrent: torrent, erase: true, config: info.config, auth: info.auth, onDel: { response in
                        handleTransmissionResponse(response,
                            onSuccess: {},
                            onError: { error in
                                errorMessage.wrappedValue = error
                                showingError.wrappedValue = true
                            }
                        )
                    })
                }
                isPresented.wrappedValue.toggle()
            } label: {
                Text("Delete file(s)")
            }
            Button("Remove from list only") {
                let info = makeConfig(store: store)
                for torrent in set {
                    deleteTorrent(torrent: torrent, erase: false, config: info.config, auth: info.auth, onDel: { response in
                        handleTransmissionResponse(response,
                            onSuccess: {},
                            onError: { error in
                                errorMessage.wrappedValue = error
                                showingError.wrappedValue = true
                            }
                        )
                    })
                }
                isPresented.wrappedValue.toggle()
            }
        } message: {
            Text("Do you want to delete the file(s) from the disk?")
        }
    }
}

#endif
