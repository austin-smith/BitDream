//
//  ContentTypeIconMapper.swift
//  BitDream
//
//  Shared icon mapping system for both MIME types and file extensions
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Content Type Icon Mapper

/// Unified system for mapping MIME types and file extensions to SF Symbols
public enum ContentTypeIconMapper {

    // MARK: - Primary Interface

    /// Get SF Symbol for a torrent based on its primary MIME type
    /// - Parameter mimeType: The primary MIME type from Transmission API (optional)
    /// - Returns: SF Symbol name for the content type
    public static func symbolForTorrent(mimeType: String?) -> String {
        guard let mimeType = mimeType?.lowercased(), !mimeType.isEmpty else {
            return defaultIcon
        }

        return symbolForMimeType(mimeType)
    }

    /// Get SF Symbol for a file based on its path/name (existing functionality)
    /// - Parameter pathOrName: File path or filename
    /// - Returns: SF Symbol name for the file type
    public static func symbolForFile(_ pathOrName: String) -> String {
        let ext = URL(fileURLWithPath: pathOrName).pathExtension.lowercased()
        guard let utType = UTType(filenameExtension: ext) else {
            return defaultIcon
        }

        return symbolForUTType(utType)
    }

    // MARK: - MIME Type Mapping

    private static func symbolForMimeType(_ mimeType: String) -> String {
        // Check for exact MIME type matches first
        if let exactMatch = exactMimeTypeMap[mimeType] {
            return exactMatch
        }

        // Check for MIME type category matches (e.g., "video/*")
        let category = mimeType.components(separatedBy: "/").first ?? ""
        return mimeTypeCategoryMap[category] ?? defaultIcon
    }

    // MARK: - UTType Mapping (for files)

    private static func symbolForUTType(_ utType: UTType) -> String {
        if utType.conforms(to: .image)        { return "photo" }
        if utType.conforms(to: .movie)        { return "film" }
        if utType.conforms(to: .audio)        { return "waveform" }
        if utType.conforms(to: .archive)      { return "zipper.page" }
        if utType.conforms(to: .pdf)          { return "richtext.page" }
        if utType.conforms(to: .spreadsheet)  { return "tablecells" }
        if utType.conforms(to: .presentation) { return "rectangle.on.rectangle" }
        if utType.conforms(to: .sourceCode)   { return "chevron.left.forwardslash.chevron.right" }
        if utType.conforms(to: .text)         { return "doc.text" }
        if utType.conforms(to: .executable)   { return "document" }
        return defaultIcon
    }

    // MARK: - Icon Maps

    /// Exact MIME type to icon mapping
    private static let exactMimeTypeMap: [String: String] = [
        // Torrent files
        "application/x-bittorrent": "arrow.down.circle",

        // Archives
        "application/zip": "zipper.page",
        "application/x-rar-compressed": "zipper.page",
        "application/x-7z-compressed": "zipper.page",
        "application/gzip": "zipper.page",
        "application/x-tar": "zipper.page",

        // Documents
        "application/pdf": "richtext.page",
        "application/msword": "text.page",
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document": "text.page",

        // Spreadsheets
        "application/vnd.ms-excel": "tablecells",
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet": "tablecells",

        // Presentations
        "application/vnd.ms-powerpoint": "rectangle.on.rectangle",
        "application/vnd.openxmlformats-officedocument.presentationml.presentation": "rectangle.on.rectangle",

        // Disk images
        "application/x-iso9660-image": "opticaldiscdrive",
        "application/x-apple-diskimage": "opticaldiscdrive",
    ]

    /// MIME type category to icon mapping
    private static let mimeTypeCategoryMap: [String: String] = [
        "video": "film",
        "audio": "waveform",
        "image": "photo",
        "text": "doc.text",
        "application": "doc",
        "font": "textformat",
    ]

    // MARK: - Default Icon

    /// Default icon for unknown content types
    private static let defaultIcon = "document"
}

// MARK: - Content Type Categories

/// Enhanced content type categories for better organization
public enum ContentTypeCategory: String, CaseIterable {
    case video = "Videos"
    case audio = "Audio"
    case image = "Images"
    case document = "Documents"
    case archive = "Archives"
    case executable = "Applications"
    case other = "Other"
}

extension ContentTypeCategory {
    var title: String { rawValue }

    var icon: String {
        switch self {
        case .video: return "film"
        case .audio: return "waveform"
        case .image: return "photo"
        case .document: return "doc.text"
        case .archive: return "zipper.page"
        case .executable: return "gearshape.2"
        case .other: return "document"
        }
    }
}

// MARK: - Utility Extensions

extension ContentTypeIconMapper {

    /// Get content type category from MIME type
    /// - Parameter mimeType: The MIME type string
    /// - Returns: Content type category
    public static func categoryForMimeType(_ mimeType: String?) -> ContentTypeCategory {
        guard let mimeType = mimeType?.lowercased(), !mimeType.isEmpty else {
            return .other
        }

        let category = mimeType.components(separatedBy: "/").first ?? ""

        switch category {
        case "video": return .video
        case "audio": return .audio
        case "image": return .image
        case "text": return .document
        case "application":
            // Check for specific application types
            if mimeType.contains("pdf") || mimeType.contains("word") || mimeType.contains("document") {
                return .document
            }
            if mimeType.contains("zip") || mimeType.contains("rar") || mimeType.contains("compressed") {
                return .archive
            }
            if mimeType.contains("executable") || mimeType.contains("program") {
                return .executable
            }
            return .document
        default: return .other
        }
    }

    /// Get content type category from file path (existing functionality)
    /// - Parameter pathOrName: File path or filename
    /// - Returns: Content type category
    public static func categoryForFile(_ pathOrName: String) -> ContentTypeCategory {
        let ext = URL(fileURLWithPath: pathOrName).pathExtension.lowercased()
        guard let utType = UTType(filenameExtension: ext) else { return .other }

        if utType.conforms(to: .movie) || utType.conforms(to: .video) { return .video }
        if utType.conforms(to: .audio) { return .audio }
        if utType.conforms(to: .image) { return .image }
        if utType.conforms(to: .pdf) || utType.conforms(to: .text) ||
           utType.conforms(to: .spreadsheet) || utType.conforms(to: .presentation) { return .document }
        if utType.conforms(to: .archive) { return .archive }
        if utType.conforms(to: .executable) { return .executable }
        return .other
    }
}
