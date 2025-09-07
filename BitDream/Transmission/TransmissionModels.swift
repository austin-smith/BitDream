//
//  TransmissionModels.swift
//  BitDream
//
//  Created by Austin Smith on 12/29/22.
//

import Foundation

// MARK: - Enums

public enum TransmissionResponse {
    case success
    case unauthorized
    case configError
    case failed
}

public enum TorrentPriority: String {
    case high = "priority-high"
    case normal = "priority-normal"
    case low = "priority-low"
}

// Priority enum for torrent files
public enum FilePriority: Int {
    case low = -1
    case normal = 0
    case high = 1
}

public enum TorrentStatus: Int {
    case stopped = 0
    case queuedToVerify = 1
    case verifying = 2
    case queuedToDownload = 3
    case downloading = 4
    case queuedToSeed = 5
    case seeding = 6
}

public enum TorrentError: Int {
    /// everything's fine
    case ok = 0
    /// when we announced to the tracker, we got a warning in the response
    case trackerWarning = 1
    /// when we announced to the tracker, we got an error in the response
    case trackerError = 2
    /// local trouble, such as disk full or permissions error
    case localError = 3
}

public enum TorrentStatusCalc: String, CaseIterable {
    case complete = "Complete"
    case paused = "Paused"
    case queued = "Queued"
    case verifyingLocalData = "Verifying local data"
    case retrievingMetadata = "Retrieving metadata"
    case downloading = "Downloading"
    case seeding = "Seeding"
    case stalled = "Stalled"
    case unknown = "Unknown"
}

// MARK: - Generic Request/Response Models

/// Generic request struct for all Transmission RPC methods
public struct TransmissionGenericRequest<T: Codable>: Codable {
    public let method: String
    public let arguments: T
    
    public init(method: String, arguments: T) {
        self.method = method
        self.arguments = arguments
    }
}

/// Generic response struct for all Transmission RPC methods
public struct TransmissionGenericResponse<T: Codable>: Codable {
    public let arguments: T
}

// MARK: - Domain Models

public struct Torrent: Codable, Hashable, Identifiable {
    let activityDate: Int
    let addedDate: Int
    let desiredAvailable: Int64
    let error: Int
    let errorString: String
    let eta: Int
    let haveUnchecked: Int64
    let haveValid: Int64
    public let id: Int
    let isFinished: Bool
    let isStalled: Bool
    let labels: [String]
    let leftUntilDone: Int64
    let magnetLink: String
    let metadataPercentComplete: Double
    let name: String
    let peersConnected: Int
    let peersGettingFromUs: Int
    let peersSendingToUs: Int
    let percentDone: Double
    let rateDownload: Int64
    let rateUpload: Int64
    let sizeWhenDone: Int64
    let status: Int
    let totalSize: Int64
    var downloadedCalc: Int64 { haveUnchecked + haveValid}
    var statusCalc: TorrentStatusCalc {
        if status == TorrentStatus.stopped.rawValue && percentDone == 1 {
            return TorrentStatusCalc.complete
        }
        else if status == TorrentStatus.stopped.rawValue {
            return TorrentStatusCalc.paused
        }
        else if status == TorrentStatus.queuedToVerify.rawValue
            || status == TorrentStatus.queuedToDownload.rawValue
            || status == TorrentStatus.queuedToSeed.rawValue {
            
            return TorrentStatusCalc.queued
        }
        else if status == TorrentStatus.verifying.rawValue {
            return TorrentStatusCalc.verifyingLocalData
        }
        else if status == TorrentStatus.downloading.rawValue && metadataPercentComplete < 1 {
            return TorrentStatusCalc.retrievingMetadata
        }
        else if status == TorrentStatus.downloading.rawValue && isStalled {
            return TorrentStatusCalc.stalled
        }
        else if status == TorrentStatus.downloading.rawValue {
            return TorrentStatusCalc.downloading
        }
        else if status == TorrentStatus.seeding.rawValue {
            return TorrentStatusCalc.seeding
        }
        else {
            return TorrentStatusCalc.unknown
        }
    }
}

public struct TorrentFile: Codable, Identifiable {
    public var id: String { name }
    var bytesCompleted: Int64
    var length: Int64
    var name: String
    var percentDone: Double { Double(bytesCompleted) / Double(length) }
}

public struct TorrentFileStats: Codable {
    var bytesCompleted: Int64
    var wanted: Bool
    var priority: Int
}

public struct SessionStats: Codable, Hashable {
    let activeTorrentCount: Int
    let downloadSpeed: Int64
    let pausedTorrentCount: Int
    let torrentCount: Int
    let uploadSpeed: Int64
}

// MARK: - Request Argument Models

/// String-only arguments for simple requests
public typealias StringArguments = [String: String]

/// List of strings arguments (like fields)
public typealias StringListArguments = [String: [String]]

/// Empty arguments for requests that don't need any
public struct EmptyArguments: Codable {
    public init() {}
}

/// Torrent ID list arguments
public struct TorrentIDsArgument: Codable {
    public var ids: [Int]
    
    public init(ids: [Int]) {
        self.ids = ids
    }
}

public struct TorrentFilesRequestArgs: Codable {
    public var fields: [String]
    public var ids: [Int]
    
    public init(fields: [String], ids: [Int]) {
        self.fields = fields
        self.ids = ids
    }
}

/// The remove body has delete-local-data argument with hyphens
public struct TransmissionRemoveRequestArgs: Codable {
    public var ids: [Int]
    public var deleteLocalData: Bool
    
    public init(ids: [Int], deleteLocalData: Bool) {
        self.ids = ids
        self.deleteLocalData = deleteLocalData
    }
    
    enum CodingKeys: String, CodingKey {
        case ids
        case deleteLocalData = "delete-local-data"
    }
}

/// Generic request arguments for torrent-set method
public struct TorrentSetRequestArgs: Codable {
    public var ids: [Int]
    public var labels: [String]?
    public var bandwidthPriority: Int?
    public var downloadLimit: Int?
    public var downloadLimited: Bool?
    public var uploadLimit: Int?
    public var uploadLimited: Bool?
    public var honorsSessionLimits: Bool?
    public var group: String?
    public var location: String?
    public var peerLimit: Int?
    public var seedIdleLimit: Int?
    public var seedIdleMode: Int?
    public var seedRatioLimit: Double?
    public var seedRatioMode: Int?
    public var sequentialDownload: Bool?
    public var priorityHigh: [Int]?
    public var priorityLow: [Int]?
    public var priorityNormal: [Int]?
    public var filesWanted: [Int]?
    public var filesUnwanted: [Int]?
    
    public init(ids: [Int]) {
        self.ids = ids
    }
    
    public init(ids: [Int], labels: [String]) {
        self.ids = ids
        self.labels = labels
    }
    
    public init(ids: [Int], priority: TorrentPriority) {
        self.ids = ids
        switch priority {
        case .high: priorityHigh = []
        case .normal: priorityNormal = []
        case .low: priorityLow = []
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case ids
        case labels
        case bandwidthPriority
        case downloadLimit = "download-limit"
        case downloadLimited = "download-limited"
        case uploadLimit = "upload-limit"
        case uploadLimited = "upload-limited"
        case honorsSessionLimits = "honors-session-limits"
        case group
        case location
        case peerLimit = "peer-limit"
        case seedIdleLimit = "seed-idle-limit"
        case seedIdleMode = "seed-idle-mode"
        case seedRatioLimit = "seed-ratio-limit"
        case seedRatioMode = "seed-ratio-mode"
        case sequentialDownload = "sequential-download"
        case priorityHigh = "priority-high"
        case priorityLow = "priority-low"
        case priorityNormal = "priority-normal"
        case filesWanted = "files-wanted"
        case filesUnwanted = "files-unwanted"
    }
}

// MARK: - Response Argument Models

/// Response for torrent list
public struct TorrentListResponse: Codable {
    public let torrents: [Torrent]
}

/// Response for torrent-add method
public struct TorrentAddResponseArgs: Codable {
    public var hashString: String
    public var id: Int
    public var name: String
}

/// Torrent add response wraps the added torrent info
public struct TorrentAddResponseData: Codable {
    public var torrentAdded: TorrentAddResponseArgs
    
    enum CodingKeys: String, CodingKey {
        case torrentAdded = "torrent-added"
    }
}

/// Response for torrent files
public struct TorrentFilesResponseData: Codable {
    public let files: [TorrentFile]
    public let fileStats: [TorrentFileStats]
}

/// Response for torrent files list contains a torrents array
public struct TorrentFilesResponseTorrents: Codable {
    public let torrents: [TorrentFilesResponseData]
}

/// Session info response arguments
public struct TransmissionSessionResponseArguments: Codable, Hashable {
    public let downloadDir: String
    public let version: String
    
    public init(downloadDir: String = "unknown", version: String = "unknown") {
        self.downloadDir = downloadDir
        self.version = version
    }
    
    enum CodingKeys: String, CodingKey {
        case downloadDir = "download-dir"
        case version
    }
}