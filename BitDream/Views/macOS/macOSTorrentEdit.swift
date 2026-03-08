import Foundation
import SwiftUI

#if os(macOS)

@MainActor
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
                    if !isSaveDisabled {
                        onSave(name)
                    }
                }
            if let validationMessage {
                Text(validationMessage)
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
            DispatchQueue.main.async {
                isNameFocused = true
            }
        }
    }
}

@MainActor
struct LabelEditView: View {
    @Binding var labelInput: String
    let existingLabels: [String]
    @State private var workingLabels: Set<String>
    @State private var newTagInput: String = ""
    @FocusState private var isInputFocused: Bool
    @Environment(\.dismiss) private var dismiss
    var store: TransmissionStore
    let selectedTorrents: Set<Torrent>
    @Binding var shouldSave: Bool

    init(
        labelInput: Binding<String>,
        existingLabels: [String],
        store: TransmissionStore,
        selectedTorrents: Set<Torrent>,
        shouldSave: Binding<Bool>
    ) {
        self._labelInput = labelInput
        self.existingLabels = existingLabels
        self._workingLabels = State(initialValue: Set(existingLabels))
        self.store = store
        self.selectedTorrents = selectedTorrents
        self._shouldSave = shouldSave
    }

    private func saveAndDismiss() {
        if addNewTag(from: &newTagInput, to: &workingLabels) {
            labelInput = workingLabels.joined(separator: ", ")
        }

        labelInput = workingLabels.joined(separator: ", ")

        if selectedTorrents.count == 1 {
            let torrent = selectedTorrents.first!
            saveTorrentLabels(torrentId: torrent.id, labels: workingLabels, store: store) {
                dismiss()
            }
        } else {
            let info = makeConfig(store: store)
            for torrent in selectedTorrents {
                let mergedLabels = Set(torrent.labels).union(workingLabels)
                let sortedLabels = Array(mergedLabels).sorted()
                updateTorrent(
                    args: TorrentSetRequestArgs(ids: [torrent.id], labels: sortedLabels),
                    info: info,
                    onComplete: { _ in }
                )
            }
            store.requestRefresh()
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
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(width: 360, alignment: .leading)
            }
        }
        .onChange(of: shouldSave) { _, newValue in
            if newValue {
                saveAndDismiss()
                shouldSave = false
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

@MainActor
struct MoveSheetContent: View {
    let store: TransmissionStore
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
                    let ids = Array(selectedTorrents.map(\.id))
                    let args = TorrentSetLocationRequestArgs(
                        ids: ids,
                        location: movePath.trimmingCharacters(in: .whitespacesAndNewlines),
                        move: moveShouldMove
                    )
                    setTorrentLocation(args: args, info: info) { response in
                        handleTransmissionResponse(response, onSuccess: {
                            store.requestRefresh()
                            isPresented = false
                        }, onError: { error in
                            errorMessage = error
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

#endif
