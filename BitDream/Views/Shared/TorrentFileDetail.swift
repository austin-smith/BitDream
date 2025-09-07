import Foundation
import SwiftUI
import KeychainAccess
import UniformTypeIdentifiers

// Priority enum for torrent files
public enum FilePriority: Int {
    case low = -1
    case normal = 0
    case high = 1
    
    public var displayText: String {
        switch self {
        case .low: return "Low"
        case .normal: return "Normal"
        case .high: return "High"
        }
    }
    
    public var color: Color {
        switch self {
        case .low: return .orange
        case .normal: return .secondary
        case .high: return .green
        }
    }
}

// File status constants
struct FileStatus {
    static let wanted = "Wanted"
    static let skip = "Skip"
    
    static func displayText(for wanted: Bool) -> String {
        wanted ? Self.wanted : Self.skip
    }
    
    static func color(for wanted: Bool) -> Color {
        wanted ? .green : .secondary
    }
}

// File completion constants
struct FileCompletion {
    static let complete = "Complete"
    static let incomplete = "Incomplete"
    
    static func color(for isComplete: Bool) -> Color {
        isComplete ? .green : .blue
    }
}

// MARK: - File Type Utilities

/// Pick an SF Symbol by UTType category
func symbolForPath(_ pathOrName: String) -> String {
    let ext = URL(fileURLWithPath: pathOrName).pathExtension.lowercased()
    guard let ut = UTType(filenameExtension: ext) else { return "doc" }

    if ut.conforms(to: .image)        { return "photo" }
    if ut.conforms(to: .movie)        { return "film" }
    if ut.conforms(to: .audio)        { return "waveform" }
    if ut.conforms(to: .archive)      { return "archivebox" }
    if ut.conforms(to: .pdf)          { return "doc.richtext" }
    if ut.conforms(to: .spreadsheet)  { return "tablecells" }
    if ut.conforms(to: .presentation) { return "rectangle.on.rectangle" }
    if ut.conforms(to: .sourceCode)   { return "chevron.left.forwardslash.chevron.right" }
    if ut.conforms(to: .text)         { return "doc.text" }
    return "doc"
}

// MARK: - File Type Categories

enum FileTypeCategory: String, CaseIterable {
    case video = "Videos"
    case audio = "Audio"
    case image = "Images"
    case document = "Documents"
    case archive = "Archives"
    case other = "Other"
}


/// Get file type category from filename
func fileTypeCategory(_ pathOrName: String) -> FileTypeCategory {
    let ext = URL(fileURLWithPath: pathOrName).pathExtension.lowercased()
    guard let ut = UTType(filenameExtension: ext) else { return .other }

    if ut.conforms(to: .movie) || ut.conforms(to: .video) { return .video }
    if ut.conforms(to: .audio) { return .audio }
    if ut.conforms(to: .image) { return .image }
    if ut.conforms(to: .pdf) || ut.conforms(to: .text) || 
       ut.conforms(to: .spreadsheet) || ut.conforms(to: .presentation) { return .document }
    if ut.conforms(to: .archive) { return .archive }
    return .other
}

// MARK: - Shared File Utilities

/// Calculate common folder prefix across multiple file paths
func calculateCommonPrefix(_ filenames: [String]) -> String {
    guard !filenames.isEmpty else { return "" }
    guard filenames.count > 1 else { return "" }
    
    // Find the shortest path to avoid index out of bounds
    let shortestPath = filenames.min(by: { $0.count < $1.count }) ?? ""
    var commonPrefix = ""
    
    for i in shortestPath.indices {
        let char = shortestPath[i]
        if filenames.allSatisfy({ $0.indices.contains(i) && $0[i] == char }) {
            commonPrefix.append(char)
        } else {
            break
        }
    }
    
    // Only return prefix if it ends with a slash (complete folder)
    if let lastSlash = commonPrefix.lastIndex(of: "/") {
        return String(commonPrefix[...lastSlash])
    }
    
    return ""
}

/// Strip common prefix from filename if it exists
func stripCommonPrefix(_ filename: String, prefix: String) -> String {
    guard !prefix.isEmpty, filename.hasPrefix(prefix) else { return filename }
    return String(filename.dropFirst(prefix.count))
}

/// Process all files with smart display names (calculates prefix once)
func processFilesForDisplay(_ files: [TorrentFile], stats: [TorrentFileStats]) -> [(file: TorrentFile, stats: TorrentFileStats, displayName: String, fileIndex: Int)] {
    let filenames = files.map { $0.name }
    let commonPrefix = calculateCommonPrefix(filenames)
    
    return zip(files, stats).enumerated().map { index, pair in
        (file: pair.0, stats: pair.1, displayName: stripCommonPrefix(pair.0.name, prefix: commonPrefix), fileIndex: index)
    }
}

/// Get file extension without the dot
func fileExtension(from filename: String) -> String {
    let pathExtension = URL(fileURLWithPath: filename).pathExtension
    guard !pathExtension.isEmpty else { return "—" }
    return pathExtension.lowercased()
}

/// Platform-agnostic wrapper for TorrentFileDetail
/// This view simply delegates to the appropriate platform-specific implementation
struct TorrentFileDetail: View {
    let files: [TorrentFile]
    let fileStats: [TorrentFileStats]
    let torrentId: Int
    let store: Store
    
    var body: some View {
        #if os(iOS)
        iOSTorrentFileDetail(files: files, fileStats: fileStats, torrentId: torrentId, store: store)
        #elseif os(macOS)
        macOSTorrentFileDetail(files: files, fileStats: fileStats, torrentId: torrentId, store: store)
        #endif
    }
}

// MARK: - Preview Data

/// Shared test data for previews
struct TorrentFilePreviewData {
    static let sampleFiles: [TorrentFile] = [
        TorrentFile(bytesCompleted: 1024 * 1024 * 50, length: 1024 * 1024 * 100, name: "Movie.2024/Movie.2024.mkv"),
        TorrentFile(bytesCompleted: 1024 * 1024 * 25, length: 1024 * 1024 * 25, name: "Movie.2024/Subtitles/English.srt"),
        TorrentFile(bytesCompleted: 1024 * 1024 * 75, length: 1024 * 1024 * 200, name: "Movie.2024/extras/behind_scenes.mp4"),
        TorrentFile(bytesCompleted: 0, length: 1024 * 1024 * 10, name: "Movie.2024/poster.jpg"),
        TorrentFile(bytesCompleted: 0, length: 1024 * 1024 * 50, name: "Movie.2024/soundtrack.mp3")
    ]
    
    static let sampleFileStats: [TorrentFileStats] = [
        TorrentFileStats(bytesCompleted: 1024 * 1024 * 50, wanted: true, priority: -1),  // Low priority
        TorrentFileStats(bytesCompleted: 1024 * 1024 * 25, wanted: true, priority: 0),   // Normal priority
        TorrentFileStats(bytesCompleted: 1024 * 1024 * 75, wanted: true, priority: 1),   // High priority
        TorrentFileStats(bytesCompleted: 0, wanted: true, priority: -1),                 // Low priority
        TorrentFileStats(bytesCompleted: 0, wanted: false, priority: -1)                 // Unwanted file with low priority
    ]
}

// MARK: - Shared Components

/// Priority badge component for consistent styling across platforms
struct PriorityBadge: View {
    let priority: FilePriority
    
    var body: some View {
        Text(priority.displayText)
            .font(.caption)
            .foregroundColor(priority.color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(priority.color.opacity(0.15))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(priority.color.opacity(0.3), lineWidth: 0.5)
            )
            .cornerRadius(4)
    }
}

/// Status badge component for consistent styling across platforms
struct StatusBadge: View {
    let wanted: Bool
    
    var body: some View {
        Text(FileStatus.displayText(for: wanted))
            .font(.caption)
            .foregroundColor(FileStatus.color(for: wanted))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(FileStatus.color(for: wanted).opacity(0.15))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(FileStatus.color(for: wanted).opacity(0.3), lineWidth: 0.5)
        )
        .cornerRadius(4)
    }
}

/// File type chip with icon and extension for consistent styling across platforms
struct FileTypeChip: View {
    let filename: String
    var iconSize: CGFloat = 10
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbolForPath(filename))
                .frame(width: iconSize, alignment: .center)
                .font(.system(size: iconSize))
                .foregroundColor(.secondary)
            
            Text(fileExtension(from: filename))
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.secondary.opacity(0.15))
        .cornerRadius(4)
    }
}

/// Progress view with bar and percentage for consistent styling across platforms
struct FileProgressView: View {
    let percentDone: Double
    var showDetailedText: Bool = false
    var bytesCompleted: Int64 = 0
    var totalSize: Int64 = 0
    
    var body: some View {
        HStack(spacing: 6) {
            ProgressView(value: percentDone)
                .progressViewStyle(.linear)
                .tint(percentDone >= 1.0 ? .green : .blue)
                .frame(minWidth: showDetailedText ? 100 : 50)
            
            if showDetailedText {
                // iOS style with detailed percentage
                Text("\(String(format: "%.1f%%", percentDone * 100))")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
            } else {
                // macOS style with just percentage
                Text("\(Int(percentDone * 100))%")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 30, alignment: .trailing)
            }
        }
    }
}

// MARK: - Shared Data Model

public class TorrentFileRow: NSObject, Identifiable {
    public let id: String
    public let name: String
    public let displayName: String
    public let fileIndex: Int
    public let size: Int64
    public let bytesCompleted: Int64
    public let percentDone: Double
    public let priority: Int
    public let wanted: Bool
    
    // Computed properties for display
    public var sizeDisplay: String {
        byteCountFormatter.string(fromByteCount: size)
    }
    
    public var downloadedDisplay: String {
        byteCountFormatter.string(fromByteCount: bytesCompleted)
    }
    
    public var progressDisplay: String {
        "\(Int(percentDone * 100))%"
    }
    
    public var fileExtension: String {
        BitDream.fileExtension(from: name)
    }
    
    public var fileSymbol: String {
        symbolForPath(name)
    }
    
    public var priorityDisplay: String {
        (FilePriority(rawValue: priority) ?? .normal).displayText
    }
    
    public var statusDisplay: String {
        FileStatus.displayText(for: wanted)
    }
    
    public init(file: TorrentFile, stats: TorrentFileStats, percentDone: Double, priority: Int, wanted: Bool, displayName: String, fileIndex: Int) {
        self.id = file.id
        self.name = file.name
        self.displayName = displayName
        self.fileIndex = fileIndex
        self.size = file.length
        self.bytesCompleted = file.bytesCompleted
        self.percentDone = percentDone
        self.priority = priority
        self.wanted = wanted
        super.init()
    }
}
