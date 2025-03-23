import Foundation
import SwiftUI
import KeychainAccess

#if os(iOS)
struct iOSTorrentListRow: View {
    @Binding var torrent: Torrent
    var store: Store
    @Binding var selectedTorrents: Set<Torrent>  // Added for API compatibility
    
    @State var deleteDialog: Bool = false
    @State var labelDialog: Bool = false
    @State var labelInput: String = ""
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack {
            HStack(spacing: 8) {
                Text(torrent.name)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(alignment: .leading)
                
                // Use shared label tags view
                createLabelTagsView(for: torrent)
                    .layoutPriority(-1)  // Give lower priority than the name
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
        .contentShape(Rectangle())
        .padding([.top, .bottom, .leading, .trailing], 10)
        .contextMenu {
            // Play/Pause Button
            Button(action: {
                let info = makeConfig(store: store)
                playPauseTorrent(torrent: torrent, config: info.config, auth: info.auth, onResponse: { response in
                    // TODO: Handle response
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
            
            // Priority Menu
            Menu {
                Button(action: {
                    let info = makeConfig(store: store)
                    updateTorrent(
                        args: TorrentSetRequestArgs(
                            ids: [torrent.id],
                            priorityHigh: []
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
                            priorityNormal: []
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
                            priorityLow: []
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

            Button(action: {
                labelDialog.toggle()
            }) {
                Label("Edit Labels", systemImage: "tag")
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
                    // TODO: Handle response
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
        .id(torrent.id)
        .alert(
            "Delete Torrent",
            isPresented: $deleteDialog) {
                Button(role: .destructive) {
                    let info = makeConfig(store: store)
                    deleteTorrent(torrent: torrent, erase: true, config: info.config, auth: info.auth, onDel: { response in
                        // TODO: Handle response
                    })
                    deleteDialog.toggle()
                } label: {
                    Text("Delete file(s)")
                }
                Button("Remove from list only") {
                    let info = makeConfig(store: store)
                    deleteTorrent(torrent: torrent, erase: false, config: info.config, auth: info.auth, onDel: { response in
                        // TODO: Handle response
                    })
                    deleteDialog.toggle()
                }
            } message: {
                Text("Do you want to delete the file(s) from the disk?")
            }
            .interactiveDismissDisabled(false)
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
    
    private func saveAndDismiss() {
        // First add any pending tag
        addNewTag()
        
        // Update the binding
        updateLabelInput()
        
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
                        ForEach(Array(workingLabels).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }, id: \.self) { label in
                            LabelTag(label: label) {
                                workingLabels.remove(label)
                                updateLabelInput()
                            }
                        }
                    }
                    .padding(.horizontal)
                    
                    HStack {
                        TextField("Add label", text: $newTagInput)
                            .textFieldStyle(.roundedBorder)
                            .focused($isInputFocused)
                            .submitLabel(.done)
                            .onSubmit(addNewTag)
                        
                        if !newTagInput.isEmpty {
                            Button(action: addNewTag) {
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
        .onChange(of: newTagInput) { newValue in
            if newValue.contains(",") {
                // Remove the comma and add the tag
                newTagInput = newValue.replacingOccurrences(of: ",", with: "")
                addNewTag()
            }
        }
    }
    
    private func addNewTag() {
        let trimmed = newTagInput.trimmingCharacters(in: .whitespaces)
        if BitDream.addNewTag(trimmedInput: trimmed, to: &workingLabels) {
            updateLabelInput()
        }
        newTagInput = ""
    }
    
    private func updateLabelInput() {
        // Update the binding with the current working set
        labelInput = workingLabels.joined(separator: ", ")
    }
}

#else
// Empty struct for macOS to reference - this won't be compiled on macOS but provides the type
struct iOSTorrentListRow: View {
    @Binding var torrent: Torrent
    var store: Store
    @Binding var selectedTorrents: Set<Torrent>
    
    var body: some View {
        EmptyView()
    }
}
#endif 