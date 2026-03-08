import Foundation
import SwiftUI

#if os(iOS)
struct iOSTorrentListRow: View {
    var torrent: Torrent
    var store: TransmissionStore
    var showContentTypeIcons: Bool

    @State private var deleteDialog: Bool = false
    @State private var labelDialog: Bool = false
    @State private var labelInput: String = ""
    @State private var renameDialog: Bool = false
    @State private var renameInput: String = ""
    @State private var moveDialog: Bool = false
    @State private var movePath: String = ""
    @State private var moveShouldMove: Bool = true
    @State private var showingError = false
    @State private var errorMessage = ""

    var body: some View {
        rowContent
            .contentShape(Rectangle())
            .padding(10)
            .swipeActions(edge: .trailing) {
                swipeActions
            }
            .contextMenu { actionsMenu }
            .id(torrent.id)
            .confirmationDialog(
                "Delete Torrent",
                isPresented: $deleteDialog,
                titleVisibility: .visible
            ) {
                Button("Delete file(s)", role: .destructive) {
                    performDelete(erase: true)
                }
                Button("Remove from list only") {
                    performDelete(erase: false)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Do you want to delete the file(s) from the disk?")
            }
            .transmissionErrorAlert(isPresented: $showingError, message: errorMessage)
            .sheet(isPresented: $renameDialog, content: renameSheet)
            .sheet(isPresented: $moveDialog, content: moveSheet)
            .sheet(isPresented: $labelDialog, content: labelSheet)
    }

    private var rowContent: some View {
        HStack(spacing: 12) {
            if showContentTypeIcons {
                Image(systemName: ContentTypeIconMapper.symbolForTorrent(mimeType: torrent.primaryMimeType))
                    .font(.system(size: 16))
                    .foregroundColor(.secondary.opacity(0.6))
                    .frame(width: 20, height: 20)
            }

            VStack(spacing: 4) {
                HStack(spacing: 8) {
                    Text(torrent.name)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(1)

                    createLabelTagsView(for: torrent)
                }

                createStatusView(for: torrent)
                    .font(.custom("sub", size: 10))
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .foregroundColor(.secondary)

                ProgressView(value: torrent.metadataPercentComplete < 1 ? 1 : torrent.percentDone)
                    .tint(progressColorForTorrent(torrent))

                Text(formatTorrentSubtext(torrent))
                    .font(.custom("sub", size: 10))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var actionsMenu: some View {
        IOSTorrentActionsMenu(
            torrent: torrent,
            store: store,
            onShowMove: showMoveDialog,
            onShowRename: showRenameDialog,
            onShowLabels: { labelDialog = true },
            onShowDelete: { deleteDialog = true },
            onError: presentError
        )
    }

    @ViewBuilder
    private var swipeActions: some View {
        Button(action: togglePlayback) {
            Image(systemName: torrent.status == TorrentStatus.stopped.rawValue ? "play.fill" : "pause.fill")
        }
        .tint(torrent.status == TorrentStatus.stopped.rawValue ? .blue : .orange)

        Menu {
            actionsMenu
        } label: {
            Image(systemName: "ellipsis.circle")
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

    private func togglePlayback() {
        performTransmissionAction(
            operation: { try await store.toggleTorrentPlayback(torrent) },
            onError: presentError
        )
    }

    private func performDelete(erase: Bool) {
        performTransmissionAction(
            operation: { try await store.removeTorrents(ids: [torrent.id], deleteLocalData: erase) },
            onError: presentError
        )
    }

    private func showRenameDialog() {
        renameInput = torrent.name
        renameDialog = true
    }

    private func showMoveDialog() {
        movePath = store.defaultDownloadDir
        moveDialog = true
    }

    private func presentError(_ error: String) {
        errorMessage = error
        showingError = true
    }
}

@MainActor
private struct IOSTorrentActionsMenu: View {
    let torrent: Torrent
    let store: TransmissionStore
    let onShowMove: () -> Void
    let onShowRename: () -> Void
    let onShowLabels: () -> Void
    let onShowDelete: () -> Void
    let onError: @MainActor @Sendable (String) -> Void

    var body: some View {
        playbackSection
        Divider()
        prioritySection
        queueSection
        Divider()
        Button("Set Location…", systemImage: "folder.badge.gearshape", action: onShowMove)
        Button("Rename…", systemImage: "pencil", action: onShowRename)
        Button("Edit Labels…", systemImage: "tag", action: onShowLabels)
        Divider()
        Button("Copy Magnet Link", systemImage: "document.on.document") {
            copyMagnetLinkToClipboard(torrent.magnetLink)
        }
        Divider()
        Button("Ask For More Peers", systemImage: "arrow.left.arrow.right") {
            reannounce()
        }
        Button("Verify Local Data", systemImage: "checkmark.arrow.trianglehead.counterclockwise") {
            verifyTorrentAction()
        }
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive, action: onShowDelete)
    }

    private var playbackSection: some View {
        Group {
            Button(
                torrent.status == TorrentStatus.stopped.rawValue ? "Resume" : "Pause",
                systemImage: torrent.status == TorrentStatus.stopped.rawValue ? "play" : "pause"
            ) {
                togglePlayback()
            }

            if torrent.status == TorrentStatus.stopped.rawValue {
                Button("Resume Now", systemImage: "play.fill") {
                    resumeNow()
                }
            }
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

    private func togglePlayback() {
        runAction {
            try await store.toggleTorrentPlayback(torrent)
        }
    }

    private func updatePriority(_ priority: TorrentPriority) {
        runAction {
            try await store.updateTorrentPriority(ids: [torrent.id], priority: priority)
        }
    }

    private func queueMoveTopAction() {
        runAction {
            try await store.moveTorrentsInQueue(.top, ids: [torrent.id])
        }
    }

    private func queueMoveUpAction() {
        runAction {
            try await store.moveTorrentsInQueue(.upward, ids: [torrent.id])
        }
    }

    private func queueMoveDownAction() {
        runAction {
            try await store.moveTorrentsInQueue(.downward, ids: [torrent.id])
        }
    }

    private func queueMoveBottomAction() {
        runAction {
            try await store.moveTorrentsInQueue(.bottom, ids: [torrent.id])
        }
    }

    private func verifyTorrentAction() {
        runAction {
            try await store.verifyTorrents(ids: [torrent.id])
        }
    }

    private func resumeNow() {
        runAction {
            try await store.startTorrentsNow(ids: [torrent.id])
        }
    }

    private func reannounce() {
        runAction {
            try await store.reannounceTorrents(ids: [torrent.id])
        }
    }

    private func runAction(_ operation: @escaping @MainActor () async throws -> Void) {
        performTransmissionAction(operation: operation, onError: onError)
    }
}

@MainActor
private struct IOSTorrentRenameSheet: View {
    let torrent: Torrent
    let store: TransmissionStore
    @Binding var renameInput: String
    @Binding var isPresented: Bool
    let onError: @MainActor @Sendable (String) -> Void

    private var trimmedRenameInput: String {
        renameInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isRenameValid: Bool {
        validateNewName(renameInput, current: torrent.name) == nil && trimmedRenameInput != torrent.name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rename Torrent")
                .font(.headline)
                .padding(.top)
            TextField("Name", text: $renameInput)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.done)
                .onSubmit {
                    saveRename()
                }
            Spacer()
        }
        .padding()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { isPresented = false }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveRename()
                }
                .disabled(!isRenameValid)
            }
        }
    }

    private func saveRename() {
        guard isRenameValid else { return }
        let nameToSave = trimmedRenameInput
        performTransmissionAction(
            operation: { try await store.renameTorrentRoot(torrent, to: nameToSave) },
            onSuccess: { (_: TorrentRenameResponseArgs) in
                isPresented = false
            },
            onError: onError
        )
    }
}

@MainActor
private struct IOSTorrentMoveSheet: View {
    let torrent: Torrent
    let store: TransmissionStore
    @Binding var movePath: String
    @Binding var moveShouldMove: Bool
    @Binding var isPresented: Bool
    let onError: @MainActor @Sendable (String) -> Void

    private var isMoveDisabled: Bool {
        movePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Set Files Location")
                .font(.headline)
                .padding(.top)
            if let path = torrent.downloadDir {
                Text("Current: \(path)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.disabled)
            }
            TextField("Destination path", text: $movePath)
                .textFieldStyle(.roundedBorder)
            Toggle(isOn: $moveShouldMove) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Move files on disk")
                    Text("When enabled, physically moves/renames the torrent's data into this folder on the server. When disabled, does not move files, and instead simply links this torrent to files already in the selected folder.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
        }
        .padding()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { isPresented = false }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Set Location") {
                    setLocation()
                }
                .disabled(isMoveDisabled)
            }
        }
    }

    private func setLocation() {
        let location = movePath.trimmingCharacters(in: .whitespacesAndNewlines)

        performTransmissionAction(
            operation: {
                try await store.setTorrentLocation(
                    ids: [torrent.id],
                    location: location,
                    move: moveShouldMove
                )
            },
            onSuccess: {
                isPresented = false
            },
            onError: onError
        )
    }
}

struct iOSLabelEditView: View {
    @Binding var labelInput: String
    let existingLabels: [String]
    @State private var workingLabels: Set<String>
    @State private var newTagInput: String = ""
    @FocusState private var isInputFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var showingError = false
    @State private var errorMessage = ""
    var store: TransmissionStore
    var torrentId: Int

    init(labelInput: Binding<String>, existingLabels: [String], store: TransmissionStore, torrentId: Int) {
        self._labelInput = labelInput
        self.existingLabels = existingLabels
        self._workingLabels = State(initialValue: Set(existingLabels))
        self.store = store
        self.torrentId = torrentId
    }

    private var sortedLabels: [String] {
        Array(workingLabels).sorted { lhs, rhs in
            lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
    }

    private func saveAndDismiss() {
        if addNewTag(from: &newTagInput, to: &workingLabels) {
            labelInput = workingLabels.joined(separator: ", ")
        }

        labelInput = workingLabels.joined(separator: ", ")
        let sortedLabels = Array(workingLabels).sorted()

        performTransmissionAction(
            operation: {
                try await store.updateTorrentLabels([
                    TransmissionTorrentLabelsUpdate(ids: [torrentId], labels: sortedLabels)
                ])
            },
            onSuccess: {
                dismiss()
            },
            onError: { message in
                errorMessage = message
                showingError = true
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Labels")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)

                    FlowLayout(spacing: 4) {
                        ForEach(sortedLabels, id: \.self) { label in
                            LabelTag(label: label) {
                                workingLabels.remove(label)
                                labelInput = workingLabels.joined(separator: ", ")
                            }
                        }
                    }
                    .padding(.horizontal)

                    HStack {
                        TextField("Add label", text: $newTagInput)
                            .textFieldStyle(.roundedBorder)
                            .focused($isInputFocused)
                            .submitLabel(.done)
                            .onSubmit {
                                if addNewTag(from: &newTagInput, to: &workingLabels) {
                                    labelInput = workingLabels.joined(separator: ", ")
                                }
                            }

                        if !newTagInput.isEmpty {
                            Button(action: {
                                if addNewTag(from: &newTagInput, to: &workingLabels) {
                                    labelInput = workingLabels.joined(separator: ", ")
                                }
                            }, label: {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(.accentColor)
                            })
                        }
                    }
                    .padding(.horizontal)

                    Text("Add labels to organize your torrents.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                }
                .padding(.vertical)
            }
        }
        .navigationTitle("Edit Labels")
        .navigationBarTitleDisplayMode(.inline)
        .transmissionErrorAlert(isPresented: $showingError, message: errorMessage)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveAndDismiss()
                }
            }
        }
        .onChange(of: newTagInput) { _, newValue in
            if newValue.contains(",") {
                newTagInput = newValue.replacingOccurrences(of: ",", with: "")
                if addNewTag(from: &newTagInput, to: &workingLabels) {
                    labelInput = workingLabels.joined(separator: ", ")
                }
            }
        }
    }
}

#else
struct iOSTorrentListRow: View {
    var torrent: Torrent
    var store: TransmissionStore
    var showContentTypeIcons: Bool

    var body: some View {
        EmptyView()
    }
}
#endif
