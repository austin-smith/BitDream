import Foundation
import SwiftUI
import KeychainAccess

#if os(macOS)

// MARK: - Table Row Data Model
struct TorrentTableRow: Identifiable, Hashable {
    let id: Int
    let torrent: Torrent
    
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
    var priority: String { 
        // This would need to be added to Torrent model if not available
        "Normal" // Placeholder
    }
    
    init(torrent: Torrent) {
        self.id = torrent.id
        self.torrent = torrent
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: TorrentTableRow, rhs: TorrentTableRow) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Torrent Table View
struct macOSTorrentListCompactView: View {
    let torrents: [Torrent]
    @Binding var selection: Set<Int>
    @State private var sortOrder = [KeyPathComparator(\TorrentTableRow.name)]
    let store: Store
    
    @State private var deleteDialog: Bool = false
    @State private var labelDialog: Bool = false
    @State private var labelInput: String = ""
    @State private var shouldSave: Bool = false
    @State private var showingError = false
    @State private var errorMessage = ""
    
    private var rows: [TorrentTableRow] {
        torrents.map { TorrentTableRow(torrent: $0) }
    }
    
    private var selectedTorrents: Binding<Set<Torrent>> {
        Binding<Set<Torrent>>(
            get: {
                Set(selection.compactMap { id in
                    torrents.first { $0.id == id }
                })
            },
            set: { newSelection in
                selection = Set(newSelection.map { $0.id })
            }
        )
    }
    
    var body: some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            // Status icon column
            TableColumn("") { row in
                statusIcon(for: row.torrent)
                    .font(.system(size: 12))
                    .foregroundColor(statusColor(for: row.torrent))
                    .frame(width: 16)
            }
            .width(20)
            
            // Name column (always visible)
            TableColumn("Name", value: \.name) { row in
                Text(row.name)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .width(min: 150, ideal: 250, max: 400)
            
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
            
            // Status column
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
            
            // Total size column
            TableColumn("Size", value: \.totalBytes) { row in
                Text(byteCountFormatter.string(fromByteCount: row.totalBytes))
                    .font(.system(size: 10, design: .monospaced))
            }
            .width(min: 70, ideal: 90)
            
            // Downloaded column
            TableColumn("Downloaded", value: \.downloadedBytes) { row in
                Text(byteCountFormatter.string(fromByteCount: row.downloadedBytes))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .width(min: 80, ideal: 100)
            
            // Speed column (only show when active)
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
            .width(min: 100, ideal: 140)
            
            // ETA column
            TableColumn("ETA") { row in
                Text(etaText(for: row))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .width(min: 60, ideal: 80)
            
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
            .width(min: 80, ideal: 120, max: 200)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .contextMenu(forSelectionType: TorrentTableRow.ID.self) { selection in
            torrentContextMenu(for: selection)
        }
        .sheet(isPresented: $labelDialog) {
            VStack(spacing: 16) {
                let selectedTorrentsSet = Set(selection.compactMap { id in
                    torrents.first { $0.id == id }
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
                        torrents.first { $0.id == id }
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
                        torrents.first { $0.id == id }
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
                showingError: $showingError,
                errorMessage: $errorMessage
            )
        }
    }
}

#else
// Empty struct for iOS to reference
struct macOSTorrentListCompactView: View {
    let torrents: [Torrent]
    @Binding var selection: Set<Int>
    let store: Store
    
    var body: some View {
        EmptyView()
    }
}
#endif
