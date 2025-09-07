import Foundation
import SwiftUI
import CoreData

#if os(iOS)

// MARK: - iOS File Sort Properties

enum FileSortProperty: String, CaseIterable {
    case name = "Name"
    case size = "Size"
    case progress = "Progress"
    case type = "Type"
    case priority = "Priority"
}

/// Sort files using the same pattern as torrents
func sortFiles(_ files: [TorrentFileRow], by property: FileSortProperty, order: SortOrder) -> [TorrentFileRow] {
    switch property {
    case .name:
        return order == .ascending ? 
            files.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending } :
            files.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedDescending }
    case .size:
        return order == .ascending ? 
            files.sorted { $0.size < $1.size } :
            files.sorted { $0.size > $1.size }
    case .progress:
        return order == .ascending ?
            files.sorted { $0.percentDone < $1.percentDone } :
            files.sorted { $0.percentDone > $1.percentDone }
    case .type:
        return order == .ascending ?
            files.sorted { $0.fileType.localizedCaseInsensitiveCompare($1.fileType) == .orderedAscending } :
            files.sorted { $0.fileType.localizedCaseInsensitiveCompare($1.fileType) == .orderedDescending }
    case .priority:
        return order == .ascending ?
            files.sorted { $0.priority < $1.priority } :
            files.sorted { $0.priority > $1.priority }
    }
}

struct iOSTorrentFileDetail: View {
    let files: [TorrentFile]
    let fileStats: [TorrentFileStats]
    let torrentId: Int
    let store: Store
    
    @State private var mutableFileStats: [TorrentFileStats] = []
    @State private var searchText = ""
    @State private var sortProperty: FileSortProperty = .name
    @State private var sortOrder: SortOrder = .ascending
    
    // Filter toggles - same as macOS
    @State private var showWantedFiles = true
    @State private var showSkippedFiles = true
    @State private var showCompleteFiles = true
    @State private var showIncompleteFiles = true
    @State private var showVideos = true
    @State private var showAudio = true
    @State private var showImages = true
    @State private var showDocuments = true
    @State private var showArchives = true
    @State private var showOther = true
    @State private var showFilterSheet = false
    
    // Multi-select state
    @State private var isEditing = false
    @State private var selectedFileIds: Set<String> = []
    
    private var fileRows: [TorrentFileRow] {
        let processedFiles = processFilesForDisplay(files, stats: mutableFileStats.isEmpty ? fileStats : mutableFileStats)
        return processedFiles.map { processed in
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
    
    private var hasActiveFilters: Bool {
        !showWantedFiles || !showSkippedFiles ||
        !showCompleteFiles || !showIncompleteFiles ||
        !showVideos || !showAudio || !showImages ||
        !showDocuments || !showArchives || !showOther
    }
    
    private var filteredAndSortedFileRows: [TorrentFileRow] {
        let filtered = fileRows.filter { row in
            // Search filter
            if !searchText.isEmpty {
                let searchLower = searchText.lowercased()
                if !row.name.lowercased().contains(searchLower) {
                    return false
                }
            }
            
            // Wanted/Skip filter - same logic as macOS
            if row.wanted && !showWantedFiles { return false }
            if !row.wanted && !showSkippedFiles { return false }
            
            // Completion filter - same logic as macOS
            let isComplete = row.percentDone >= 1.0
            if isComplete && !showCompleteFiles { return false }
            if !isComplete && !showIncompleteFiles { return false }
            
            // File type filter - same logic as macOS
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
        return sortFiles(filtered, by: sortProperty, order: sortOrder)
    }
    
    @Environment(\.editMode) private var editMode
    
    var body: some View {
        List(selection: isEditing ? $selectedFileIds : .constant(Set<String>())) {
            ForEach(filteredAndSortedFileRows, id: \.id) { row in
                VStack {
                        HStack {
                            Text(row.displayName)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            
                            Spacer()
                        }
                    .padding(.bottom, 4)
                    
                    ProgressView(value: row.percentDone)
                        .progressViewStyle(.linear)
                        .tint(row.percentDone >= 1.0 ? .green : .blue)
                    
                    HStack {
                        Text("\(byteCountFormatter.string(fromByteCount: row.bytesCompleted)) / \(byteCountFormatter.string(fromByteCount: row.size)) (\(String(format: "%.1f%%", row.percentDone * 100)))")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        if row.wanted {
                            let priority = FilePriority(rawValue: row.priority) ?? .normal
                            PriorityBadge(priority: priority)
                        } else {
                            StatusBadge(wanted: false)
                        }
                        
                        FileTypeChip(filename: row.name)
                    }
                }
                .opacity(row.wanted ? 1.0 : 0.5)
                .swipeActions(edge: .trailing) {
                    // Priority menu (flag) - appears on the right
                    Menu {
                        Section("Priority") {
                            Button("High Priority") {
                                setFilePriority(row, priority: .high)
                            }
                            
                            Button("Normal Priority") {
                                setFilePriority(row, priority: .normal)
                            }
                            
                            Button("Low Priority") {
                                setFilePriority(row, priority: .low)
                            }
                        }
                    } label: {
                        Image(systemName: "flag")
                    }
                    .tint(.orange)
                    
                    // All actions menu (three dots) - appears on the left
                    Menu {
                        Section("Status") {
                            Button("Download") {
                                setFileWanted(row, wanted: true)
                            }
                            
                            Button("Don't Download") {
                                setFileWanted(row, wanted: false)
                            }
                        }
                        
                        Section("Priority") {
                            Button("High Priority") {
                                setFilePriority(row, priority: .high)
                            }
                            
                            Button("Normal Priority") {
                                setFilePriority(row, priority: .normal)
                            }
                            
                            Button("Low Priority") {
                                setFilePriority(row, priority: .low)
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                .contextMenu {
                    Section("Status") {
                        Button("Download") {
                            setFileWanted(row, wanted: true)
                        }
                        
                        Button("Don't Download") {
                            setFileWanted(row, wanted: false)
                        }
                    }
                    
                    Section("Priority") {
                        Button("High Priority") {
                            setFilePriority(row, priority: .high)
                        }
                        
                        Button("Normal Priority") {
                            setFilePriority(row, priority: .normal)
                        }
                        
                        Button("Low Priority") {
                            setFilePriority(row, priority: .low)
                        }
                    }
                }
            }
            
            // File count footer as a List section
            Section {
                EmptyView()
            } footer: {
                HStack {
                    if filteredAndSortedFileRows.count < fileRows.count {
                        Text("Showing \(filteredAndSortedFileRows.count) of \(fileRows.count) files")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("\(fileRows.count) files")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .environment(\.editMode, .constant(isEditing ? .active : .inactive))
        .navigationTitle("Files")
        .safeAreaInset(edge: .bottom) {
            if isEditing {
                BulkActionToolbar(
                    selectedCount: selectedFileIds.count,
                    selectedFileIds: $selectedFileIds,
                    allFileRows: filteredAndSortedFileRows,
                    torrentId: torrentId,
                    store: store,
                    updateFileStatus: updateLocalFileStatus,
                    updateFilePriority: updateLocalFilePriority,
                    revertData: revertToOriginalData
                )
            }
        }
        .searchable(text: $searchText, prompt: "Search files")
        .safeAreaInset(edge: .top) {
            FileActionButtonsView(
                hasActiveFilters: hasActiveFilters,
                sortProperty: $sortProperty,
                sortOrder: $sortOrder,
                isEditing: $isEditing,
                selectedFileIds: $selectedFileIds,
                showFilterSheet: $showFilterSheet
            )
        }
        .sheet(isPresented: $showFilterSheet) {
            FilterSheet(
                showWantedFiles: $showWantedFiles,
                showSkippedFiles: $showSkippedFiles,
                showCompleteFiles: $showCompleteFiles,
                showIncompleteFiles: $showIncompleteFiles,
                showVideos: $showVideos,
                showAudio: $showAudio,
                showImages: $showImages,
                showDocuments: $showDocuments,
                showArchives: $showArchives,
                showOther: $showOther
            )
        }
        .onAppear {
            mutableFileStats = fileStats
        }
    }
    
    // MARK: - File Operations
    
    private func setFileWanted(_ row: TorrentFileRow, wanted: Bool) {
        FileActionExecutor.setWanted(
            torrentId: torrentId,
            fileIndices: [row.fileIndex],
            store: store,
            wanted: wanted,
            optimisticApply: { updateLocalFileStatus(fileIndex: row.fileIndex, wanted: wanted) },
            revert: { revertToOriginalData() },
            onComplete: { response in
                print("Set wanted status: \(response)")
            }
        )
    }
    
    private func setFilePriority(_ row: TorrentFileRow, priority: FilePriority) {
        FileActionExecutor.setPriority(
            torrentId: torrentId,
            fileIndices: [row.fileIndex],
            store: store,
            priority: priority,
            optimisticApply: { updateLocalFilePriority(fileIndex: row.fileIndex, priority: priority) },
            revert: { revertToOriginalData() },
            onComplete: { response in
                print("Set priority: \(response)")
            }
        )
    }
    
    // MARK: - Optimistic Updates
    
    private func updateLocalFileStatus(fileIndex: Int, wanted: Bool) {
        guard fileIndex < mutableFileStats.count else { return }
        mutableFileStats[fileIndex] = TorrentFileStats(
            bytesCompleted: mutableFileStats[fileIndex].bytesCompleted,
            wanted: wanted,
            priority: mutableFileStats[fileIndex].priority
        )
    }
    
    private func updateLocalFilePriority(fileIndex: Int, priority: FilePriority) {
        guard fileIndex < mutableFileStats.count else { return }
        mutableFileStats[fileIndex] = TorrentFileStats(
            bytesCompleted: mutableFileStats[fileIndex].bytesCompleted,
            wanted: mutableFileStats[fileIndex].wanted,
            priority: priority.rawValue
        )
    }
    
    private func revertToOriginalData() {
        mutableFileStats = fileStats
    }
}

// MARK: - Bulk Action Toolbar

struct BulkActionToolbar: View {
    let selectedCount: Int
    @Binding var selectedFileIds: Set<String>
    let allFileRows: [TorrentFileRow]
    let torrentId: Int
    let store: Store
    let updateFileStatus: (Int, Bool) -> Void
    let updateFilePriority: (Int, FilePriority) -> Void
    let revertData: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            Divider()
            
            HStack(spacing: 16) {
                // Selection count
                Text("\(selectedCount) selected")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // Select All/Deselect All - selection controls, not actions
                Button(selectedCount == allFileRows.count ? "Deselect All" : "Select All") {
                    if selectedCount == allFileRows.count {
                        selectedFileIds.removeAll()
                    } else {
                        selectedFileIds = Set(allFileRows.map { $0.id })
                    }
                }
                .font(.subheadline)
                
                // Actions menu - EXACTLY same as context menu
                Menu {
                    Section("Status") {
                        Button("Download") {
                            setBulkWanted(true)
                        }
                        
                        Button("Don't Download") {
                            setBulkWanted(false)
                        }
                    }
                    
                    Section("Priority") {
                        Button("High Priority") {
                            setBulkPriority(.high)
                        }
                        
                        Button("Normal Priority") {
                            setBulkPriority(.normal)
                        }
                        
                        Button("Low Priority") {
                            setBulkPriority(.low)
                        }
                    }
                } label: {
                    Text("Actions")
                        .font(.subheadline)
                }
                .disabled(selectedCount == 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.background)
        }
    }
    
    private func setBulkPriority(_ priority: FilePriority) {
        let selectedRows = allFileRows.filter { selectedFileIds.contains($0.id) }
        let fileIndices = selectedRows.map { $0.fileIndex }
        
        // Optimistic updates for all selected files
        for fileIndex in fileIndices {
            updateFilePriority(fileIndex, priority)
        }
        
        let info = makeConfig(store: store)
        setFilePriority(
            torrentId: torrentId,
            fileIndices: fileIndices,
            priority: priority,
            info: info
        ) { response in
            print("Bulk priority set: \(response)")
            if response != .success {
                // Revert on failure
                revertData()
            }
        }
    }
    
    private func setBulkWanted(_ wanted: Bool) {
        let selectedRows = allFileRows.filter { selectedFileIds.contains($0.id) }
        let fileIndices = selectedRows.map { $0.fileIndex }
        
        // Optimistic updates for all selected files
        for fileIndex in fileIndices {
            updateFileStatus(fileIndex, wanted)
        }
        
        let info = makeConfig(store: store)
        setFileWantedStatus(
            torrentId: torrentId,
            fileIndices: fileIndices,
            wanted: wanted,
            info: info
        ) { response in
            print("Bulk wanted status set: \(response)")
            if response != .success {
                // Revert on failure
                revertData()
            }
        }
    }
}

// MARK: - File Action Buttons View

struct FileActionButtonsView: View {
    let hasActiveFilters: Bool
    @Binding var sortProperty: FileSortProperty
    @Binding var sortOrder: SortOrder
    @Binding var isEditing: Bool
    @Binding var selectedFileIds: Set<String>
    @Binding var showFilterSheet: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // Filter button
            Button {
                showFilterSheet = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    Text("Filter")
                }
                .font(.subheadline)
                .foregroundColor(hasActiveFilters ? .white : .accentColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(hasActiveFilters ? Color.accentColor : Color.accentColor.opacity(0.1))
                .cornerRadius(16)
            }
            
            // Sort menu
            Menu {
                // Sort properties
                ForEach(FileSortProperty.allCases, id: \.self) { property in
                    Button {
                        sortProperty = property
                    } label: {
                        HStack {
                            Text(property.rawValue)
                            Spacer()
                            if sortProperty == property {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
                
                Divider()
                
                // Sort order
                Button {
                    sortOrder = .ascending
                } label: {
                    HStack {
                        Text("Ascending")
                        Spacer()
                        if sortOrder == .ascending {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                
                Button {
                    sortOrder = .descending
                } label: {
                    HStack {
                        Text("Descending")
                        Spacer()
                        if sortOrder == .descending {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.arrow.down")
                    Text("Sort")
                }
                .font(.subheadline)
                .foregroundColor(.accentColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(16)
            }
            
            Spacer()
            
            // Edit button - separated on the right
            Button {
                withAnimation {
                    isEditing.toggle()
                    if !isEditing {
                        selectedFileIds.removeAll()
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isEditing ? "checkmark" : "pencil")
                    Text(isEditing ? "Done" : "Edit")
                }
                .font(.subheadline)
                .foregroundColor(isEditing ? .white : .accentColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isEditing ? Color.accentColor : Color.accentColor.opacity(0.1))
                .cornerRadius(16)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.background)
    }
}

// MARK: - Filter Sheet

struct FilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    @Binding var showWantedFiles: Bool
    @Binding var showSkippedFiles: Bool
    @Binding var showCompleteFiles: Bool
    @Binding var showIncompleteFiles: Bool
    @Binding var showVideos: Bool
    @Binding var showAudio: Bool
    @Binding var showImages: Bool
    @Binding var showDocuments: Bool
    @Binding var showArchives: Bool
    @Binding var showOther: Bool
    
    var body: some View {
        NavigationView {
            List {
                Section("Status") {
                    Toggle(FileStatus.wanted, isOn: $showWantedFiles)
                    Toggle(FileStatus.skip, isOn: $showSkippedFiles)
                }
                
                Section("Progress") {
                    Toggle(FileCompletion.complete, isOn: $showCompleteFiles)
                    Toggle(FileCompletion.incomplete, isOn: $showIncompleteFiles)
                }
                
                Section("File Types") {
                    Toggle(FileTypeCategory.video.title, isOn: $showVideos)
                    Toggle(FileTypeCategory.audio.title, isOn: $showAudio)
                    Toggle(FileTypeCategory.image.title, isOn: $showImages)
                    Toggle(FileTypeCategory.document.title, isOn: $showDocuments)
                    Toggle(FileTypeCategory.archive.title, isOn: $showArchives)
                    Toggle(FileTypeCategory.other.title, isOn: $showOther)
                }
                
                Section {
                    Button("Reset All Filters") {
                        showWantedFiles = true
                        showSkippedFiles = true
                        showCompleteFiles = true
                        showIncompleteFiles = true
                        showVideos = true
                        showAudio = true
                        showImages = true
                        showDocuments = true
                        showArchives = true
                        showOther = true
                    }
                    .foregroundColor(.accentColor)
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("iOS Torrent Files") {
    NavigationView {
        iOSTorrentFileDetail(
            files: TorrentFilePreviewData.sampleFiles,
            fileStats: TorrentFilePreviewData.sampleFileStats,
            torrentId: 1,
            store: Store()
        )
    }
}

#else
// Empty struct for macOS to reference - this won't be compiled on macOS but provides the type
struct iOSTorrentFileDetail: View {
    let files: [TorrentFile]
    let fileStats: [TorrentFileStats]
    let torrentId: Int
    let store: Store
    
    var body: some View {
        EmptyView()
    }
}
#endif 