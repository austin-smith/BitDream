import Foundation
import SwiftUI
import KeychainAccess

#if os(macOS)

// MARK: - Table Row Data Model with Binding Support
struct TorrentTableRow: Identifiable, Hashable {
    let id: Int
    @Binding var torrent: Torrent
    
    // Computed properties for sorting
    var name: String { torrent.name }
    var status: String { torrent.statusCalc.rawValue }
    var progress: Double { torrent.percentDone }
    var downloadedBytes: Int64 { torrent.downloadedCalc }
    var totalBytes: Int64 { torrent.sizeWhenDone }
    var downloadSpeed: Int64 { torrent.rateDownload }
    var uploadSpeed: Int64 { torrent.rateUpload }
    var eta: Int { torrent.eta }
    var labels: [String] { torrent.labels }
    
    init(torrent: Binding<Torrent>) {
        self.id = torrent.wrappedValue.id
        self._torrent = torrent
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        // Include key properties that change to ensure proper updates
        hasher.combine(torrent.name)
        hasher.combine(torrent.labels)
        hasher.combine(torrent.status)
        hasher.combine(torrent.percentDone)
        hasher.combine(torrent.rateDownload)
        hasher.combine(torrent.rateUpload)
        hasher.combine(torrent.eta)
    }
    
    static func == (lhs: TorrentTableRow, rhs: TorrentTableRow) -> Bool {
        lhs.id == rhs.id &&
        lhs.torrent.name == rhs.torrent.name &&
        lhs.torrent.labels == rhs.torrent.labels &&
        lhs.torrent.status == rhs.torrent.status &&
        lhs.torrent.percentDone == rhs.torrent.percentDone &&
        lhs.torrent.rateDownload == rhs.torrent.rateDownload &&
        lhs.torrent.rateUpload == rhs.torrent.rateUpload &&
        lhs.torrent.eta == rhs.torrent.eta
    }
}

// MARK: - Torrent Table View
struct macOSTorrentListCompact: View {
    let torrents: [Torrent]  // Keep this to match how it's called from parent
    @Binding var selection: Set<Int>
    @State private var sortOrder = [KeyPathComparator(\TorrentTableRow.name)]
    let store: Store
    let showContentTypeIcons: Bool
    
    @State private var deleteDialog: Bool = false
    @State private var labelDialog: Bool = false
    @State private var labelInput: String = ""
    @State private var shouldSave: Bool = false
    @State private var renameDialog: Bool = false
    @State private var renameInput: String = ""
    @State private var renameTargetId: Int? = nil
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var columnCustomization = TableColumnCustomization<TorrentTableRow>()
    private static let columnCustomizationKey = "mac.compact.columns.v1"
    @AppStorage(Self.columnCustomizationKey) private var columnCustomizationData: Data?
    
    
    // Create bindings to the actual torrents in the store (like expanded view does)
    private var rows: [TorrentTableRow] {
        torrents.compactMap { torrent in
            // Find the actual torrent in the store and create a binding to it
            if let storeIndex = store.torrents.firstIndex(where: { $0.id == torrent.id }) {
                let binding = Binding<Torrent>(
                    get: { store.torrents[storeIndex] },
                    set: { store.torrents[storeIndex] = $0 }
                )
                return TorrentTableRow(torrent: binding)
            }
            return nil
        }
    }
    
    private var sortedRows: [TorrentTableRow] {
        rows.sorted(using: sortOrder)
    }
    
    private var selectedTorrents: Binding<Set<Torrent>> {
        Binding<Set<Torrent>>(
            get: {
                Set(selection.compactMap { id in
                    store.torrents.first { $0.id == id }
                })
            },
            set: { newSelection in
                selection = Set(newSelection.map { $0.id })
            }
        )
    }
    
    var body: some View {
        Table(sortedRows, selection: $selection, sortOrder: $sortOrder, columnCustomization: $columnCustomization, columns: {
            // Status icon column
            TableColumn("") { row in
                statusIcon(for: row.torrent)
                    .font(.system(size: 12))
                    .foregroundColor(statusColor(for: row.torrent))
                    .frame(width: 16)
            }
            .width(20)
            .customizationID("statusIcon")
            
            // Content type icon column (feature-gated)
            if showContentTypeIcons {
                TableColumn("") { row in
                    Image(systemName: ContentTypeIconMapper.symbolForTorrent(mimeType: row.torrent.primaryMimeType))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.6))
                        .frame(width: 12)
                }
                .width(20)
                .customizationID("contentType")
            }
            
            // Name column
            TableColumn("Name", value: \.name) { row in
                Text(row.name)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .width(min: 150, ideal: 250, max: 600)
            .customizationID("name")
            
            // Progress column
            TableColumn("Progress", value: \.progress) { row in
                HStack(spacing: 4) {
                    ProgressView(value: row.torrent.metadataPercentComplete < 1 ? 1 : row.progress)
                        .tint(progressColorForTorrent(row.torrent))
                        .frame(height: 6)
                    
                    Text(String(format: "%.1f%%", row.progress * 100))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            .width(min: 100, ideal: 120)
            .customizationID("progress")
            
            // Status text column
            TableColumn("Status", value: \.status) { row in
                if row.torrent.error != TorrentError.ok.rawValue {
                    Text("Error")
                        .font(.system(size: 10))
                        .foregroundColor(.red)
                } else {
                    Text(row.status)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            .width(min: 80, ideal: 120)
            .customizationID("status")
            
            // Total size column
            TableColumn("Size", value: \.totalBytes) { row in
                Text(byteCountFormatter.string(fromByteCount: row.totalBytes))
                    .font(.system(size: 10, design: .monospaced))
            }
            .width(min: 70, ideal: 90)
            .customizationID("size")
            
            // Downloaded column
            TableColumn("Downloaded", value: \.downloadedBytes) { row in
                Text(byteCountFormatter.string(fromByteCount: row.downloadedBytes))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .width(min: 80, ideal: 100)
            .customizationID("downloaded")
            
            // Speed column
            TableColumn("Speed") { row in
                HStack(spacing: 4) {
                    if row.downloadSpeed > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 8))
                            Text(byteCountFormatter.string(fromByteCount: row.downloadSpeed) + "/s")
                                .font(.system(size: 9, design: .monospaced))
                        }
                        .foregroundColor(.blue)
                    }
                    
                    if row.uploadSpeed > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 8))
                            Text(byteCountFormatter.string(fromByteCount: row.uploadSpeed) + "/s")
                                .font(.system(size: 9, design: .monospaced))
                        }
                        .foregroundColor(.green)
                    }
                }
            }
            .width(min: 100, ideal: 140, max: 200)
            .customizationID("speed")
            
            // ETA column
            TableColumn("ETA") { row in
                Text(etaText(for: row))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .width(min: 60, ideal: 80)
            .customizationID("eta")
            
            // Labels column
            TableColumn("Labels") { row in
                if !row.labels.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 2) {
                            ForEach(row.labels.prefix(3), id: \.self) { label in
                                LabelTag(label: label)
                                    .font(.system(size: 9))
                            }
                            if row.labels.count > 3 {
                                Text("+\(row.labels.count - 3)")
                                    .font(.system(size: 8))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .width(min: 80, ideal: 120, max: 300)
            .customizationID("labels")
        })
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .animation(.default, value: sortOrder)
        .contextMenu(forSelectionType: TorrentTableRow.ID.self) { selection in
            torrentContextMenu(for: selection)
        }
        .sheet(isPresented: $renameDialog) {
            // Determine single selected torrent for rename
            let selectedTorrentsSet = Set(selection.compactMap { id in
                store.torrents.first { $0.id == id }
            })
            if selectedTorrentsSet.count == 1, let t = selectedTorrentsSet.first {
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
        .sheet(isPresented: $labelDialog) {
            VStack(spacing: 16) {
                let selectedTorrentsSet = Set(selection.compactMap { id in
                    store.torrents.first { $0.id == id }
                })
                
                Text("Edit Labels\(selectedTorrentsSet.count > 1 ? " (\(selectedTorrentsSet.count) torrents)" : "")")
                    .font(.headline)
                
                LabelEditView(
                    labelInput: $labelInput,
                    // Show existing labels for single torrent, empty for multi-torrent (append mode)
                    existingLabels: selectedTorrentsSet.count == 1 ? Array(selectedTorrentsSet.first!.labels) : [],
                    store: store,
                    torrentIds: Array(selectedTorrentsSet.map { $0.id }),
                    selectedTorrents: selectedTorrentsSet,
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
            "Delete \(selection.count > 1 ? "\(selection.count) Torrents" : "Torrent")",
            isPresented: $deleteDialog) {
                Button(role: .destructive) {
                    let info = makeConfig(store: store)
                    let selectedTorrentsSet = Set(selection.compactMap { id in
                        store.torrents.first { $0.id == id }
                    })
                    for t in selectedTorrentsSet {
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
                    let selectedTorrentsSet = Set(selection.compactMap { id in
                        store.torrents.first { $0.id == id }
                    })
                    for t in selectedTorrentsSet {
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
        .onAppear {
            if let data = columnCustomizationData {
                do {
                    let decoded = try JSONDecoder().decode(TableColumnCustomization<TorrentTableRow>.self, from: data)
                    columnCustomization = decoded
                } catch {
                    let dataSummary = data.base64EncodedString()
                    print("Failed to decode columnCustomizationData to TableColumnCustomization<TorrentTableRow>: \(error). Data (base64): \(dataSummary)")
                    columnCustomization = TableColumnCustomization<TorrentTableRow>()
                }
            }
        }
        .onChange(of: columnCustomization) { oldValue, newValue in
            do {
                let encoded = try JSONEncoder().encode(newValue)
                columnCustomizationData = encoded
            } catch {
                print("Failed to encode columnCustomization: \(error)")
                print("Failed to encode columnCustomization (TableColumnCustomization<TorrentTableRow>): \(error.localizedDescription)")
            }
        }
    }
    
    private func statusIcon(for torrent: Torrent) -> Image {
        if torrent.error != TorrentError.ok.rawValue {
            return Image(systemName: "exclamationmark.triangle.fill")
        }
        
        switch torrent.statusCalc {
        case .downloading, .retrievingMetadata:
            return Image(systemName: "arrow.down.circle.fill")
        case .seeding:
            return Image(systemName: "arrow.up.circle.fill")
        case .paused:
            return Image(systemName: "pause.circle.fill")
        case .complete:
            return Image(systemName: "checkmark.circle.fill")
        case .queued:
            return Image(systemName: "clock.fill")
        case .verifyingLocalData:
            return Image(systemName: "checkmark.arrow.trianglehead.counterclockwise")
        case .stalled:
            return Image(systemName: "exclamationmark.circle.fill")
        case .unknown:
            return Image(systemName: "questionmark.circle.fill")
        }
    }
    
    private func statusColor(for torrent: Torrent) -> Color {
        if torrent.error != TorrentError.ok.rawValue {
            return .red
        }
        
        switch torrent.statusCalc {
        case .downloading, .retrievingMetadata:
            return .blue
        case .seeding:
            return .green
        case .paused:
            return .gray
        case .complete:
            return .green
        case .queued:
            return .orange
        case .verifyingLocalData:
            return .purple
        case .stalled:
            return .orange
        case .unknown:
            return .gray
        }
    }
    
    private func etaText(for row: TorrentTableRow) -> String {
        guard row.torrent.statusCalc == .downloading && row.eta >= 0 else {
            return "—"
        }
        
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        
        return formatter.string(from: TimeInterval(row.eta)) ?? "—"
    }
    
    @ViewBuilder
    private func torrentContextMenu(for selection: Set<TorrentTableRow.ID>) -> some View {
        let selectedRows = rows.filter { selection.contains($0.id) }
        let selectedTorrents = selectedRows.map { $0.torrent }
        
        if selection.isEmpty {
            Button("Select All") {
                self.selection = Set(rows.map { $0.id })
            }
        } else {
            // The context menu will be handled by TorrentRowModifier
            createTorrentContextMenu(
                torrents: Set(selectedTorrents),
                store: store,
                labelInput: $labelInput,
                labelDialog: $labelDialog,
                deleteDialog: $deleteDialog,
                renameInput: $renameInput,
                renameDialog: $renameDialog,
                renameTargetId: $renameTargetId,
                showingError: $showingError,
                errorMessage: $errorMessage
            )
        }
    }
    
}

#else
// Empty struct for iOS to reference
struct macOSTorrentListCompact: View {
    let torrents: [Torrent]
    @Binding var selection: Set<Int>
    let store: Store
    let showContentTypeIcons: Bool
    
    var body: some View {
        EmptyView()
    }
}
#endif