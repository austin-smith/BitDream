//
//  macOSTorrentListRow.swift
//  BitDream
//
//  Created by Austin Smith on 12/29/22.
//

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
            let torrentsToAct = selectedTorrents.contains(torrent) ? selectedTorrents : Set([torrent])
            
            // Play/Pause Button
            Button(action: {
                let info = makeConfig(store: store)
                for t in torrentsToAct {
                    playPauseTorrent(torrent: t, config: info.config, auth: info.auth, onResponse: { response in
                        // TODO: Handle response
                    })
                }
            }) {
                HStack {
                    Image(systemName: torrent.status == TorrentStatus.stopped.rawValue ? "play" : "pause")
                    Text(torrent.status == TorrentStatus.stopped.rawValue ? "Resume Dream" : "Pause Dream")
                }
            }

            Divider()
            
            // Priority Menu
            Menu {
                Button(action: {
                    let info = makeConfig(store: store)
                    updateTorrent(
                        args: TorrentSetRequestArgs(
                            ids: Array(torrentsToAct.map { $0.id }),
                            priorityHigh: []
                        ),
                        info: info,
                        onComplete: { r in }
                    )
                }) {
                    HStack {
                        Image(systemName: "arrow.up")
                        Text("High")
                    }
                }
                Button(action: {
                    let info = makeConfig(store: store)
                    updateTorrent(
                        args: TorrentSetRequestArgs(
                            ids: Array(torrentsToAct.map { $0.id }),
                            priorityNormal: []
                        ),
                        info: info,
                        onComplete: { r in }
                    )
                }) {
                    HStack {
                        Image(systemName: "minus")
                        Text("Normal")
                    }
                }
                Button(action: {
                    let info = makeConfig(store: store)
                    updateTorrent(
                        args: TorrentSetRequestArgs(
                            ids: Array(torrentsToAct.map { $0.id }),
                            priorityLow: []
                        ),
                        info: info,
                        onComplete: { r in }
                    )
                }) {
                    HStack {
                        Image(systemName: "arrow.down")
                        Text("Low")
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "flag.badge.ellipsis")
                    Text("Update Priority")
                }
            }

            Button(action: {
                labelInput = torrent.labels.joined(separator: ", ")
                labelDialog.toggle()
            }) {
                HStack {
                    Image(systemName: "tag")
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
                        Image(systemName: "document.on.document.fill")
                        Text("Copy Magnet Link")
                    }
                }
                
                Divider()
            }
            
            // Delete Button
            Button(role: .destructive, action: {
                deleteDialog.toggle()
            }) {
                HStack {
                    Image(systemName: "trash")
                    Text("Delete")
                }
            }
        }
        .id(torrent.id)
        .sheet(isPresented: $labelDialog) {
            VStack(spacing: 16) {
                Text("Edit Labels")
                    .font(.headline)
                
                LabelEditView(
                    labelInput: $labelInput,
                    existingLabels: torrent.labels,
                    store: store,
                    torrentId: torrent.id,
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
            "Delete \(torrentsToDelete.count > 1 ? "\(torrentsToDelete.count) Torrents" : "Torrent")",
            isPresented: $deleteDialog) {
                Button(role: .destructive) {
                    let info = makeConfig(store: store)
                    for t in torrentsToDelete {
                        deleteTorrent(torrent: t, erase: true, config: info.config, auth: info.auth, onDel: { response in
                            // TODO: Handle response
                        })
                    }
                    deleteDialog.toggle()
                } label: {
                    Text("Delete file(s)")
                }
                Button("Remove from list only") {
                    let info = makeConfig(store: store)
                    for t in torrentsToDelete {
                        deleteTorrent(torrent: t, erase: false, config: info.config, auth: info.auth, onDel: { response in
                            // TODO: Handle response
                        })
                    }
                    deleteDialog.toggle()
                }
            } message: {
                Text("Do you want to delete the file(s) from the disk?")
            }
            .interactiveDismissDisabled(false)
    }
    
    private var torrentsToDelete: Set<Torrent> {
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
    var torrentId: Int
    @Binding var shouldSave: Bool
    
    init(labelInput: Binding<String>, existingLabels: [String], store: Store, torrentId: Int, shouldSave: Binding<Bool>) {
        self._labelInput = labelInput
        self.existingLabels = existingLabels
        self._workingLabels = State(initialValue: Set(existingLabels))
        self.store = store
        self.torrentId = torrentId
        self._shouldSave = shouldSave
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
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.vertical, showsIndicators: false) {
                FlowLayout(spacing: 4) {
                    ForEach(Array(workingLabels).sorted(), id: \.self) { label in
                        LabelTag(label: label) {
                            workingLabels.remove(label)
                            updateLabelInput()
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
        .onChange(of: shouldSave) { newValue in
            if newValue {
                saveAndDismiss()
                shouldSave = false
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
    
    private var tagInputField: some View {
        TextField("Add label", text: $newTagInput)
            .textFieldStyle(.plain)
            .focused($isInputFocused)
            .frame(width: 80)
            .onSubmit(addNewTag)
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