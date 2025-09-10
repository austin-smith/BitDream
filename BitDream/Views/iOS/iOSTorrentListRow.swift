import Foundation
import SwiftUI
import KeychainAccess

#if os(iOS)
struct iOSTorrentListRow: View {
    @Binding var torrent: Torrent
    var store: Store
    @Binding var selectedTorrents: Set<Torrent>
    var showContentTypeIcons: Bool
    
    @State var deleteDialog: Bool = false
    @State var labelDialog: Bool = false
    @State var labelInput: String = ""
    @State private var renameDialog: Bool = false
    @State private var renameInput: String = ""
    @State private var showingError = false
    @State private var errorMessage = ""
    @Environment(\.colorScheme) var colorScheme
    
    // MARK: - Rename validation helpers
    private var trimmedRenameInput: String {
        renameInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private var isRenameValid: Bool {
        validateNewName(renameInput, current: torrent.name) == nil && trimmedRenameInput != torrent.name
    }
    
    // Create reusable torrent actions view
    @ViewBuilder
    private func torrentActionsMenu() -> some View {
        // Play/Pause Button
        Button(action: {
            let info = makeConfig(store: store)
            playPauseTorrent(torrent: torrent, config: info.config, auth: info.auth, onResponse: { response in
                handleTransmissionResponse(response,
                    onSuccess: {
                        // Success - torrent state will update automatically
                    },
                    onError: { error in
                        errorMessage = error
                        showingError = true
                    }
                )
            })
        }) {
            Label(torrent.status == TorrentStatus.stopped.rawValue ? "Resume" : "Pause", 
                  systemImage: torrent.status == TorrentStatus.stopped.rawValue ? "play" : "pause")
        }
        
        // Resume Now Button (only show for stopped torrents)
        if torrent.status == TorrentStatus.stopped.rawValue {
            Button(action: {
                resumeTorrentNow(torrent: torrent, store: store)
            }) {
                Label("Resume Now", systemImage: "play.fill")
            }
        }

        Divider()
        
        // MARK: - Priority & Queue Section
        
        // Priority Menu
        Menu {
            Button(action: {
                let info = makeConfig(store: store)
                updateTorrent(
                    args: TorrentSetRequestArgs(
                        ids: [torrent.id],
                        priority: .high
                    ),
                    info: info,
                    onComplete: { r in }
                )
            }) {
                Label("High", systemImage: "arrow.up")
            }
            Button(action: {
                let info = makeConfig(store: store)
                updateTorrent(
                    args: TorrentSetRequestArgs(
                        ids: [torrent.id],
                        priority: .normal
                    ),
                    info: info,
                    onComplete: { r in }
                )
            }) {
                Label("Normal", systemImage: "minus")
            }
            Button(action: {
                let info = makeConfig(store: store)
                updateTorrent(
                    args: TorrentSetRequestArgs(
                        ids: [torrent.id],
                        priority: .low
                    ),
                    info: info,
                    onComplete: { r in }
                )
            }) {
                Label("Low", systemImage: "arrow.down")
            }
        } label: {
            Label("Update Priority", systemImage: "flag.badge.ellipsis")
        }

        // Queue Position Menu
        Menu {
            Button(action: {
                let info = makeConfig(store: store)
                queueMoveTop(ids: [torrent.id], info: info) { response in
                    handleTransmissionResponse(response,
                        onSuccess: {},
                        onError: { error in
                            errorMessage = error
                            showingError = true
                        }
                    )
                }
            }) {
                Label("Move to Front", systemImage: "arrow.up.to.line")
            }
            Button(action: {
                let info = makeConfig(store: store)
                queueMoveUp(ids: [torrent.id], info: info) { response in
                    handleTransmissionResponse(response,
                        onSuccess: {},
                        onError: { error in
                            errorMessage = error
                            showingError = true
                        }
                    )
                }
            }) {
                Label("Move Up", systemImage: "arrow.up")
            }
            Button(action: {
                let info = makeConfig(store: store)
                queueMoveDown(ids: [torrent.id], info: info) { response in
                    handleTransmissionResponse(response,
                        onSuccess: {},
                        onError: { error in
                            errorMessage = error
                            showingError = true
                        }
                    )
                }
            }) {
                Label("Move Down", systemImage: "arrow.down")
            }
            Button(action: {
                let info = makeConfig(store: store)
                queueMoveBottom(ids: [torrent.id], info: info) { response in
                    handleTransmissionResponse(response,
                        onSuccess: {},
                        onError: { error in
                            errorMessage = error
                            showingError = true
                        }
                    )
                }
            }) {
                Label("Move to Back", systemImage: "arrow.down.to.line")
            }
        } label: {
            Label("Move in Queue", systemImage: "line.3.horizontal")
        }

        Divider()

        // Rename
        Button(action: {
            renameInput = torrent.name
            renameDialog = true
        }) {
            Label("Rename…", systemImage: "pencil")
        }

        Button(action: {
            labelDialog.toggle()
        }) {
            Label("Edit Labels…", systemImage: "tag")
        }
        
        Divider()
        
        // Copy Magnet Link Button
        Button(action: {
            copyMagnetLinkToClipboard(torrent.magnetLink)
        }) {
            Label("Copy Magnet Link", systemImage: "document.on.document")
        }
        
        Divider()

        // Re-announce Button
        Button(action: {
            reAnnounceToTrackers(torrent: torrent, store: store)
        }) {
            Label("Ask For More Peers", systemImage: "arrow.left.arrow.right")
        }

        // Verify Button
        Button(action: {
            let info = makeConfig(store: store)
            verifyTorrent(torrent: torrent, config: info.config, auth: info.auth, onResponse: { response in
                handleTransmissionResponse(response,
                    onSuccess: {
                        // Success - verification started
                    },
                    onError: { error in
                        errorMessage = error
                        showingError = true
                    }
                )
            })
        }) {
            Label("Verify Local Data", systemImage: "checkmark.arrow.trianglehead.counterclockwise")
        }
    
        Divider()
        
        // Delete Button
        Button(role: .destructive, action: {
            deleteDialog.toggle()
        }) {
            Label("Delete", systemImage: "trash")
        }
    }
    
    var body: some View {
         HStack(spacing: 12) {
             // Icon column (conditional) - spans full row height
             if showContentTypeIcons {
                 Image(systemName: ContentTypeIconMapper.symbolForTorrent(mimeType: torrent.primaryMimeType))
                     .font(.system(size: 16))
                     .foregroundColor(.secondary.opacity(0.6))
                     .frame(width: 20, height: 20)
             }
             
             // Content column - all the text content
             VStack(spacing: 4) {
                 HStack(spacing: 8) {
                     Text(torrent.name)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(1)
                    
                     // Use shared label tags view
                     createLabelTagsView(for: torrent)
                 }
                
                createStatusView(for: torrent)
                    .font(.custom("sub", size: 10))
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .foregroundColor(.secondary)
                
                // Logic here is kind of funky, but we are going to fill up the entire progress bar if the
                // torrent is still retrieving metadata (as the bar will be colored red)
                ProgressView(value: torrent.metadataPercentComplete < 1 ? 1 : torrent.percentDone)
                    .tint(progressColorForTorrent(torrent))
                
                Text(formatTorrentSubtext(torrent))
                    .font(.custom("sub", size: 10))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .foregroundColor(.secondary)
            }
        }
        .contentShape(Rectangle())
        .padding([.top, .bottom, .leading, .trailing], 10)
        .swipeActions(edge: .trailing) {
            // Play/Pause action (rightmost when swiping)
            Button {
                let info = makeConfig(store: store)
                playPauseTorrent(torrent: torrent, config: info.config, auth: info.auth, onResponse: { response in
                    handleTransmissionResponse(response,
                        onSuccess: {
                            // Success - torrent state will update automatically
                        },
                        onError: { error in
                            errorMessage = error
                            showingError = true
                        }
                    )
                })
            } label: {
                Image(systemName: torrent.status == TorrentStatus.stopped.rawValue ? "play.fill" : "pause.fill")
            }
            .tint(torrent.status == TorrentStatus.stopped.rawValue ? .blue : .orange)
            
            // Three-dot menu with all actions (leftmost when swiping)
            Menu {
                torrentActionsMenu()
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
        .contextMenu {
            torrentActionsMenu()
        }
        .id(torrent.id)
        .confirmationDialog(
            "Delete Torrent",
            isPresented: $deleteDialog,
            titleVisibility: .visible
        ) {
            Button("Delete file(s)", role: .destructive) {
                let info = makeConfig(store: store)
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
            Button("Remove from list only") {
                let info = makeConfig(store: store)
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
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Do you want to delete the file(s) from the disk?")
        }
        .transmissionErrorAlert(isPresented: $showingError, message: errorMessage)
        .sheet(isPresented: $renameDialog) {
            NavigationView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Rename Torrent")
                        .font(.headline)
                        .padding(.top)
                    TextField("Name", text: $renameInput)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.done)
                        .onSubmit {
                            if isRenameValid {
                                let nameToSave = trimmedRenameInput
                                renameTorrentRoot(torrent: torrent, to: nameToSave, store: store) { err in
                                    if let err = err {
                                        errorMessage = err
                                        showingError = true
                                    } else {
                                        renameDialog = false
                                    }
                                }
                            }
                        }
                    Spacer()
                }
                .padding()
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { renameDialog = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        let disabled = !isRenameValid
                        Button("Save") {
                            let nameToSave = trimmedRenameInput
                            renameTorrentRoot(torrent: torrent, to: nameToSave, store: store) { err in
                                if let err = err {
                                    errorMessage = err
                                    showingError = true
                                } else {
                                    renameDialog = false
                                }
                            }
                        }
                        .disabled(disabled)
                    }
                }
            }
            // focus handled on TextField onAppear
        }
        .sheet(isPresented: $labelDialog) {
            NavigationView {
                iOSLabelEditView(labelInput: $labelInput, existingLabels: torrent.labels, store: store, torrentId: torrent.id)
            }
        }
    }
}

struct iOSLabelEditView: View {
    @Binding var labelInput: String
    let existingLabels: [String]
    @State private var workingLabels: Set<String>
    @State private var newTagInput: String = ""
    @FocusState private var isInputFocused: Bool
    @Environment(\.dismiss) private var dismiss
    var store: Store
    var torrentId: Int
    
    init(labelInput: Binding<String>, existingLabels: [String], store: Store, torrentId: Int) {
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
        // First add any pending tag
        if addNewTag(from: &newTagInput, to: &workingLabels) {
            labelInput = workingLabels.joined(separator: ", ")
        }
        
        // Update the binding
        labelInput = workingLabels.joined(separator: ", ")
        
        // Save to server and refresh
        saveTorrentLabels(torrentId: torrentId, labels: workingLabels, store: store) {
            dismiss()
        }
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
                            }) {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(.accentColor)
                            }
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
    
}

#else
// Empty struct for macOS to reference - this won't be compiled on macOS but provides the type
struct iOSTorrentListRow: View {
    @Binding var torrent: Torrent
    var store: Store
    @Binding var selectedTorrents: Set<Torrent>
    var showContentTypeIcons: Bool
    
    var body: some View {
        EmptyView()
    }
}
#endif 