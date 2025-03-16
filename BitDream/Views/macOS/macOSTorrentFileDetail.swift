import Foundation
import SwiftUI
import CoreData
import KeychainAccess

#if os(macOS)
struct macOSTorrentFileDetail: View {
    let files: [TorrentFile]
    let fileStats: [TorrentFileStats]
    
    private var mergedFiles: [(file: TorrentFile, stats: TorrentFileStats)] {
        Array(zip(files, fileStats))
    }
    
    var body: some View {
        List {
            ForEach(mergedFiles, id: \.file.id) { pair in
                VStack {
                    HStack {
                        Text(pair.file.name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                    }
                    .padding(.bottom, 1)
                    
                    HStack {
                        Text("\(byteCountFormatter.string(fromByteCount: pair.file.bytesCompleted)) of \(byteCountFormatter.string(fromByteCount: pair.file.length)) (\(String(format: "%.1f%%", pair.file.percentDone * 100)))")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        ProgressView(value: pair.file.percentDone)
                            .frame(width: 100)
                            .tint(pair.file.percentDone == 1.0 ? .green : .blue)
                    }
                    
                    HStack {
                        Text("Priority:")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                        let priority = FilePriority(rawValue: pair.stats.priority) ?? .normal
                        Text(pair.stats.wanted ? priority.displayText : "Skip")
                            .font(.footnote)
                            .foregroundColor(pair.stats.wanted ? priority.color : .secondary)
                        Spacer()
                    }
                }
                .listRowInsets(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
                .listRowSeparator(.visible)
            }
        }
    }
}

// MARK: - Preview
#Preview("Torrent Files") {
    macOSTorrentFileDetail(
        files: [
            TorrentFile(bytesCompleted: 1024 * 1024 * 50, length: 1024 * 1024 * 100, name: "sample_movie.mp4"),
            TorrentFile(bytesCompleted: 1024 * 1024 * 25, length: 1024 * 1024 * 25, name: "readme.txt"),
            TorrentFile(bytesCompleted: 1024 * 1024 * 75, length: 1024 * 1024 * 200, name: "large_dataset.zip"),
            TorrentFile(bytesCompleted: 0, length: 1024 * 1024 * 10, name: "not_started_file.iso"),
            TorrentFile(bytesCompleted: 0, length: 1024 * 1024 * 50, name: "unwanted_file.mkv")
        ],
        fileStats: [
            TorrentFileStats(bytesCompleted: 1024 * 1024 * 50, wanted: true, priority: -1),  // Low priority
            TorrentFileStats(bytesCompleted: 1024 * 1024 * 25, wanted: true, priority: 0),   // Normal priority
            TorrentFileStats(bytesCompleted: 1024 * 1024 * 75, wanted: true, priority: 1),   // High priority
            TorrentFileStats(bytesCompleted: 0, wanted: true, priority: -1),                 // Low priority
            TorrentFileStats(bytesCompleted: 0, wanted: false, priority: -1)                 // Unwanted file with low priority
        ]
    )
}

#else
// Empty struct for iOS to reference - this won't be compiled on iOS but provides the type
struct macOSTorrentFileDetail: View {
    let files: [TorrentFile]
    let fileStats: [TorrentFileStats]
    
    var body: some View {
        EmptyView()
    }
}
#endif 