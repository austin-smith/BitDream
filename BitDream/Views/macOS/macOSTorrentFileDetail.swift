import Foundation
import SwiftUI

#if os(macOS)

// MARK: - View Model

class FileTableViewModel: ObservableObject {
    @Published var searchText = ""
    @Published var sortOrder = [KeyPathComparator(\TorrentFileRow.name)]
    @Published var selection = Set<TorrentFileRow.ID>()
    
    // Filter toggles
    @Published var showLowPriority = true
    @Published var showNormalPriority = true
    @Published var showHighPriority = true
    @Published var showWantedFiles = true
    @Published var showSkippedFiles = true
    @Published var showCompleteFiles = true
    @Published var showIncompleteFiles = true
    
    // File type filters
    @Published var showVideos = true
    @Published var showAudio = true
    @Published var showImages = true
    @Published var showDocuments = true
    @Published var showArchives = true
    @Published var showOther = true
    
    
    var allRows: [TorrentFileRow] = []
    
    var filteredRows: [TorrentFileRow] {
        allRows.filter { row in
            // Search filter
            if !searchText.isEmpty {
                let searchLower = searchText.lowercased()
                if !row.name.lowercased().contains(searchLower) {
                    return false
                }
            }
            
            // Priority filters
            let priority = FilePriority(rawValue: row.priority) ?? .normal
            switch priority {
            case .low:
                if !showLowPriority { return false }
            case .normal:
                if !showNormalPriority { return false }
            case .high:
                if !showHighPriority { return false }
            }
            
            // Wanted/Skip filter
            if row.wanted && !showWantedFiles { return false }
            if !row.wanted && !showSkippedFiles { return false }
            
            // Completion filter
            let isComplete = row.percentDone >= 1.0
            if isComplete && !showCompleteFiles { return false }
            if !isComplete && !showIncompleteFiles { return false }
            
            // File type filter
            let fileType = fileTypeCategory(row.name)
            switch fileType {
            case .video: if !showVideos { return false }
            case .audio: if !showAudio { return false }
            case .image: if !showImages { return false }
            case .document: if !showDocuments { return false }
            case .archive: if !showArchives { return false }
            case .other: if !showOther { return false }
            }
            
            return true
        }
        .sorted(using: sortOrder)
    }
    
    
    func updateData(files: [TorrentFile], fileStats: [TorrentFileStats]) {
        let processedFiles = processFilesForDisplay(files, stats: fileStats)
        
        allRows = processedFiles.map { processed in
            TorrentFileRow(
                file: processed.file,
                stats: processed.stats,
                percentDone: processed.file.percentDone,
                priority: processed.stats.priority,
                wanted: processed.stats.wanted,
                displayName: processed.displayName,
                fileIndex: processed.fileIndex
            )
        }
    }
}


// MARK: - Main View

struct macOSTorrentFileDetail: View {
    let files: [TorrentFile]
    let fileStats: [TorrentFileStats]
    let torrentId: Int
    let store: Store
    
    @StateObject private var viewModel = FileTableViewModel()
    @State private var columnVisibility = Set<String>(["name", "size", "progress", "downloaded", "priority", "status"])
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with search and filters
            HeaderView(viewModel: viewModel)
                .padding(.horizontal)
                .padding(.vertical, 12)
            
            Divider()
            
            // Table
            Table(viewModel.filteredRows, selection: $viewModel.selection, sortOrder: $viewModel.sortOrder) {
                TableColumn("") { row in
                    Toggle("", isOn: Binding(
                        get: { row.wanted },
                        set: { newValue in
                            setFilesWanted([row], wanted: newValue)
                        }
                    ))
                    .toggleStyle(.checkbox)
                    .help(row.wanted ? "Don't download this file" : "Download this file")
                }
                .width(20)
                
                TableColumn("Name", value: \.displayName) { row in
                    Text(row.displayName)
                        .opacity(row.wanted ? 1.0 : 0.6)
                }
                .width(min: 160, ideal: 230)
                
                TableColumn("Type", value: \.fileExtension) { row in
                    HStack {
                        FileTypeChip(filename: row.name, iconSize: 12)
                        Spacer()
                    }
                    .opacity(row.wanted ? 1.0 : 0.6)
                }
                .width(min: 70, ideal: 80)
                
                TableColumn("Size", value: \.sizeDisplay) { row in
                    Text(row.sizeDisplay)
                        .font(.system(.caption, design: .monospaced))
                        .opacity(row.wanted ? 1.0 : 0.6)
                }
                .width(min: 80, ideal: 100)
                
                TableColumn("Downloaded", value: \.downloadedDisplay) { row in
                    Text(row.downloadedDisplay)
                        .font(.system(.caption, design: .monospaced))
                        .opacity(row.wanted ? 1.0 : 0.6)
                }
                .width(min: 80, ideal: 100)
                
                TableColumn("Progress", value: \.progressDisplay) { row in
                    FileProgressView(percentDone: row.percentDone)
                        .opacity(row.wanted ? 1.0 : 0.6)
                }
                .width(min: 90, ideal: 110)
                
                TableColumn("Priority", value: \.priorityDisplay) { row in
                    HStack {
                        let priority = FilePriority(rawValue: row.priority) ?? .normal
                        PriorityBadge(priority: priority)
                        Spacer()
                    }
                    .opacity(row.wanted ? 1.0 : 0.4)
                }
                .width(min: 70, ideal: 80)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
            .animation(.default, value: viewModel.sortOrder)
            .contextMenu(forSelectionType: TorrentFileRow.ID.self) { selection in
                if selection.isEmpty {
                    // No selection - show general options
                    Button("Select All") {
                        viewModel.selection = Set(viewModel.filteredRows.map { $0.id })
                    }
                } else {
                    // File(s) selected - show file operations
                    let selectedRows = viewModel.filteredRows.filter { selection.contains($0.id) }
                    
                    Section("Status") {
                        Toggle("Download", isOn: Binding(
                            get: { selectedRows.allSatisfy({ $0.wanted }) },
                            set: { _ in setFilesWanted(selectedRows, wanted: true) }
                        ))
                        
                        Toggle("Don't Download", isOn: Binding(
                            get: { selectedRows.allSatisfy({ !$0.wanted }) },
                            set: { _ in setFilesWanted(selectedRows, wanted: false) }
                        ))
                    }
                    
                    Section("Priority") {
                        Toggle("High", isOn: Binding(
                            get: { selectedRows.allSatisfy({ $0.priority == FilePriority.high.rawValue }) },
                            set: { _ in setFilesPriority(selectedRows, priority: .high) }
                        ))
                        
                        Toggle("Normal", isOn: Binding(
                            get: { selectedRows.allSatisfy({ $0.priority == FilePriority.normal.rawValue }) },
                            set: { _ in setFilesPriority(selectedRows, priority: .normal) }
                        ))
                        
                        Toggle("Low", isOn: Binding(
                            get: { selectedRows.allSatisfy({ $0.priority == FilePriority.low.rawValue }) },
                            set: { _ in setFilesPriority(selectedRows, priority: .low) }
                        ))
                    }
                }
            }
            
            // Footer with file count
            FooterView(totalCount: files.count, filteredCount: viewModel.filteredRows.count)
                .padding(.horizontal)
                .padding(.vertical, 8)
        }
        .frame(minHeight: 300)
        .onAppear {
            viewModel.updateData(files: files, fileStats: fileStats)
        }
    }
    
    // MARK: - File Operations
    
    private func setFilesWanted(_ selectedRows: [TorrentFileRow], wanted: Bool) {
        let fileIndices = selectedRows.map { $0.fileIndex }
        let info = makeConfig(store: store)
        
        setFileWantedStatus(
            torrentId: torrentId,
            fileIndices: fileIndices,
            wanted: wanted,
            info: info
        ) { response in
            handleTransmissionResponse(response,
                onSuccess: {
                    print("Successfully set wanted status")
                    // File data will refresh automatically through the binding
                },
                onError: { error in
                    print("Failed to set wanted status: \(error)")
                    // Could add user-facing error handling here if needed
                }
            )
        }
        
        // Optimistic update
        updateLocalFileStatus(selectedRows, wanted: wanted)
    }
    
    private func setFilesPriority(_ selectedRows: [TorrentFileRow], priority: FilePriority) {
        let fileIndices = selectedRows.map { $0.fileIndex }
        let info = makeConfig(store: store)
        
        setFilePriority(
            torrentId: torrentId,
            fileIndices: fileIndices,
            priority: priority,
            info: info
        ) { response in
            handleTransmissionResponse(response,
                onSuccess: {
                    print("Successfully set file priority")
                    // File data will refresh automatically through the binding
                },
                onError: { error in
                    print("Failed to set file priority: \(error)")
                    // Could add user-facing error handling here if needed
                }
            )
        }
        
        // Optimistic update
        updateLocalFilePriority(selectedRows, priority: priority)
    }
    
    private func updateLocalFileStatus(_ selectedRows: [TorrentFileRow], wanted: Bool) {
        // Update local data optimistically
        for row in selectedRows {
            if let index = viewModel.allRows.firstIndex(where: { $0.id == row.id }) {
                let updatedRow = TorrentFileRow(
                    file: files[row.fileIndex],
                    stats: TorrentFileStats(
                        bytesCompleted: viewModel.allRows[index].bytesCompleted,
                        wanted: wanted,
                        priority: viewModel.allRows[index].priority
                    ),
                    percentDone: viewModel.allRows[index].percentDone,
                    priority: viewModel.allRows[index].priority,
                    wanted: wanted,
                    displayName: viewModel.allRows[index].displayName,
                    fileIndex: viewModel.allRows[index].fileIndex
                )
                viewModel.allRows[index] = updatedRow
            }
        }
    }
    
    private func updateLocalFilePriority(_ selectedRows: [TorrentFileRow], priority: FilePriority) {
        // Update local data optimistically
        for row in selectedRows {
            if let index = viewModel.allRows.firstIndex(where: { $0.id == row.id }) {
                let updatedRow = TorrentFileRow(
                    file: files[row.fileIndex],
                    stats: TorrentFileStats(
                        bytesCompleted: viewModel.allRows[index].bytesCompleted,
                        wanted: viewModel.allRows[index].wanted,
                        priority: priority.rawValue
                    ),
                    percentDone: viewModel.allRows[index].percentDone,
                    priority: priority.rawValue,
                    wanted: viewModel.allRows[index].wanted,
                    displayName: viewModel.allRows[index].displayName,
                    fileIndex: viewModel.allRows[index].fileIndex
                )
                viewModel.allRows[index] = updatedRow
            }
        }
    }
}

// MARK: - Header View

struct HeaderView: View {
    @ObservedObject var viewModel: FileTableViewModel
    
    var body: some View {
        HStack {
            // Clean search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search files...", text: $viewModel.searchText)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.background)
            .cornerRadius(6)
            .frame(maxWidth: 300)
            
            // Filter menu button
            Menu {
                Section("Priority") {
                    Toggle(FilePriority.low.displayText, isOn: $viewModel.showLowPriority)
                    Toggle(FilePriority.normal.displayText, isOn: $viewModel.showNormalPriority)
                    Toggle(FilePriority.high.displayText, isOn: $viewModel.showHighPriority)
                }
                
                Section("Status") {
                    Toggle(FileStatus.wanted, isOn: $viewModel.showWantedFiles)
                    Toggle(FileStatus.skip, isOn: $viewModel.showSkippedFiles)
                }
                
                Section("Progress") {
                    Toggle(FileCompletion.complete, isOn: $viewModel.showCompleteFiles)
                    Toggle(FileCompletion.incomplete, isOn: $viewModel.showIncompleteFiles)
                }
                
                    Section("File Types") {
                        Toggle("Videos", isOn: $viewModel.showVideos)
                        Toggle("Audio", isOn: $viewModel.showAudio)
                        Toggle("Images", isOn: $viewModel.showImages)
                        Toggle("Documents", isOn: $viewModel.showDocuments)
                        Toggle("Archives", isOn: $viewModel.showArchives)
                        Toggle("Other", isOn: $viewModel.showOther)
                    }
                    
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                    if activeFilterCount > 0 {
                        Text("Filters (\(activeFilterCount))")
                            .font(.caption)
                    } else {
                        Text("Filters")
                            .font(.caption)
                    }
                }
                .foregroundColor(hasActiveFilters ? .accentColor : .secondary)
            }
            .buttonStyle(.borderless)
            .menuStyle(.borderlessButton)
            
            Spacer()
        }
    }
    
    private var hasActiveFilters: Bool {
        !viewModel.showLowPriority || !viewModel.showNormalPriority || !viewModel.showHighPriority ||
        !viewModel.showWantedFiles || !viewModel.showSkippedFiles ||
        !viewModel.showCompleteFiles || !viewModel.showIncompleteFiles ||
        !viewModel.showVideos || !viewModel.showAudio || !viewModel.showImages ||
        !viewModel.showDocuments || !viewModel.showArchives || !viewModel.showOther
    }
    
    private var activeFilterCount: Int {
        var count = 0
        
        // Priority filters
        if !viewModel.showLowPriority { count += 1 }
        if !viewModel.showNormalPriority { count += 1 }
        if !viewModel.showHighPriority { count += 1 }
        
        // Status filters
        if !viewModel.showWantedFiles { count += 1 }
        if !viewModel.showSkippedFiles { count += 1 }
        
        // Progress filters
        if !viewModel.showCompleteFiles { count += 1 }
        if !viewModel.showIncompleteFiles { count += 1 }
        
        // File type filters
        if !viewModel.showVideos { count += 1 }
        if !viewModel.showAudio { count += 1 }
        if !viewModel.showImages { count += 1 }
        if !viewModel.showDocuments { count += 1 }
        if !viewModel.showArchives { count += 1 }
        if !viewModel.showOther { count += 1 }
        
        return count
    }
}

// MARK: - Footer View

struct FooterView: View {
    let totalCount: Int
    let filteredCount: Int
    
    var body: some View {
        HStack {
            if filteredCount < totalCount {
                Text("Showing \(filteredCount) of \(totalCount) files")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("\(totalCount) files")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
}

// MARK: - Preview

#Preview("macOS Torrent Files") {
    macOSTorrentFileDetail(
        files: TorrentFilePreviewData.sampleFiles,
        fileStats: TorrentFilePreviewData.sampleFileStats,
        torrentId: 1,
        store: Store()
    )
    .frame(width: 1000, height: 700)
}

#else
// Empty struct for iOS to reference
struct macOSTorrentFileDetail: View {
    let files: [TorrentFile]
    let fileStats: [TorrentFileStats]
    let torrentId: Int
    let store: Store
    
    var body: some View {
        EmptyView()
    }
}
#endif 
