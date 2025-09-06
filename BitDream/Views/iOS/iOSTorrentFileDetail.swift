import Foundation
import SwiftUI
import CoreData

#if os(iOS)
struct iOSTorrentFileDetail: View {
    let files: [TorrentFile]
    let fileStats: [TorrentFileStats]
    let torrentId: Int
    let store: Store
    
    private var fileRows: [TorrentFileRow] {
        let processedFiles = processFilesForDisplay(files, stats: fileStats)
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
    
    var body: some View {
        List {
            ForEach(fileRows, id: \.id) { row in
                VStack {
                    HStack {
                        Text(row.displayName)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        
                        Spacer()
                        
                        // File type chip
                        FileTypeChip(filename: row.name)
                    }
                    .padding(.bottom, 4)
                    
                    FileProgressView(
                        percentDone: row.percentDone,
                        showDetailedText: true,
                        bytesCompleted: row.bytesCompleted,
                        totalSize: row.size
                    )
                    
                    HStack {
                        Text("Priority:")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                        
                        if row.wanted {
                            let priority = FilePriority(rawValue: row.priority) ?? .normal
                            PriorityBadge(priority: priority)
                        } else {
                            StatusBadge(wanted: false)
                        }
                        
                        Spacer()
                    }
                }
                .listRowInsets(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
                .opacity(row.wanted ? 1.0 : 0.5)
                .contextMenu {
                    // Status section
                    Button("Download") {
                        setFileWanted(row, wanted: true)
                    }
                    
                    Button("Don't Download") {
                        setFileWanted(row, wanted: false)
                    }
                    
                    Divider()
                    
                    // Priority section
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
        .navigationTitle("Files")
    }
    
    // MARK: - File Operations
    
    private func setFileWanted(_ row: TorrentFileRow, wanted: Bool) {
        let info = makeConfig(store: store)
        
        setFileWantedStatus(
            torrentId: torrentId,
            fileIndices: [row.fileIndex],
            wanted: wanted,
            info: info
        ) { response in
            print("Set wanted status: \(response)")
        }
    }
    
    private func setFilePriority(_ row: TorrentFileRow, priority: FilePriority) {
        let info = makeConfig(store: store)
        
        BitDream.setFilePriority(
            torrentId: torrentId,
            fileIndices: [row.fileIndex],
            priority: priority,
            info: info
        ) { response in
            print("Set priority: \(response)")
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