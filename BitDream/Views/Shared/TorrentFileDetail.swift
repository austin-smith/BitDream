import Foundation
import SwiftUI
import KeychainAccess
import UniformTypeIdentifiers

// MARK: - UI Extensions for Domain Models

extension FilePriority {
    var displayText: String {
        switch self {
        case .low: return "Low"
        case .normal: return "Normal"
        case .high: return "High"
        }
    }
    
    var color: Color {
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

/// Pick an SF Symbol by UTType category (now uses shared ContentTypeIconMapper)
func symbolForPath(_ pathOrName: String) -> String {
    return ContentTypeIconMapper.symbolForFile(pathOrName)
}

// MARK: - File Type Category Helper

/// Get file type category from filename using shared ContentTypeIconMapper
/// Executables are treated as "Other" for file context filters
func fileTypeCategory(_ pathOrName: String) -> ContentTypeCategory {
    let category = ContentTypeIconMapper.categoryForFile(pathOrName)
    return category == .executable ? .other : category
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

// FileProgressView moved to SharedComponents.swift

// MARK: - Shared Data Model

struct TorrentFileRow: Identifiable {
    let id: String
    let name: String
    let displayName: String
    let fileIndex: Int
    let size: Int64
    let bytesCompleted: Int64
    let percentDone: Double
    let priority: Int
    let wanted: Bool
    
    // Computed properties for display
    var sizeDisplay: String {
        byteCountFormatter.string(fromByteCount: size)
    }
    
    var downloadedDisplay: String {
        byteCountFormatter.string(fromByteCount: bytesCompleted)
    }
    
    var progressDisplay: String {
        "\(Int(percentDone * 100))%"
    }
    
    var fileType: String {
        fileExtension(from: name)
    }
    
    var fileSymbol: String {
        symbolForPath(name)
    }
    
    var priorityDisplay: String {
        (FilePriority(rawValue: priority) ?? .normal).displayText
    }
    
    var statusDisplay: String {
        FileStatus.displayText(for: wanted)
    }
    
    init(file: TorrentFile, stats: TorrentFileStats, percentDone: Double, priority: Int, wanted: Bool, displayName: String, fileIndex: Int) {
        self.id = file.id
        self.name = file.name
        self.displayName = displayName
        self.fileIndex = fileIndex
        self.size = file.length
        self.bytesCompleted = file.bytesCompleted
        self.percentDone = percentDone
        self.priority = priority
        self.wanted = wanted
    }
}

// MARK: - Shared File Action Executor

/// Namespaced executor that standardizes optimistic apply + revert-on-failure
/// across platforms while keeping all network calls in TransmissionFunctions.
enum FileActionExecutor {
    /// Set wanted status for specific file indices with optimistic update and revert on failure
    static func setWanted(
        torrentId: Int,
        fileIndices: [Int],
        store: Store,
        wanted: Bool,
        optimisticApply: @escaping () -> Void,
        revert: @escaping () -> Void,
        onComplete: ((TransmissionResponse) -> Void)? = nil
    ) {
        // Apply UI changes immediately on the main thread
        DispatchQueue.main.async {
            optimisticApply()
        }

        let info = makeConfig(store: store)
        setFileWantedStatus(
            torrentId: torrentId,
            fileIndices: fileIndices,
            wanted: wanted,
            info: info
        ) { response in
            if response != .success {
                DispatchQueue.main.async {
                    revert()
                }
            }
            onComplete?(response)
        }
    }

    /// Set priority for specific file indices with optimistic update and revert on failure
    static func setPriority(
        torrentId: Int,
        fileIndices: [Int],
        store: Store,
        priority: FilePriority,
        optimisticApply: @escaping () -> Void,
        revert: @escaping () -> Void,
        onComplete: ((TransmissionResponse) -> Void)? = nil
    ) {
        // Apply UI changes immediately on the main thread
        DispatchQueue.main.async {
            optimisticApply()
        }

        let info = makeConfig(store: store)
        setFilePriority(
            torrentId: torrentId,
            fileIndices: fileIndices,
            priority: priority,
            info: info
        ) { response in
            if response != .success {
                DispatchQueue.main.async {
                    revert()
                }
            }
            onComplete?(response)
        }
    }
}
