import Foundation
import SwiftUI

#if os(macOS)

struct TorrentActionsToolbarMenu: View {
    let store: Store
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
    @State private var renameTargetId: Int? = nil
    @State private var moveDialog: Bool = false
    @State private var movePath: String = ""
    @State private var moveShouldMove: Bool = true

    var body: some View {
        Menu {
            if selectedTorrents.isEmpty {
                Text("Select a Dream")
                    .foregroundColor(.secondary)
                    .disabled(true)
            } else {
                createTorrentContextMenu(
                    torrents: selectedTorrents,
                    store: store,
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
                    torrentIds: Array(torrents.map { $0.id }),
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
                    for t in selectedTorrents {
                        deleteTorrent(torrent: t, erase: true, config: info.config, auth: info.auth, onDel: { response in
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
                    for t in selectedTorrents {
                        deleteTorrent(torrent: t, erase: false, config: info.config, auth: info.auth, onDel: { response in
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
            if let t = targetTorrent {
                RenameSheetView(
                    title: "Rename Torrent",
                    name: $renameInput,
                    currentName: t.name,
                    onCancel: {
                        renameDialog = false
                    },
                    onSave: { newName in
                        if let validation = validateNewName(newName, current: t.name) {
                            errorMessage = validation
                            showingError = true
                            return
                        }
                        renameTorrentRoot(torrent: t, to: newName, store: store) { err in
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
    let store: Store
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
                torrentIds: Array(selectedTorrents.map { $0.id }),
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
    let store: Store
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
            if let t = targetTorrent {
                RenameSheetView(
                    title: "Rename Torrent",
                    name: $renameInput,
                    currentName: t.name,
                    onCancel: {
                        isPresented = false
                    },
                    onSave: { newName in
                        if let validation = validateNewName(newName, current: t.name) {
                            errorMessage = validation
                            showingError = true
                            return
                        }
                        renameTorrentRoot(torrent: t, to: newName, store: store) { err in
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
        store: Store,
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
                for t in set {
                    deleteTorrent(torrent: t, erase: true, config: info.config, auth: info.auth, onDel: { response in
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
                for t in set {
                    deleteTorrent(torrent: t, erase: false, config: info.config, auth: info.auth, onDel: { response in
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