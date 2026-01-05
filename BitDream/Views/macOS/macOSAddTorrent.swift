import Foundation
import SwiftUI
import KeychainAccess
import UniformTypeIdentifiers
import CoreData

#if os(macOS)
struct macOSAddTorrent: View {
    // MARK: - Properties
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: Store

    @State private var inputMethod: TorrentInputMethod = .magnetLink
    @State private var alertInput: String = ""
    @State private var downloadDir: String = ""
    @State private var errorMessage: String? = nil
    @State private var showingError = false
    @State private var selectedTorrentFiles: [(name: String, data: Data)] = []
    private enum ActiveImporter {
        case torrentFiles
        case downloadFolder
    }
    @State private var activeImporter: ActiveImporter? = nil
    @State private var isShowingImporter: Bool = false

    enum TorrentInputMethod: String, CaseIterable, Identifiable {
        case magnetLink = "Magnet Link"
        case torrentFile = "Torrent File"

        var id: String { self.rawValue }
    }

    // MARK: - Body
    var body: some View {
        VStack(spacing: 0) {
            // Header with queue indicator (1/N)
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

            Divider()

            // Form content
            ScrollView {
                addTorrentForm
            }

            Divider()

            // Footer with buttons
            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Add") {
                    if inputMethod == .magnetLink {
                        addTorrentAction(
                            alertInput: alertInput,
                            downloadDir: downloadDir,
                            store: store,
                            errorMessage: $errorMessage,
                            showingError: $showingError,
                            onSuccess: { dismiss() }
                        )
                    } else if inputMethod == .torrentFile && !selectedTorrentFiles.isEmpty {
                        // Add each selected torrent file
                        for torrentFile in selectedTorrentFiles {
                            addTorrentFile(fileData: torrentFile.data)
                        }
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(inputMethod == .magnetLink ? alertInput.isEmpty : selectedTorrentFiles.isEmpty)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 600, height: 400)
        .alert("Error", isPresented: $showingError, actions: {
            Button("OK", role: .cancel) {}
        }, message: {
            Text(errorMessage ?? "An unknown error occurred")
        })
        .fileImporter(
            isPresented: $isShowingImporter,
            allowedContentTypes: activeImporter == .downloadFolder ? [.folder] : [UTType.torrent],
            allowsMultipleSelection: activeImporter == .torrentFiles
        ) { result in
            switch activeImporter {
            case .torrentFiles:
                switch result {
                case .success(let urls):
                    for url in urls {
                        do {
                            let fileData = try Data(contentsOf: url)
                            selectedTorrentFiles.append((name: url.lastPathComponent, data: fileData))
                        } catch {
                            handleAddTorrentError("Error loading torrent file: \(error.localizedDescription)", errorMessage: $errorMessage, showingError: $showingError)
                        }
                    }
                case .failure(let error):
                    handleAddTorrentError("File import failed: \(error.localizedDescription)", errorMessage: $errorMessage, showingError: $showingError)
                }
            case .downloadFolder:
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        downloadDir = url.path
                    }
                case .failure(let error):
                    handleAddTorrentError("Folder selection failed: \(error.localizedDescription)", errorMessage: $errorMessage, showingError: $showingError)
                }
            case .none:
                break
            }
            // Reset active importer after completion
            activeImporter = nil
        }
    }

    // MARK: - Form View
    var addTorrentForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Torrent Source Section
            VStack(alignment: .leading, spacing: 8) {
                Text("Torrent Source")
                    .font(.headline)
                    .foregroundColor(.primary)

                // Card-style selection buttons
                HStack(spacing: 16) {
                    // Magnet Link Card
                    Button(action: {
                        inputMethod = .magnetLink
                        selectedTorrentFiles = []
                    }) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "link")
                                    .font(.system(size: 14))
                                    .foregroundColor(inputMethod == .magnetLink ? .white : .accentColor)
                                    .frame(width: 28, height: 28)
                                    .background(
                                        Circle()
                                            .fill(inputMethod == .magnetLink ? Color.accentColor : Color.accentColor.opacity(0.1))
                                    )
                                Text("Magnet Link")
                                    .fontWeight(.medium)
                                Spacer()
                            }

                            Text("Add torrent using a magnet link")
                                .font(.caption)
                                .foregroundColor(inputMethod == .magnetLink ? .secondary : .secondary.opacity(0.7))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(inputMethod == .magnetLink ?
                                      Color.accentColor.opacity(0.2) :
                                      Color(NSColor.controlBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(inputMethod == .magnetLink ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: 1)
                        )
                        .foregroundColor(inputMethod == .magnetLink ? .accentColor : .primary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .frame(maxWidth: .infinity)

                    // Torrent File Card
                    Button(action: {
                        inputMethod = .torrentFile
                        alertInput = ""
                    }) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "doc")
                                    .font(.system(size: 14))
                                    .foregroundColor(inputMethod == .torrentFile ? .white : .accentColor)
                                    .frame(width: 28, height: 28)
                                    .background(
                                        Circle()
                                            .fill(inputMethod == .torrentFile ? Color.accentColor : Color.accentColor.opacity(0.1))
                                    )
                                Text("Torrent File")
                                    .fontWeight(.medium)
                                Spacer()
                            }

                            Text("Add torrent using a .torrent file")
                                .font(.caption)
                                .foregroundColor(inputMethod == .torrentFile ? .secondary : .secondary.opacity(0.7))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(inputMethod == .torrentFile ?
                                      Color.accentColor.opacity(0.2) :
                                      Color(NSColor.controlBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(inputMethod == .torrentFile ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: 1)
                        )
                        .foregroundColor(inputMethod == .torrentFile ? .accentColor : .primary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity)
            }

            // Conditional input section - only show one at a time
            Group {
                if inputMethod == .magnetLink {
                    // Magnet link input
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Enter magnet link:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        TextField("magnet:?xt=urn:btih:...", text: $alertInput)
                            .textFieldStyle(.roundedBorder)
                            .frame(height: 30)
                            .onSubmit {
                                guard !alertInput.isEmpty else { return }
                                addTorrentAction(
                                    alertInput: alertInput,
                                    downloadDir: downloadDir,
                                    store: store,
                                    errorMessage: $errorMessage,
                                    showingError: $showingError,
                                    onSuccess: { dismiss() }
                                )
                            }
                    }
                    .frame(height: 80) // Fixed height for both sections
                } else {
                    // Torrent file selection
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
                                activeImporter = .torrentFiles
                                isShowingImporter = true
                            }
                            .controlSize(.regular)
                        }
                        .padding(8)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(6)
                    }
                    .frame(height: 80) // Fixed height for both sections
                }
            }

            // Download Location Section
            VStack(alignment: .leading) {
                Text("Download Location")
                    .font(.headline)
                    .foregroundColor(.primary)

                HStack(spacing: 8) {
                    TextField("Download path", text: $downloadDir)
                        .textFieldStyle(.roundedBorder)
                        .frame(height: 24)

                    Button(action: {
                        activeImporter = .downloadFolder
                        isShowingImporter = true
                    }) {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.borderless)
                    .help("Choose download location")
                }
            }
        }
        .padding()
        .onAppear {
            downloadDir = store.defaultDownloadDir
            #if os(macOS)
            if let initial = store.addTorrentInitialMode {
                switch initial {
                case .magnet:
                    inputMethod = .magnetLink
                case .file:
                    inputMethod = .torrentFile
                }
                store.addTorrentInitialMode = nil
            }
            // Pre-fill magnet link if provided by delegate
            if let prefill = store.addTorrentPrefill, !prefill.isEmpty {
                inputMethod = .magnetLink
                alertInput = prefill
                // Clear after consuming so subsequent opens don't reuse it
                store.addTorrentPrefill = nil
            }
            #endif
        }
    }

    // MARK: - File Pickers (SwiftUI wrappers handled by .fileImporter)
    private func addTorrentFile(fileData: Data) {
        let fileStream = fileData.base64EncodedString(options: NSData.Base64EncodingOptions(rawValue: 0))

        let info = makeConfig(store: store)
        addTorrent(
            fileUrl: fileStream,
            saveLocation: downloadDir,
            auth: info.auth,
            file: true,
            config: info.config,
            onAdd: { response in
                // Ensure UI updates happen on the main thread
                DispatchQueue.main.async {
                    if response.response != TransmissionResponse.success {
                        handleAddTorrentError("Failed to add torrent: \(response.response)", errorMessage: $errorMessage, showingError: $showingError)
                    }
                }
            }
        )
    }

    // Download folder selection handled by .fileImporter
}

// MARK: - Preview
#Preview("Add Torrent") {
    macOSAddTorrent(store: Store())
}

#else
// Empty struct for iOS to reference - this won't be compiled on iOS but provides the type
struct macOSAddTorrent: View {
    @ObservedObject var store: Store

    init(store: Store) {
        self.store = store
    }

    var body: some View {
        EmptyView()
    }
}
#endif
