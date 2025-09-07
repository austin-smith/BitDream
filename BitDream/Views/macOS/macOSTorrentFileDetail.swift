import Foundation
import SwiftUI

#if os(macOS)

// MARK: - View Model

class FileTableViewModel: ObservableObject {
    @Published var searchText = ""
    @Published var sortOrder = [KeyPathComparator(\TorrentFileRow.displayName)]
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
}


// MARK: - Main View

struct macOSTorrentFileDetail: View {
    let files: [TorrentFile]
    let fileStats: [TorrentFileStats]
    let torrentId: Int
    let store: Store
    
    @StateObject private var viewModel = FileTableViewModel()
    @State private var columnVisibility = Set<String>(["name", "size", "progress", "downloaded", "priority", "status"])
    @State private var mutableFileStats: [TorrentFileStats] = []
    @State private var cachedRows: [TorrentFileRow] = []
    
    private func recomputeRows() {
        let statsToUse = mutableFileStats.isEmpty ? fileStats : mutableFileStats
        let processed = processFilesForDisplay(files, stats: statsToUse)
        cachedRows = processed.map { processed in
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
    
    private var filteredRows: [TorrentFileRow] {
        cachedRows.filter { row in
            // Search filter
            if !viewModel.searchText.isEmpty {
                let searchLower = viewModel.searchText.lowercased()
                if !row.name.lowercased().contains(searchLower) { return false }
            }
            
            // Priority filters
            let priority = FilePriority(rawValue: row.priority) ?? .normal
            switch priority {
            case .low:
                if !viewModel.showLowPriority { return false }
            case .normal:
                if !viewModel.showNormalPriority { return false }
            case .high:
                if !viewModel.showHighPriority { return false }
            }
            
            // Wanted/Skip filter
            if row.wanted && !viewModel.showWantedFiles { return false }
            if !row.wanted && !viewModel.showSkippedFiles { return false }
            
            // Completion filter
            let isComplete = row.percentDone >= 1.0
            if isComplete && !viewModel.showCompleteFiles { return false }
            if !isComplete && !viewModel.showIncompleteFiles { return false }
            
            // File type filter
            let fileType = fileTypeCategory(row.name)
            switch fileType {
            case .video: if !viewModel.showVideos { return false }
            case .audio: if !viewModel.showAudio { return false }
            case .image: if !viewModel.showImages { return false }
            case .document: if !viewModel.showDocuments { return false }
            case .archive: if !viewModel.showArchives { return false }
            case .other: if !viewModel.showOther { return false }
            }
            
            return true
        }
        .sorted(using: viewModel.sortOrder)
    }
    
    private var filesTable: some View {
        Table(filteredRows, selection: $viewModel.selection, sortOrder: $viewModel.sortOrder) {
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
            
            TableColumn("Type", value: \.fileType) { row in
                HStack {
                    FileTypeChip(filename: row.name, iconSize: 12)
                    Spacer()
                }
                .opacity(row.wanted ? 1.0 : 0.6)
            }
            .width(min: 70, ideal: 80)
            
            TableColumn("Size", value: \.size) { row in
                Text(row.sizeDisplay)
                    .font(.system(.caption, design: .monospaced))
                    .opacity(row.wanted ? 1.0 : 0.6)
            }
            .width(min: 80, ideal: 100)
            
            TableColumn("Downloaded", value: \.bytesCompleted) { row in
                Text(row.downloadedDisplay)
                    .font(.system(.caption, design: .monospaced))
                    .opacity(row.wanted ? 1.0 : 0.6)
            }
            .width(min: 80, ideal: 100)
            
            TableColumn("Progress", value: \.percentDone) { row in
                FileProgressView(percentDone: row.percentDone)
                    .opacity(row.wanted ? 1.0 : 0.6)
            }
            .width(min: 90, ideal: 110)
            
            TableColumn("Priority", value: \.priority) { row in
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
                Button("Select All") {
                    viewModel.selection = Set(filteredRows.map { $0.id })
                }
            } else {
                let selectedRows = filteredRows.filter { selection.contains($0.id) }
                
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
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with search and filters
            HeaderView(viewModel: viewModel)
                .padding(.horizontal)
                .padding(.vertical, 12)
            
            Divider()
            
            // Table
            filesTable
            
            // Footer with file count
            FooterView(totalCount: cachedRows.count, filteredCount: filteredRows.count)
                .padding(.horizontal)
                .padding(.vertical, 8)
        }
        .frame(minHeight: 300)
        .onAppear {
            mutableFileStats = fileStats
            recomputeRows()
        }
    }
    
    // MARK: - File Operations
    
    private func setFilesWanted(_ selectedRows: [TorrentFileRow], wanted: Bool) {
        let fileIndices = selectedRows.map { $0.fileIndex }
        
        // Snapshot previous stats for revert-on-failure
        let previousStats: [(index: Int, stats: TorrentFileStats)] = fileIndices.compactMap { idx in
            guard idx < (mutableFileStats.isEmpty ? fileStats.count : mutableFileStats.count) else { return nil }
            let current = (mutableFileStats.isEmpty ? fileStats[idx] : mutableFileStats[idx])
            return (idx, current)
        }

        FileActionExecutor.setWanted(
            torrentId: torrentId,
            fileIndices: fileIndices,
            store: store,
            wanted: wanted,
            optimisticApply: { updateLocalFileStatus(selectedRows, wanted: wanted) },
            revert: {
                for (idx, old) in previousStats {
                    if idx < mutableFileStats.count { mutableFileStats[idx] = old }
                }
                recomputeRows()
            },
            onComplete: { response in
                print("macOS set wanted status: \(response)")
            }
        )
    }
    
    private func setFilesPriority(_ selectedRows: [TorrentFileRow], priority: FilePriority) {
        let fileIndices = selectedRows.map { $0.fileIndex }
        
        // Snapshot previous stats for revert-on-failure
        let previousStats: [(index: Int, stats: TorrentFileStats)] = fileIndices.compactMap { idx in
            guard idx < (mutableFileStats.isEmpty ? fileStats.count : mutableFileStats.count) else { return nil }
            let current = (mutableFileStats.isEmpty ? fileStats[idx] : mutableFileStats[idx])
            return (idx, current)
        }

        FileActionExecutor.setPriority(
            torrentId: torrentId,
            fileIndices: fileIndices,
            store: store,
            priority: priority,
            optimisticApply: { updateLocalFilePriority(selectedRows, priority: priority) },
            revert: {
                for (idx, old) in previousStats {
                    if idx < mutableFileStats.count { mutableFileStats[idx] = old }
                }
                recomputeRows()
            },
            onComplete: { response in
                print("macOS set file priority: \(response)")
            }
        )
    }
    
    private func updateLocalFileStatus(_ selectedRows: [TorrentFileRow], wanted: Bool) {
        // Update local data optimistically by mutating stats
        for row in selectedRows {
            let idx = row.fileIndex
            guard idx < (mutableFileStats.isEmpty ? fileStats.count : mutableFileStats.count) else { continue }
            let current = mutableFileStats.isEmpty ? fileStats[idx] : mutableFileStats[idx]
            let updated = TorrentFileStats(bytesCompleted: current.bytesCompleted, wanted: wanted, priority: current.priority)
            if mutableFileStats.isEmpty {
                mutableFileStats = fileStats
            }
            mutableFileStats[idx] = updated
        }
        recomputeRows()
    }
    
    private func updateLocalFilePriority(_ selectedRows: [TorrentFileRow], priority: FilePriority) {
        // Update local data optimistically by mutating stats
        for row in selectedRows {
            let idx = row.fileIndex
            guard idx < (mutableFileStats.isEmpty ? fileStats.count : mutableFileStats.count) else { continue }
            let current = mutableFileStats.isEmpty ? fileStats[idx] : mutableFileStats[idx]
            let updated = TorrentFileStats(bytesCompleted: current.bytesCompleted, wanted: current.wanted, priority: priority.rawValue)
            if mutableFileStats.isEmpty {
                mutableFileStats = fileStats
            }
            mutableFileStats[idx] = updated
        }
        recomputeRows()
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
                        Toggle(FileTypeCategory.video.title, isOn: $viewModel.showVideos)
                        Toggle(FileTypeCategory.audio.title, isOn: $viewModel.showAudio)
                        Toggle(FileTypeCategory.image.title, isOn: $viewModel.showImages)
                        Toggle(FileTypeCategory.document.title, isOn: $viewModel.showDocuments)
                        Toggle(FileTypeCategory.archive.title, isOn: $viewModel.showArchives)
                        Toggle(FileTypeCategory.other.title, isOn: $viewModel.showOther)
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
