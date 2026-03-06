import Foundation
import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
struct macOSAddTorrent: View {
    // MARK: - Properties
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: AppStore

    @State private var inputMethod: TorrentInputMethod = .magnetLink
    @State private var alertInput = ""
    @State private var downloadDir = ""
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var selectedTorrentFiles: [(name: String, data: Data)] = []
    @State private var activeImporter: ActiveImporter?
    @State private var isShowingImporter = false

    private enum ActiveImporter {
        case torrentFiles
        case downloadFolder

        var allowedContentTypes: [UTType] {
            switch self {
            case .torrentFiles:
                [.torrent]
            case .downloadFolder:
                [.folder]
            }
        }

        var allowsMultipleSelection: Bool {
            self == .torrentFiles
        }
    }

    enum TorrentInputMethod: String, CaseIterable, Identifiable {
        case magnetLink = "Magnet Link"
        case torrentFile = "Torrent File"

        var id: String { rawValue }
    }

    private var isAddDisabled: Bool {
        switch inputMethod {
        case .magnetLink:
            alertInput.isEmpty
        case .torrentFile:
            selectedTorrentFiles.isEmpty
        }
    }

    private var importerContentTypes: [UTType] {
        activeImporter?.allowedContentTypes ?? [.torrent]
    }

    private var importerAllowsMultipleSelection: Bool {
        activeImporter?.allowsMultipleSelection ?? false
    }

    // MARK: - Body
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                addTorrentForm
            }
            Divider()
            footer
        }
        .frame(width: 600, height: 400)
        .alert("Error", isPresented: $showingError, actions: {
            Button("OK", role: .cancel) {}
        }, message: {
            Text(errorMessage ?? "An unknown error occurred")
        })
        .fileImporter(
            isPresented: $isShowingImporter,
            allowedContentTypes: importerContentTypes,
            allowsMultipleSelection: importerAllowsMultipleSelection,
            onCompletion: handleImporterResult
        )
    }
}

private extension macOSAddTorrent {
    // MARK: - Subviews

    var header: some View {
        HStack {
            Text("Add Torrent")
                .font(.headline)

            if store.magnetQueueTotal > 1, store.magnetQueueDisplayIndex > 0 {
                Text("(\(store.magnetQueueDisplayIndex)/\(store.magnetQueueTotal))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
    }

    var footer: some View {
        HStack {
            Spacer()

            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Button("Add", action: submit)
                .keyboardShortcut(.defaultAction)
                .disabled(isAddDisabled)
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
    }

    var addTorrentForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            torrentSourceSection
            inputSection
            downloadLocationSection
        }
        .padding()
        .onAppear(perform: applyInitialState)
    }

    var torrentSourceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Torrent Source")
                .font(.headline)
                .foregroundColor(.primary)

            HStack(spacing: 16) {
                TorrentSourceCard(
                    title: "Magnet Link",
                    subtitle: "Add torrent using a magnet link",
                    systemImage: "link",
                    isSelected: inputMethod == .magnetLink,
                    action: selectMagnetLink
                )

                TorrentSourceCard(
                    title: "Torrent File",
                    subtitle: "Add torrent using a .torrent file",
                    systemImage: "doc",
                    isSelected: inputMethod == .torrentFile,
                    action: selectTorrentFile
                )
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    var inputSection: some View {
        if inputMethod == .magnetLink {
            magnetInputSection
        } else {
            torrentFileInputSection
        }
    }

    var magnetInputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Enter magnet link:")
                .font(.subheadline)
                .foregroundColor(.secondary)

            TextField("magnet:?xt=urn:btih:...", text: $alertInput)
                .textFieldStyle(.roundedBorder)
                .frame(height: 30)
                .onSubmit(submit)
        }
        .frame(height: 80)
    }

    var torrentFileInputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Select torrent file:")
                .font(.subheadline)
                .foregroundColor(.secondary)

            HStack {
                if selectedTorrentFiles.isEmpty {
                    Text("No files selected")
                        .foregroundColor(.secondary)
                } else {
                    Text("\(selectedTorrentFiles.count) files selected")
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                Button("Choose Files…") {
                    presentImporter(.torrentFiles)
                }
                .controlSize(.regular)
            }
            .padding(8)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(6)
        }
        .frame(height: 80)
    }

    var downloadLocationSection: some View {
        VStack(alignment: .leading) {
            Text("Download Location")
                .font(.headline)
                .foregroundColor(.primary)

            HStack(spacing: 8) {
                TextField("Download path", text: $downloadDir)
                    .textFieldStyle(.roundedBorder)
                    .frame(height: 24)

                Button {
                    presentImporter(.downloadFolder)
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless)
                .help("Choose download location")
            }
        }
    }
}

private extension macOSAddTorrent {
    // MARK: - Actions

    func submit() {
        switch inputMethod {
        case .magnetLink:
            addMagnetTorrent()
        case .torrentFile:
            addSelectedTorrentFiles()
        }
    }

    func addMagnetTorrent() {
        addTorrentAction(
            alertInput: alertInput,
            downloadDir: downloadDir,
            store: store,
            errorMessage: $errorMessage,
            showingError: $showingError,
            onSuccess: { dismiss() }
        )
    }

    func addSelectedTorrentFiles() {
        guard !selectedTorrentFiles.isEmpty else { return }

        for torrentFile in selectedTorrentFiles {
            addTorrentFile(fileData: torrentFile.data)
        }

        dismiss()
    }

    func handleImporterResult(_ result: Result<[URL], Error>) {
        defer { activeImporter = nil }

        guard let activeImporter else { return }

        switch activeImporter {
        case .torrentFiles:
            handleTorrentFileImportResult(result)
        case .downloadFolder:
            handleDownloadFolderImportResult(result)
        }
    }

    func handleTorrentFileImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                do {
                    let fileData = try Data(contentsOf: url)
                    selectedTorrentFiles.append((name: url.lastPathComponent, data: fileData))
                } catch {
                    handleAddTorrentError(
                        "Error loading torrent file: \(error.localizedDescription)",
                        errorMessage: $errorMessage,
                        showingError: $showingError
                    )
                }
            }
        case .failure(let error):
            handleAddTorrentError(
                "File import failed: \(error.localizedDescription)",
                errorMessage: $errorMessage,
                showingError: $showingError
            )
        }
    }

    func handleDownloadFolderImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            downloadDir = url.path
        case .failure(let error):
            handleAddTorrentError(
                "Folder selection failed: \(error.localizedDescription)",
                errorMessage: $errorMessage,
                showingError: $showingError
            )
        }
    }

    private func presentImporter(_ importer: ActiveImporter) {
        activeImporter = importer
        isShowingImporter = true
    }

    func selectMagnetLink() {
        inputMethod = .magnetLink
        selectedTorrentFiles = []
    }

    func selectTorrentFile() {
        inputMethod = .torrentFile
        alertInput = ""
    }

    func applyInitialState() {
        downloadDir = store.defaultDownloadDir

        if let initial = store.addTorrentInitialMode {
            switch initial {
            case .magnet:
                inputMethod = .magnetLink
            case .file:
                inputMethod = .torrentFile
            }
            store.addTorrentInitialMode = nil
        }

        if let prefill = store.addTorrentPrefill, !prefill.isEmpty {
            inputMethod = .magnetLink
            alertInput = prefill
            store.addTorrentPrefill = nil
        }
    }

    func addTorrentFile(fileData: Data) {
        let fileStream = fileData.base64EncodedString(options: [])
        let info = makeConfig(store: store)

        addTorrent(
            fileUrl: fileStream,
            saveLocation: downloadDir,
            auth: info.auth,
            file: true,
            config: info.config,
            onAdd: { response in
                if response.response != TransmissionResponse.success {
                    handleAddTorrentError(
                        "Failed to add torrent: \(response.response)",
                        errorMessage: $errorMessage,
                        showingError: $showingError
                    )
                }
            }
        )
    }
}

private struct TorrentSourceCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: systemImage)
                        .font(.system(size: 14))
                        .foregroundColor(isSelected ? .white : .accentColor)
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(isSelected ? Color.accentColor : Color.accentColor.opacity(0.1))
                        )

                    Text(title)
                        .fontWeight(.medium)

                    Spacer()
                }

                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(isSelected ? .secondary : .secondary.opacity(0.7))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.2) : Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: 1)
            )
            .foregroundColor(isSelected ? .accentColor : .primary)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Preview
#Preview("Add Torrent") {
    macOSAddTorrent(store: AppStore())
}
#endif
