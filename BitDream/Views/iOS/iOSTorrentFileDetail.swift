import Foundation
import SwiftUI

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
    let store: TransmissionStore
    let onCommittedFileStatsMutation: @MainActor @Sendable ([Int], TorrentDetailFileStatsMutation) -> Void

    init(
        files: [TorrentFile],
        fileStats: [TorrentFileStats],
        torrentId: Int,
        store: TransmissionStore,
        onCommittedFileStatsMutation: @escaping @MainActor @Sendable ([Int], TorrentDetailFileStatsMutation) -> Void = { _, _ in }
    ) {
        self.files = files
        self.fileStats = fileStats
        self.torrentId = torrentId
        self.store = store
        self.onCommittedFileStatsMutation = onCommittedFileStatsMutation
    }

    @State private var mutableFileStats: [TorrentFileStats] = []
    @State private var searchText = ""
    @State private var sortProperty: FileSortProperty = .name
    @State private var sortOrder: SortOrder = .ascending

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

    @State private var isEditing = false
    @State private var selectedFileIds: Set<String> = []
    @State private var showingError = false
    @State private var errorMessage = ""

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
            if !searchText.isEmpty {
                let searchLower = searchText.lowercased()
                if !row.name.lowercased().contains(searchLower) {
                    return false
                }
            }

            if row.wanted && !showWantedFiles { return false }
            if !row.wanted && !showSkippedFiles { return false }

            let isComplete = row.percentDone >= 1.0
            if isComplete && !showCompleteFiles { return false }
            if !isComplete && !showIncompleteFiles { return false }

            let fileType = fileTypeCategory(row.name)
            switch fileType {
            case .video: if !showVideos { return false }
            case .audio: if !showAudio { return false }
            case .image: if !showImages { return false }
            case .document: if !showDocuments { return false }
            case .archive: if !showArchives { return false }
            case .executable: if !showOther { return false }
            case .other: if !showOther { return false }
            }

            return true
        }
        return sortFiles(filtered, by: sortProperty, order: sortOrder)
    }

    var body: some View {
        List(selection: isEditing ? $selectedFileIds : .constant(Set<String>())) {
            ForEach(filteredAndSortedFileRows, id: \.id) { row in
                iOSTorrentFileRow(
                    row: row,
                    setFileWanted: setFileWanted,
                    setFilePriority: setFilePriority
                )
            }

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
                    setBulkWanted: setBulkWanted,
                    setBulkPriority: setBulkPriority
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
        .onChange(of: fileStats) { _, newValue in
            mutableFileStats = newValue
        }
        .transmissionErrorAlert(isPresented: $showingError, message: errorMessage)
    }
}

private extension iOSTorrentFileDetail {
    func setFileWanted(_ row: TorrentFileRow, wanted: Bool) {
        setBulkWanted(fileIndices: [row.fileIndex], wanted: wanted)
    }

    func setFilePriority(_ row: TorrentFileRow, priority: FilePriority) {
        setBulkPriority(fileIndices: [row.fileIndex], priority: priority)
    }

    func setBulkWanted(fileIndices: [Int], wanted: Bool) {
        let previousStats = snapshotFileStats(for: fileIndices, mutableStats: mutableFileStats, fallbackStats: fileStats)
        mutableFileStats = applyLocalFileWanted(fileIndices: fileIndices, wanted: wanted, mutableStats: mutableFileStats, fallbackStats: fileStats)

        performTransmissionAction(
            operation: {
                try await store.setFileWantedStatus(
                    torrentId: torrentId,
                    fileIndices: fileIndices,
                    wanted: wanted
                )
            },
            onSuccess: {
                onCommittedFileStatsMutation(fileIndices, .wanted(wanted))
            },
            onError: { message in
                mutableFileStats = applyFileStatsRevert(previousStats, into: mutableFileStats, fallback: fileStats)
                errorMessage = message
                showingError = true
            }
        )
    }

    func setBulkPriority(fileIndices: [Int], priority: FilePriority) {
        let previousStats = snapshotFileStats(for: fileIndices, mutableStats: mutableFileStats, fallbackStats: fileStats)
        mutableFileStats = applyLocalFilePriority(fileIndices: fileIndices, priority: priority, mutableStats: mutableFileStats, fallbackStats: fileStats)

        performTransmissionAction(
            operation: {
                try await store.setFilePriority(
                    torrentId: torrentId,
                    fileIndices: fileIndices,
                    priority: priority
                )
            },
            onSuccess: {
                onCommittedFileStatsMutation(fileIndices, .priority(priority))
            },
            onError: { message in
                mutableFileStats = applyFileStatsRevert(previousStats, into: mutableFileStats, fallback: fileStats)
                errorMessage = message
                showingError = true
            }
        )
    }
}

#endif
