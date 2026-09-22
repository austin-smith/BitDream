import Foundation
import SwiftUI

#if os(iOS)

struct BulkActionToolbar: View {
    let selectedCount: Int
    @Binding var selectedFileIds: Set<String>
    let allFileRows: [TorrentFileRow]
    let setBulkWanted: ([Int], Bool) -> Void
    let setBulkPriority: ([Int], FilePriority) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                selectionSummary
                    .fixedSize(horizontal: true, vertical: false)
                Spacer()
                selectAllButton
                    .fixedSize(horizontal: true, vertical: false)
                actionsMenu
                    .fixedSize(horizontal: true, vertical: false)
            }

            VStack(alignment: .leading, spacing: 12) {
                selectionSummary
                selectAllButton
                actionsMenu
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.subheadline)
        .padding(.horizontal)
        .padding(.vertical, 12)
    }

    private var selectionSummary: some View {
        Text("\(selectedCount) selected")
            .foregroundStyle(.secondary)
    }

    private var selectAllButton: some View {
        Button(selectedCount == allFileRows.count ? "Deselect All" : "Select All") {
            if selectedCount == allFileRows.count {
                selectedFileIds.removeAll()
            } else {
                selectedFileIds = Set(allFileRows.map { $0.id })
            }
        }
    }

    private var actionsMenu: some View {
        Menu {
            Section("Status") {
                Button("Download", systemImage: "arrow.down.circle") {
                    setBulkWanted(true)
                }

                Button("Don't Download", systemImage: "xmark.circle") {
                    setBulkWanted(false)
                }
            }

            Section("Priority") {
                Button("High Priority", systemImage: "arrow.up") {
                    setBulkPriority(.high)
                }

                Button("Normal Priority", systemImage: "minus") {
                    setBulkPriority(.normal)
                }

                Button("Low Priority", systemImage: "arrow.down") {
                    setBulkPriority(.low)
                }
            }
        } label: {
            Label("Actions", systemImage: "checklist")
        }
        .iOSHapticControlActivation()
        .disabled(selectedCount == 0)
    }

    private func setBulkPriority(_ priority: FilePriority) {
        let fileIndices = allFileRows
            .filter { selectedFileIds.contains($0.id) }
            .map(\.fileIndex)
        setBulkPriority(fileIndices, priority)
    }

    private func setBulkWanted(_ wanted: Bool) {
        let fileIndices = allFileRows
            .filter { selectedFileIds.contains($0.id) }
            .map(\.fileIndex)
        setBulkWanted(fileIndices, wanted)
    }
}

struct FileActionsToolbar: ToolbarContent {
    @Environment(\.hapticFeedback) private var hapticFeedback

    let hasActiveFilters: Bool
    @Binding var sortProperty: FileSortProperty
    @Binding var sortOrder: SortOrder
    @Binding var showFilterSheet: Bool

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                hapticFeedback.play(.actionTriggered)
                showFilterSheet = true
            } label: {
                Label("Filter", systemImage: "line.3.horizontal.decrease")
            }
            .if(hasActiveFilters) { button in
                button.buttonStyle(.borderedProminent)
            }
            .accessibilityValue(hasActiveFilters ? "Filters active" : "All files")
        }

        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("Sort By", selection: $sortProperty) {
                    ForEach(FileSortProperty.allCases, id: \.self) { property in
                        Text(property.rawValue).tag(property)
                    }
                }

                Picker("Order", selection: $sortOrder) {
                    Text("Ascending").tag(SortOrder.ascending)
                    Text("Descending").tag(SortOrder.descending)
                }
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }
            .onChange(of: sortProperty) {
                hapticFeedback.play(.selectionChanged)
            }
            .onChange(of: sortOrder) {
                hapticFeedback.play(.selectionChanged)
            }
        }

        ToolbarItem(placement: .topBarTrailing) {
            EditButton()
        }
    }
}

struct FilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.hapticFeedback) private var hapticFeedback

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
        NavigationStack {
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
                    Toggle(ContentTypeCategory.video.title, isOn: $showVideos)
                    Toggle(ContentTypeCategory.audio.title, isOn: $showAudio)
                    Toggle(ContentTypeCategory.image.title, isOn: $showImages)
                    Toggle(ContentTypeCategory.document.title, isOn: $showDocuments)
                    Toggle(ContentTypeCategory.archive.title, isOn: $showArchives)
                    Toggle(ContentTypeCategory.other.title, isOn: $showOther)
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
                    .disabled(!hasActiveFilters)
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") {
                        hapticFeedback.play(.actionTriggered)
                        dismiss()
                    }
                }
            }
        }
        .onChange(of: filterSelection) {
            hapticFeedback.play(.selectionChanged)
        }
    }

    private var filterSelection: FileFilterSelection {
        FileFilterSelection(
            showsWanted: showWantedFiles,
            showsSkipped: showSkippedFiles,
            showsComplete: showCompleteFiles,
            showsIncomplete: showIncompleteFiles,
            showsVideos: showVideos,
            showsAudio: showAudio,
            showsImages: showImages,
            showsDocuments: showDocuments,
            showsArchives: showArchives,
            showsOther: showOther
        )
    }

    private var hasActiveFilters: Bool {
        filterSelection != .showAll
    }
}

private struct FileFilterSelection: Equatable {
    let showsWanted: Bool
    let showsSkipped: Bool
    let showsComplete: Bool
    let showsIncomplete: Bool
    let showsVideos: Bool
    let showsAudio: Bool
    let showsImages: Bool
    let showsDocuments: Bool
    let showsArchives: Bool
    let showsOther: Bool

    static let showAll = Self(
        showsWanted: true,
        showsSkipped: true,
        showsComplete: true,
        showsIncomplete: true,
        showsVideos: true,
        showsAudio: true,
        showsImages: true,
        showsDocuments: true,
        showsArchives: true,
        showsOther: true
    )
}

#if DEBUG
#Preview("Files at Accessibility Size") {
    @Previewable @State var state = iOSTorrentFileState()
    PreviewContainer { environment in
        NavigationStack {
            iOSTorrentFileDetail(
                files: PreviewFixtures.files,
                fileStats: PreviewFixtures.fileStats,
                torrentId: 1,
                store: environment.store,
                state: state
            )
        }
        .dynamicTypeSize(.accessibility3)
    }
}

#Preview("File Selection at Accessibility Size", traits: .fixedLayout(width: 320, height: 500)) {
    @Previewable @State var selectedFileIds: Set<String> = []

    List {
        Text("File selection")
    }
    .safeAreaBar(edge: .bottom) {
        BulkActionToolbar(
            selectedCount: selectedFileIds.count,
            selectedFileIds: $selectedFileIds,
            allFileRows: [],
            setBulkWanted: { _, _ in },
            setBulkPriority: { _, _ in }
        )
    }
    .dynamicTypeSize(.accessibility3)
}
#endif

#endif
