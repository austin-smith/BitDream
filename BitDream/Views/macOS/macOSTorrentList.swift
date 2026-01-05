import Foundation
import SwiftUI
import KeychainAccess

#if os(macOS)

// MARK: - macOS-only Linear Progress Style (native look, custom color)
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

// MARK: - Shared Components for macOS Torrent List Views

// MARK: - Torrent Row Modifier
// Shared modifier for handling torrent row interactions
struct TorrentRowModifier: ViewModifier {
    var torrent: Torrent
    var selectedTorrents: Set<Torrent>
    let store: Store
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

    func body(content: Content) -> some View {
        content
        .contextMenu {
                createTorrentContextMenu(
                    torrents: affectedTorrents,
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
        .tint(.primary)
        .id(torrent.id)
        .sheet(isPresented: $labelDialog) {
            LabelEditSheetContent(
                store: store,
                selectedTorrents: affectedTorrents,
                labelInput: $labelInput,
                shouldSave: $shouldSave,
                isPresented: $labelDialog
            )
            .frame(width: 400)
        }
        .torrentDeleteAlert(
            isPresented: $deleteDialog,
            selectedTorrents: { affectedTorrents },
            store: store,
            showingError: $showingError,
            errorMessage: $errorMessage
        )
            .interactiveDismissDisabled(false)
        .transmissionErrorAlert(isPresented: $showingError, message: errorMessage)
        .sheet(isPresented: $renameDialog) {
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
        .sheet(isPresented: $moveDialog) {
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
}

// MARK: - Context Menu Builder
@ViewBuilder
func createTorrentContextMenu(
    torrents: Set<Torrent>,
    store: Store,
    labelInput: Binding<String>,
    labelDialog: Binding<Bool>,
    deleteDialog: Binding<Bool>,
    renameInput: Binding<String>,
    renameDialog: Binding<Bool>,
    renameTargetId: Binding<Int?>,
    movePath: Binding<String>,
    moveDialog: Binding<Bool>,
    moveShouldMove: Binding<Bool>,
    showingError: Binding<Bool>,
    errorMessage: Binding<String>
) -> some View {
    let firstTorrent = torrents.first!

    // Pause Button (always shown; disabled for single stopped)
    Button(action: {
        let info = makeConfig(store: store)
        pauseTorrents(ids: Array(torrents.map { $0.id }), info: info) { response in
            handleTransmissionResponse(response,
                onSuccess: {},
                onError: { error in
                    errorMessage.wrappedValue = error
                    showingError.wrappedValue = true
                }
            )
        }
    }) {
        HStack {
            Image(systemName: "pause")
                .foregroundStyle(.secondary)
            Text("Pause")
        }
    }
    .disabled(torrents.shouldDisablePause)

    // Resume Button (always shown; disabled for single non-stopped)
    Button(action: {
        let info = makeConfig(store: store)
        resumeTorrents(ids: Array(torrents.map { $0.id }), info: info) { response in
            handleTransmissionResponse(response,
                onSuccess: {},
                onError: { error in
                    errorMessage.wrappedValue = error
                    showingError.wrappedValue = true
                }
            )
        }
    }) {
        HStack {
            Image(systemName: "play")
                .foregroundStyle(.secondary)
            Text("Resume")
        }
    }
    .disabled(torrents.shouldDisableResume)

    // Resume Now Button (always shown; disabled for single non-stopped)
    Button(action: {
        for t in torrents {
            resumeTorrentNow(torrent: t, store: store)
        }
    }) {
        HStack {
            Image(systemName: "play.fill")
                .foregroundStyle(.secondary)
            Text("Resume Now")
        }
    }
    .disabled(torrents.shouldDisableResume)

    Divider()

    // MARK: - Priority & Queue Section

    // Priority Menu
    Menu {
        Button(action: {
            let info = makeConfig(store: store)
            updateTorrent(
                args: TorrentSetRequestArgs(
                    ids: Array(torrents.map { $0.id }),
                    priority: .high
                ),
                info: info,
                onComplete: { r in }
            )
        }) {
            HStack {
                Image(systemName: "arrow.up")
                    .foregroundStyle(.secondary)
                Text("High")
            }
        }
        Button(action: {
            let info = makeConfig(store: store)
            updateTorrent(
                args: TorrentSetRequestArgs(
                    ids: Array(torrents.map { $0.id }),
                    priority: .normal
                ),
                info: info,
                onComplete: { r in }
            )
        }) {
            HStack {
                Image(systemName: "minus")
                    .foregroundStyle(.secondary)
                Text("Normal")
            }
        }
        Button(action: {
            let info = makeConfig(store: store)
            updateTorrent(
                args: TorrentSetRequestArgs(
                    ids: Array(torrents.map { $0.id }),
                    priority: .low
                ),
                info: info,
                onComplete: { r in }
            )
        }) {
            HStack {
                Image(systemName: "arrow.down")
                    .foregroundStyle(.secondary)
                Text("Low")
            }
        }
    } label: {
        HStack {
            Image(systemName: "flag.badge.ellipsis")
                .foregroundStyle(.secondary)
            Text("Update Priority")
        }
    }

    // Queue Position Menu
    Menu {
        Button(action: {
            let info = makeConfig(store: store)
            queueMoveTop(ids: Array(torrents.map { $0.id }), info: info) { response in
                handleTransmissionResponse(response,
                    onSuccess: {},
                    onError: { error in
                        errorMessage.wrappedValue = error
                        showingError.wrappedValue = true
                    }
                )
            }
        }) {
            HStack {
                Image(systemName: "arrow.up.to.line")
                    .foregroundStyle(.secondary)
                Text("Move to Front")
            }
        }
        Button(action: {
            let info = makeConfig(store: store)
            queueMoveUp(ids: Array(torrents.map { $0.id }), info: info) { response in
                handleTransmissionResponse(response,
                    onSuccess: {},
                    onError: { error in
                        errorMessage.wrappedValue = error
                        showingError.wrappedValue = true
                    }
                )
            }
        }) {
            HStack {
                Image(systemName: "arrow.up")
                    .foregroundStyle(.secondary)
                Text("Move Up")
            }
        }
        Button(action: {
            let info = makeConfig(store: store)
            queueMoveDown(ids: Array(torrents.map { $0.id }), info: info) { response in
                handleTransmissionResponse(response,
                    onSuccess: {},
                    onError: { error in
                        errorMessage.wrappedValue = error
                        showingError.wrappedValue = true
                    }
                )
            }
        }) {
            HStack {
                Image(systemName: "arrow.down")
                    .foregroundStyle(.secondary)
                Text("Move Down")
            }
        }
        Button(action: {
            let info = makeConfig(store: store)
            queueMoveBottom(ids: Array(torrents.map { $0.id }), info: info) { response in
                handleTransmissionResponse(response,
                    onSuccess: {},
                    onError: { error in
                        errorMessage.wrappedValue = error
                        showingError.wrappedValue = true
                    }
                )
            }
        }) {
            HStack {
                Image(systemName: "arrow.down.to.line")
                    .foregroundStyle(.secondary)
                Text("Move to Back")
            }
        }
    } label: {
        HStack {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)
            Text("Move in Queue")
        }
    }

    Divider()

    // Set Location… (supports multi-select)
    Button(action: {
        // Prefill with server default download dir if available
        movePath.wrappedValue = store.defaultDownloadDir
        moveDialog.wrappedValue = true
    }) {
        HStack {
            Image(systemName: "folder.badge.gearshape")
                .foregroundStyle(.secondary)
            Text("Set Location…")
        }
    }

    // Rename Button (moved into edit section)
    Button(action: {
        renameInput.wrappedValue = firstTorrent.name
        renameTargetId.wrappedValue = firstTorrent.id
        renameDialog.wrappedValue = true
    }) {
        HStack {
            Image(systemName: "pencil")
                .foregroundStyle(.secondary)
            Text("Rename…")
        }
    }
    .disabled(torrents.count != 1)

    Button(action: {
        // For single-torrent editing, pre-fill with existing labels.
        // For multi-torrent editing, start with empty input so new labels can be appended
        // without removing or overwriting existing labels.
        if torrents.count == 1 {
            labelInput.wrappedValue = torrents.first!.labels.joined(separator: ", ")
        } else {
            labelInput.wrappedValue = ""
        }
        labelDialog.wrappedValue.toggle()
    }) {
        HStack {
            Image(systemName: "tag")
                .foregroundStyle(.secondary)
            Text("Edit Labels…")
        }
    }

    Divider()

    // Copy Magnet Link Button (disabled for multi-select)
    Button(action: {
        copyMagnetLinkToClipboard(firstTorrent.magnetLink)
    }) {
        HStack {
            Image(systemName: "document.on.document")
                .foregroundStyle(.secondary)
            Text("Copy Magnet Link")
        }
    }
    .disabled(torrents.count != 1)

    Divider()

    // Re-announce Button (supports multi-select)
    Button(action: {
        for t in torrents {
            reAnnounceToTrackers(torrent: t, store: store)
        }
    }) {
        HStack {
            Image(systemName: "arrow.left.arrow.right")
                .foregroundStyle(.secondary)
            Text("Ask For More Peers")
        }
    }

    // Verify Button (supports multi-select)
    Button(action: {
        let info = makeConfig(store: store)
        for t in torrents {
            verifyTorrent(torrent: t, config: info.config, auth: info.auth, onResponse: { response in
                handleTransmissionResponse(response,
                    onSuccess: {
                        // Success - verification started
                    },
                    onError: { error in
                        errorMessage.wrappedValue = error
                        showingError.wrappedValue = true
                    }
                )
            })
        }
    }) {
        HStack {
            Image(systemName: "checkmark.arrow.trianglehead.counterclockwise")
                .foregroundStyle(.secondary)
            Text("Verify Local Data")
        }
    }

    Divider()

    // Delete Button
    Button(role: .destructive, action: {
        deleteDialog.wrappedValue.toggle()
    }) {
        HStack {
            Image(systemName: "trash")
                .foregroundStyle(.secondary)
            Text("Delete…")
        }
    }
}

// MARK: - Rename Sheet View
struct RenameSheetView: View {
    let title: String
    @Binding var name: String
    let currentName: String
    var onCancel: () -> Void
    var onSave: (String) -> Void
    @FocusState private var isNameFocused: Bool

    private var validationMessage: String? {
        validateNewName(name, current: currentName)
    }
    private var isSaveDisabled: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return validationMessage != nil || trimmed == currentName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($isNameFocused)
                .onSubmit {
                    if !isSaveDisabled { onSave(name) }
                }
            if let msg = validationMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundColor(.red)
            }
            HStack {
                Spacer()
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { onSave(name) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaveDisabled)
            }
        }
        .onAppear {
            // Defer focus to ensure sheet presentation completes
            DispatchQueue.main.async { isNameFocused = true }
        }
    }
}

// MARK: - Label Edit View
struct LabelEditView: View {
    @Binding var labelInput: String
    let existingLabels: [String]
    @State private var workingLabels: Set<String>
    @State private var newTagInput: String = ""
    @FocusState private var isInputFocused: Bool
    @Environment(\.dismiss) private var dismiss
    var store: Store
    var torrentIds: [Int]
    let selectedTorrents: Set<Torrent>
    @Binding var shouldSave: Bool

    init(labelInput: Binding<String>, existingLabels: [String], store: Store, torrentIds: [Int], selectedTorrents: Set<Torrent>, shouldSave: Binding<Bool>) {
        self._labelInput = labelInput
        self.existingLabels = existingLabels
        self._workingLabels = State(initialValue: Set(existingLabels))
        self.store = store
        self.torrentIds = torrentIds
        self.selectedTorrents = selectedTorrents
        self._shouldSave = shouldSave
    }

    /// Saves labels with different behavior for single vs multiple torrents:
    /// - Single torrent: Replace labels (allows removal)
    /// - Multiple torrents: Append labels (bulk add operation)
    private func saveAndDismiss() {
        // First add any pending tag
        if addNewTag(from: &newTagInput, to: &workingLabels) {
            labelInput = workingLabels.joined(separator: ", ")
        }

        // Update the binding
        labelInput = workingLabels.joined(separator: ", ")

        if selectedTorrents.count == 1 {
            // Single torrent: REPLACE labels (allows removal like iOS)
            let torrent = selectedTorrents.first!
            saveTorrentLabels(torrentId: torrent.id, labels: workingLabels, store: store) {
                dismiss()
            }
        } else {
            // Multiple torrents: APPEND labels (current behavior for bulk operations)
            for torrent in selectedTorrents {
                let existingLabels = Set(torrent.labels)
                let mergedLabels = existingLabels.union(workingLabels)
                let sortedLabels = Array(mergedLabels).sorted()

                let info = makeConfig(store: store)
                updateTorrent(
                    args: TorrentSetRequestArgs(ids: [torrent.id], labels: sortedLabels),
                    info: info,
                    onComplete: { _ in
                        // Individual torrent updated
                    }
                )
            }

            // Trigger refresh and dismiss
            refreshTransmissionData(store: store)
            dismiss()
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.vertical, showsIndicators: false) {
                FlowLayout(spacing: 4) {
                    ForEach(Array(workingLabels).sorted(), id: \.self) { label in
                        LabelTag(label: label) {
                            workingLabels.remove(label)
                            labelInput = workingLabels.joined(separator: ", ")
                        }
                    }

                    tagInputField
                }
                .padding(.leading, 8)
                .padding(.trailing, 8)
                .padding(.vertical, 6)
                .frame(width: 360, alignment: .leading)
            }
        }
        .onChange(of: shouldSave) { oldValue, newValue in
            if newValue {
                saveAndDismiss()
                shouldSave = false
            }
        }
        .onChange(of: newTagInput) { oldValue, newValue in
            if newValue.contains(",") {
                // Remove the comma and add the tag
                newTagInput = newValue.replacingOccurrences(of: ",", with: "")
                if addNewTag(from: &newTagInput, to: &workingLabels) {
                    labelInput = workingLabels.joined(separator: ", ")
                }
            }
        }
    }

    private var tagInputField: some View {
        TextField("Add label", text: $newTagInput)
            .textFieldStyle(.plain)
            .focused($isInputFocused)
            .frame(width: 80)
            .onSubmit {
                if addNewTag(from: &newTagInput, to: &workingLabels) {
                    labelInput = workingLabels.joined(separator: ", ")
                }
            }
            .onTapGesture {
                isInputFocused = true
            }
            .onKeyPress(keys: [.return]) { press in
                if press.modifiers.contains(.shift) {
                    saveAndDismiss()
                    return .handled
                }
                return .ignored
            }
    }
}

// MARK: - Move Sheet View
struct MoveSheetContent: View {
    let store: Store
    let selectedTorrents: Set<Torrent>
    @Binding var movePath: String
    @Binding var moveShouldMove: Bool
    @Binding var isPresented: Bool
    @Binding var showingError: Bool
    @Binding var errorMessage: String


    private var isMoveEnabled: Bool {
        !movePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Set Files Location\(selectedTorrents.count > 1 ? " (\(selectedTorrents.count) torrents)" : "")")
                .font(.headline)
            if let path = selectedTorrents.first?.downloadDir {
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
            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button("Set Location") {
                    let info = makeConfig(store: store)
                    let ids = Array(selectedTorrents.map { $0.id })
                    let args = TorrentSetLocationRequestArgs(ids: ids, location: movePath.trimmingCharacters(in: .whitespacesAndNewlines), move: moveShouldMove)
                    setTorrentLocation(args: args, info: info) { response in
                        handleTransmissionResponse(response, onSuccess: {
                            refreshTransmissionData(store: store)
                            isPresented = false
                        }, onError: { err in
                            errorMessage = err
                            showingError = true
                        })
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!isMoveEnabled)
            }
        }
        .padding(.vertical)
    }
}

#else
// Empty struct for iOS to reference - this won't be compiled on iOS but provides the type
struct macOSTorrentListRow: View {
    var torrent: Torrent
    var store: Store
    var selectedTorrents: Set<Torrent>
    let isCompact: Bool

    var body: some View {
        EmptyView()
    }
}
#endif
