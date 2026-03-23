import Foundation

// MARK: - Enums

public enum TorrentPriority: Int, Sendable {
    case high = 1
    case normal = 0
    case low = -1
}

// Priority enum for torrent files
public enum FilePriority: Int, Sendable {
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
    case none = 0
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

enum TorrentUploadRatio: Equatable, Sendable {
    case unavailable
    case infinite
    case value(Double)

    // Transmission uses raw sentinel values here: -1 means "ratio unavailable"
    // and -2 means "uploaded without any recorded download history."
    private static let unavailableRawValue = -1.0
    private static let infiniteRawValue = -2.0

    init(rawValue: Double) {
        if rawValue == Self.unavailableRawValue {
            self = .unavailable
        } else if rawValue == Self.infiniteRawValue {
            self = .infinite
        } else {
            self = .value(rawValue)
        }
    }

    var displayValue: Double {
        switch self {
        case .unavailable:
            // No ratio to show yet, so keep the ring empty.
            return 0
        case .infinite:
            // The chip caps out at a full ring, so this shows as complete.
            return 1
        case .value(let value):
            return value
        }
    }

    var displayText: String {
        switch self {
        case .unavailable:
            // Avoid pretending this is a real numeric ratio.
            return "None"
        case .infinite:
            // Keep this readable without surfacing the raw sentinel value.
            return "1.00+"
        case .value(let value):
            return String(format: "%.2f", value)
        }
    }

    var ringProgressValue: Double {
        switch self {
        case .unavailable:
            return 0
        case .infinite:
            return 1
        case .value(let value):
            return min(value, 1.0)
        }
    }

    var usesCompletionColor: Bool {
        switch self {
        case .infinite:
            return true
        case .unavailable:
            return false
        case .value(let value):
            return value >= 1.0
        }
    }

    var isAvailable: Bool {
        switch self {
        case .unavailable:
            return false
        case .infinite, .value:
            return true
        }
    }
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

// MARK: - Domain Models

public struct Torrent: Codable, Hashable, Identifiable, Sendable {
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
    let primaryMimeType: String?
    let downloadDir: String?
    let queuePosition: Int
    let rateDownload: Int64
    let rateUpload: Int64
    let sizeWhenDone: Int64
    let status: Int
    let totalSize: Int64
    // Keep the raw RPC value so we do not lose which sentinel Transmission sent.
    let uploadRatioRaw: Double
    let uploadedEver: Int64
    let downloadedEver: Int64
    var downloadedCalc: Int64 { haveUnchecked + haveValid}
    // Views should use the interpreted ratio state instead of reading the raw
    // RPC value directly.
    var uploadRatio: TorrentUploadRatio { TorrentUploadRatio(rawValue: uploadRatioRaw) }
    var statusCalc: TorrentStatusCalc {
        if status == TorrentStatus.stopped.rawValue && percentDone == 1 {
            return TorrentStatusCalc.complete
        } else if status == TorrentStatus.stopped.rawValue {
            return TorrentStatusCalc.paused
        } else if status == TorrentStatus.queuedToVerify.rawValue
            || status == TorrentStatus.queuedToDownload.rawValue
            || status == TorrentStatus.queuedToSeed.rawValue {

            return TorrentStatusCalc.queued
        } else if status == TorrentStatus.verifying.rawValue {
            return TorrentStatusCalc.verifyingLocalData
        } else if status == TorrentStatus.downloading.rawValue && metadataPercentComplete < 1 {
            return TorrentStatusCalc.retrievingMetadata
        } else if status == TorrentStatus.downloading.rawValue && isStalled {
            return TorrentStatusCalc.stalled
        } else if status == TorrentStatus.downloading.rawValue {
            return TorrentStatusCalc.downloading
        } else if status == TorrentStatus.seeding.rawValue {
            return TorrentStatusCalc.seeding
        } else {
            return TorrentStatusCalc.unknown
        }
    }

    var isActiveTransfer: Bool {
        switch statusCalc {
        case .downloading, .retrievingMetadata, .seeding, .verifyingLocalData:
            return true
        default:
            return false
        }
    }

    enum CodingKeys: String, CodingKey {
        case activityDate
        case addedDate
        case desiredAvailable
        case error
        case errorString
        case eta
        case haveUnchecked
        case haveValid
        case id
        case isFinished
        case isStalled
        case labels
        case leftUntilDone
        case magnetLink
        case metadataPercentComplete
        case name
        case peersConnected
        case peersGettingFromUs
        case peersSendingToUs
        case percentDone
        case primaryMimeType = "primary-mime-type"
        case downloadDir
        case queuePosition
        case rateDownload
        case rateUpload
        case sizeWhenDone
        case status
        case totalSize
        case uploadRatioRaw = "uploadRatio"
        case uploadedEver
        case downloadedEver
    }
}

public struct TorrentFile: Codable, Equatable, Identifiable, Sendable {
    public var id: String { name }
    var bytesCompleted: Int64
    var length: Int64
    var name: String
    var percentDone: Double { Double(bytesCompleted) / Double(length) }
}

public struct TorrentFileStats: Codable, Equatable, Sendable {
    var bytesCompleted: Int64
    var wanted: Bool
    var priority: Int
}

public struct SessionStats: Codable, Hashable, Sendable {
    let activeTorrentCount: Int
    let downloadSpeed: Int64
    let pausedTorrentCount: Int
    let torrentCount: Int
    let uploadSpeed: Int64
    let cumulativeStats: TransmissionCumulativeStats?
    let currentStats: TransmissionCumulativeStats?

    enum CodingKeys: String, CodingKey {
        case activeTorrentCount
        case downloadSpeed
        case pausedTorrentCount
        case torrentCount
        case uploadSpeed
        case cumulativeStats = "cumulative-stats"
        case currentStats = "current-stats"
    }
}

public struct TransmissionCumulativeStats: Codable, Hashable, Sendable {
    let downloadedBytes: Int64
    let filesAdded: Int64
    let secondsActive: Int64
    let sessionCount: Int64
    let uploadedBytes: Int64
}

// MARK: - Request Argument Models

/// String-only arguments for simple requests
public typealias StringArguments = [String: String]

/// List of strings arguments (like fields)
public typealias StringListArguments = [String: [String]]

/// Empty arguments for requests that don't need any
public struct EmptyArguments: Codable, Sendable {
    public init() {}
}

/// Torrent ID list arguments
public struct TorrentIDsArgument: Codable, Sendable {
    public var ids: [Int]

    public init(ids: [Int]) {
        self.ids = ids
    }
}

public struct TorrentFilesRequestArgs: Codable, Sendable {
    public var fields: [String]
    public var ids: [Int]

    public init(fields: [String], ids: [Int]) {
        self.fields = fields
        self.ids = ids
    }
}

/// Request arguments for torrent-rename-path
public struct TorrentRenameRequestArgs: Codable, Sendable {
    public var ids: [Int]
    public var path: String
    public var name: String

    public init(ids: [Int], path: String, name: String) {
        self.ids = ids
        self.path = path
        self.name = name
    }
}

/// Request arguments for torrent-set-location
public struct TorrentSetLocationRequestArgs: Codable, Sendable {
    public var ids: [Int]
    public var location: String
    public var move: Bool

    public init(ids: [Int], location: String, move: Bool) {
        self.ids = ids
        self.location = location
        self.move = move
    }
}

/// The remove body has delete-local-data argument with hyphens
public struct TransmissionRemoveRequestArgs: Codable, Sendable {
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
public struct TorrentSetRequestArgs: Codable, Sendable {
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
        bandwidthPriority = priority.rawValue
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
public struct TorrentListResponse: Codable, Sendable {
    public let torrents: [Torrent]
}

/// Response for torrent-add method
public struct TorrentAddResponseArgs: Codable, Sendable {
    public var hashString: String
    public var id: Int
    public var name: String
}

/// Response for torrent files
public struct TorrentFilesResponseData: Codable, Sendable {
    public let files: [TorrentFile]
    public let fileStats: [TorrentFileStats]
}

/// Response for torrent files list contains a torrents array
public struct TorrentFilesResponseTorrents: Codable, Sendable {
    public let torrents: [TorrentFilesResponseData]
}

/// Response for torrent-rename-path
public struct TorrentRenameResponseArgs: Codable, Sendable {
    public let path: String
    public let name: String
    public let id: Int
}

// MARK: - Peer Models

/// Represents a single peer returned by torrent-get `peers`
public struct Peer: Codable, Identifiable, Hashable, Sendable {
    public var id: String { "\(address):\(port)" }
    public let address: String
    public let clientName: String
    public let clientIsChoked: Bool
    public let clientIsInterested: Bool
    public let flagStr: String
    public let isDownloadingFrom: Bool
    public let isEncrypted: Bool
    public let isIncoming: Bool
    public let isUploadingTo: Bool
    public let isUTP: Bool
    public let peerIsChoked: Bool
    public let peerIsInterested: Bool
    public let port: Int
    public let progress: Double
    public let rateToClient: Int64?
    public let rateToPeer: Int64?
}

/// Breakdown of where peers were discovered from, returned by torrent-get `peersFrom`
public struct PeersFrom: Codable, Hashable, Sendable {
    public let fromCache: Int
    public let fromDht: Int
    public let fromIncoming: Int
    public let fromLpd: Int
    public let fromLtep: Int
    public let fromPex: Int
    public let fromTracker: Int
}

/// Response object for peers inside torrents list
public struct TorrentPeersResponseData: Codable, Sendable {
    public let peers: [Peer]
    public let peersFrom: PeersFrom?
}

/// Response wrapper for torrent peers `torrent-get` response
public struct TorrentPeersResponseTorrents: Codable, Sendable {
    public let torrents: [TorrentPeersResponseData]
}

/// Response object for pieces inside torrents list
public struct TorrentPiecesResponseData: Codable, Sendable {
    public let pieceCount: Int
    public let pieceSize: Int64
    public let pieces: String
}

/// Response wrapper for torrent pieces `torrent-get` response
public struct TorrentPiecesResponseTorrents: Codable, Sendable {
    public let torrents: [TorrentPiecesResponseData]
}
