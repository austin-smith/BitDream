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
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: 16) {
                Text("\(selectedCount) selected")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Spacer()

                Button(selectedCount == allFileRows.count ? "Deselect All" : "Select All") {
                    if selectedCount == allFileRows.count {
                        selectedFileIds.removeAll()
                    } else {
                        selectedFileIds = Set(allFileRows.map { $0.id })
                    }
                }
                .font(.subheadline)

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

struct FileActionButtonsView: View {
    let hasActiveFilters: Bool
    @Binding var sortProperty: FileSortProperty
    @Binding var sortOrder: SortOrder
    @Binding var isEditing: Bool
    @Binding var selectedFileIds: Set<String>
    @Binding var showFilterSheet: Bool

    var body: some View {
        HStack(spacing: 12) {
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

            Menu {
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

#Preview("iOS Torrent Files") {
    NavigationView {
        iOSTorrentFileDetail(
            files: TorrentFilePreviewData.sampleFiles,
            fileStats: TorrentFilePreviewData.sampleFileStats,
            torrentId: 1,
            store: TransmissionStore()
        )
    }
}

#endif
