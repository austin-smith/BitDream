import Foundation
import SwiftUI
import KeychainAccess

#if os(macOS)
struct macOSTorrentListRow: View {
    @Binding var torrent: Torrent
    var store: Store
    @Binding var selectedTorrents: Set<Torrent>
    
    @State var deleteDialog: Bool = false
    @State var labelDialog: Bool = false
    @State var labelInput: String = ""
    @State private var shouldSave: Bool = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack {
            HStack(spacing: 8) {
                Text(torrent.name)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(alignment: .leading)
                
                // Display labels inline if present, but allow them to be truncated
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
                for t in affectedTorrents {
                    playPauseTorrent(torrent: t, config: info.config, auth: info.auth, onResponse: { response in
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
                }
            }) {
                HStack {
                    Image(systemName: torrent.status == TorrentStatus.stopped.rawValue ? "play" : "pause")
                        .foregroundStyle(.secondary)
                    Text(torrent.status == TorrentStatus.stopped.rawValue ? "Resume" : "Pause")
                }
            }
            
            // Resume Now Button (only show for stopped torrents)
            if torrent.status == TorrentStatus.stopped.rawValue {
                Button(action: {
                    for t in affectedTorrents {
                        resumeTorrentNow(torrent: t, store: store)
                    }
                }) {
                    HStack {
                        Image(systemName: "play.fill")
                            .foregroundStyle(.secondary)
                        Text("Resume Now")
                    }
                }
            }

            Divider()
            
            // Priority Menu
            Menu {
                Button(action: {
                    let info = makeConfig(store: store)
                    updateTorrent(
                        args: TorrentSetRequestArgs(
                            ids: Array(affectedTorrents.map { $0.id }),
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
                            ids: Array(affectedTorrents.map { $0.id }),
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
                            ids: Array(affectedTorrents.map { $0.id }),
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

            Button(action: {
                // For single-torrent editing, pre-fill with existing labels.
                // For multi-torrent editing, start with empty input so new labels can be appended
                // without removing or overwriting existing labels.
                if affectedTorrents.count == 1 {
                    labelInput = torrent.labels.joined(separator: ", ")
                } else {
                    labelInput = ""
                }
                labelDialog.toggle()
            }) {
                HStack {
                    Image(systemName: "tag")
                        .foregroundStyle(.secondary)
                    Text("Edit Labels")
                }
            }

            Divider()
            
            // Copy Magnet Link Button - only show if no selection or single selection of this torrent
            if selectedTorrents.isEmpty || selectedTorrents.count == 1 {
                Button(action: {
                    copyMagnetLinkToClipboard(torrent.magnetLink)
                }) {
                    HStack {
                        Image(systemName: "document.on.document")
                            .foregroundStyle(.secondary)
                        Text("Copy Magnet Link")
                    }
                }
                
                Divider()

                // Re-announce Button
                Button(action: {
                    for t in affectedTorrents {
                        reAnnounceToTrackers(torrent: t, store: store)
                    }
                }) {
                    HStack {
                        Image(systemName: "arrow.left.arrow.right")
                            .foregroundStyle(.secondary)
                        Text("Ask For More Peers")
                    }
                }

                // Verify Button
                Button(action: {
                    let info = makeConfig(store: store)
                    for t in affectedTorrents {
                        verifyTorrent(torrent: t, config: info.config, auth: info.auth, onResponse: { response in
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
                    }
                }) {
                    HStack {
                        Image(systemName: "checkmark.arrow.trianglehead.counterclockwise")
                            .foregroundStyle(.secondary)
                        Text("Verify Local Data")
                    }
                }
            }

            Divider()
            
            // Delete Button
            Button(role: .destructive, action: {
                deleteDialog.toggle()
            }) {
                HStack {
                    Image(systemName: "trash")
                        .foregroundStyle(.secondary)
                    Text("Delete")
                }
            }
        }
        .tint(.primary)
        .id(torrent.id)
        .sheet(isPresented: $labelDialog) {
            VStack(spacing: 16) {
                Text("Edit Labels\(affectedTorrents.count > 1 ? " (\(affectedTorrents.count) torrents)" : "")")
                    .font(.headline)
                
                LabelEditView(
                    labelInput: $labelInput,
                    // Show existing labels for single torrent, empty for multi-torrent (append mode)
                    existingLabels: affectedTorrents.count == 1 ? Array(affectedTorrents.first!.labels) : [],
                    store: store,
                    torrentIds: Array(affectedTorrents.map { $0.id }),
                    selectedTorrents: affectedTorrents,
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
            "Delete \(affectedTorrents.count > 1 ? "\(affectedTorrents.count) Torrents" : "Torrent")",
            isPresented: $deleteDialog) {
                Button(role: .destructive) {
                    let info = makeConfig(store: store)
                    for t in affectedTorrents {
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
                    for t in affectedTorrents {
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
            .interactiveDismissDisabled(false)
        .transmissionErrorAlert(isPresented: $showingError, message: errorMessage)
    }
    
    private var affectedTorrents: Set<Torrent> {
        selectedTorrents.contains(torrent) ? selectedTorrents : Set([torrent])
    }
}

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
    
    /// Saves labels by merging newly entered labels with each selected torrent's
    /// existing labels. This appends labels and does not remove or overwrite
    /// existing labels.
    private func saveAndDismiss() {
        // First add any pending tag
        if addNewTag(from: &newTagInput, to: &workingLabels) {
            labelInput = workingLabels.joined(separator: ", ")
        }
        
        // Update the binding
        labelInput = workingLabels.joined(separator: ", ")
        
        // Merge new labels with each torrent's existing labels
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

#else
// Empty struct for iOS to reference - this won't be compiled on iOS but provides the type
struct macOSTorrentListRow: View {
    @Binding var torrent: Torrent
    var store: Store
    @Binding var selectedTorrents: Set<Torrent>
    
    var body: some View {
        EmptyView()
    }
}
#endif 