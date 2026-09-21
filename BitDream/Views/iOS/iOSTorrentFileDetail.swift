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
    @Environment(\.hapticFeedback) private var hapticFeedback

    let files: [TorrentFile]
    let fileStats: [TorrentFileStats]
    let torrentId: Int
    let store: TransmissionStore
    let onCommittedFileStatsMutation: @MainActor @Sendable ([Int], TorrentDetailFileStatsMutation) -> Void

    @Bindable private var state: iOSTorrentFileState

    init(
        files: [TorrentFile],
        fileStats: [TorrentFileStats],
        torrentId: Int,
        store: TransmissionStore,
        state: iOSTorrentFileState,
        onCommittedFileStatsMutation: @escaping @MainActor @Sendable ([Int], TorrentDetailFileStatsMutation) -> Void = { _, _ in }
    ) {
        self.files = files
        self.fileStats = fileStats
        self.torrentId = torrentId
        self.store = store
        self.state = state
        self.onCommittedFileStatsMutation = onCommittedFileStatsMutation
    }

    private var isEditing: Bool { state.editMode.isEditing }

    private var fileRows: [TorrentFileRow] {
        let processedFiles = processFilesForDisplay(files, stats: state.mutableFileStats.isEmpty ? fileStats : state.mutableFileStats)
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
        !state.showWantedFiles || !state.showSkippedFiles ||
        !state.showCompleteFiles || !state.showIncompleteFiles ||
        !state.showVideos || !state.showAudio || !state.showImages ||
        !state.showDocuments || !state.showArchives || !state.showOther
    }

    private var filteredAndSortedFileRows: [TorrentFileRow] {
        let filtered = fileRows.filter { row in
            if !state.searchText.isEmpty {
                let searchLower = state.searchText.lowercased()
                if !row.name.lowercased().contains(searchLower) {
                    return false
                }
            }

            if row.wanted && !state.showWantedFiles { return false }
            if !row.wanted && !state.showSkippedFiles { return false }

            let isComplete = row.percentDone >= 1.0
            if isComplete && !state.showCompleteFiles { return false }
            if !isComplete && !state.showIncompleteFiles { return false }

            let fileType = fileTypeCategory(row.name)
            switch fileType {
            case .video: if !state.showVideos { return false }
            case .audio: if !state.showAudio { return false }
            case .image: if !state.showImages { return false }
            case .document: if !state.showDocuments { return false }
            case .archive: if !state.showArchives { return false }
            case .executable: if !state.showOther { return false }
            case .other: if !state.showOther { return false }
            }

            return true
        }
        return sortFiles(filtered, by: state.sortProperty, order: state.sortOrder)
    }

    var body: some View {
        List(selection: isEditing ? $state.selectedFileIds : .constant(Set<String>())) {
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
        .navigationTitle("Files")
        .safeAreaBar(edge: .bottom) {
            if isEditing {
                BulkActionToolbar(
                    selectedCount: state.selectedFileIds.count,
                    selectedFileIds: $state.selectedFileIds,
                    allFileRows: filteredAndSortedFileRows,
                    setBulkWanted: setBulkWanted,
                    setBulkPriority: setBulkPriority
                )
            }
        }
        .searchable(text: $state.searchText, prompt: "Search files")
        .toolbar {
            FileActionsToolbar(
                hasActiveFilters: hasActiveFilters,
                sortProperty: $state.sortProperty,
                sortOrder: $state.sortOrder,
                showFilterSheet: $state.showFilterSheet
            )
        }
        .environment(\.editMode, $state.editMode)
        .sheet(isPresented: $state.showFilterSheet) {
            FilterSheet(
                showWantedFiles: $state.showWantedFiles,
                showSkippedFiles: $state.showSkippedFiles,
                showCompleteFiles: $state.showCompleteFiles,
                showIncompleteFiles: $state.showIncompleteFiles,
                showVideos: $state.showVideos,
                showAudio: $state.showAudio,
                showImages: $state.showImages,
                showDocuments: $state.showDocuments,
                showArchives: $state.showArchives,
                showOther: $state.showOther
            )
        }
        .onAppear {
            state.mutableFileStats = fileStats
        }
        .onChange(of: fileStats) { _, newValue in
            state.mutableFileStats = newValue
        }
        .onChange(of: fileSelectionState) {
            hapticFeedback.play(.selectionChanged)
        }
        .onChange(of: state.editMode) {
            if !state.editMode.isEditing {
                state.selectedFileIds.removeAll()
            }
        }
        .transmissionErrorAlert(isPresented: $state.showingError, message: state.errorMessage)
    }
}

private extension iOSTorrentFileDetail {
    var fileSelectionState: FileSelectionHapticState {
        FileSelectionHapticState(isEditing: isEditing, selectedFileIds: state.selectedFileIds)
    }

    func setFileWanted(_ row: TorrentFileRow, wanted: Bool) {
        setBulkWanted(fileIndices: [row.fileIndex], wanted: wanted)
    }

    func setFilePriority(_ row: TorrentFileRow, priority: FilePriority) {
        setBulkPriority(fileIndices: [row.fileIndex], priority: priority)
    }

    func setBulkWanted(fileIndices: [Int], wanted: Bool) {
        hapticFeedback.play(.actionTriggered)
        let previousStats = snapshotFileStats(for: fileIndices, mutableStats: state.mutableFileStats, fallbackStats: fileStats)
        state.mutableFileStats = applyLocalFileWanted(fileIndices: fileIndices, wanted: wanted, mutableStats: state.mutableFileStats, fallbackStats: fileStats)

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
                hapticFeedback.play(.selectionChanged)
            },
            onError: { message in
                state.mutableFileStats = applyFileStatsRevert(previousStats, into: state.mutableFileStats, fallback: fileStats)
                hapticFeedback.play(.operationFailed)
                state.errorMessage = message
                state.showingError = true
            }
        )
    }

    func setBulkPriority(fileIndices: [Int], priority: FilePriority) {
        hapticFeedback.play(.actionTriggered)
        let previousStats = snapshotFileStats(for: fileIndices, mutableStats: state.mutableFileStats, fallbackStats: fileStats)
        state.mutableFileStats = applyLocalFilePriority(fileIndices: fileIndices, priority: priority, mutableStats: state.mutableFileStats, fallbackStats: fileStats)

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
                hapticFeedback.play(.selectionChanged)
            },
            onError: { message in
                state.mutableFileStats = applyFileStatsRevert(previousStats, into: state.mutableFileStats, fallback: fileStats)
                hapticFeedback.play(.operationFailed)
                state.errorMessage = message
                state.showingError = true
            }
        )
    }
}

private struct FileSelectionHapticState: Equatable {
    let isEditing: Bool
    let selectedFileIds: Set<String>
}

#endif

#if os(iOS) && DEBUG
#Preview("iOS Torrent Files") {
    @Previewable @State var state = iOSTorrentFileState()
    PreviewContainer { environment in
        NavigationStack {
            iOSTorrentFileDetail(
                files: PreviewFixtures.files,
                fileStats: PreviewFixtures.fileStats,
                torrentId: PreviewFixtures.torrents[0].id,
                store: environment.store,
                state: state
            )
        }
    }
}
#endif
