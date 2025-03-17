import Foundation
import SwiftUI
import KeychainAccess

// Priority enum for torrent files
enum FilePriority: Int {
    case low = -1
    case normal = 0
    case high = 1
    
    var displayText: String {
        switch self {
        case .low: return "Low"
        case .normal: return "Normal"
        case .high: return "High"
        }
    }
    
    var color: Color {
        switch self {
        case .low: return .green
        case .normal: return .primary
        case .high: return .red
        }
    }
}

/// Platform-agnostic wrapper for TorrentFileDetail
/// This view simply delegates to the appropriate platform-specific implementation
struct TorrentFileDetail: View {
    let files: [TorrentFile]
    let fileStats: [TorrentFileStats]
    
    var body: some View {
        #if os(iOS)
        iOSTorrentFileDetail(files: files, fileStats: fileStats)
        #elseif os(macOS)
        macOSTorrentFileDetail(files: files, fileStats: fileStats)
        #endif
    }
}

#Preview("Torrent Files") {
    TorrentFileDetail(
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
