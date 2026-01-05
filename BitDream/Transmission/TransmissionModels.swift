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
    let primaryMimeType: String?
    let downloadDir: String?
    let queuePosition: Int
    let rateDownload: Int64
    let rateUpload: Int64
    let sizeWhenDone: Int64
    let status: Int
    let totalSize: Int64
    let uploadRatio: Double
    let uploadedEver: Int64
    let downloadedEver: Int64
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
        case uploadRatio
        case uploadedEver
        case downloadedEver
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

public struct TransmissionCumulativeStats: Codable, Hashable {
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

/// Request arguments for torrent-rename-path
public struct TorrentRenameRequestArgs: Codable {
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
public struct TorrentSetLocationRequestArgs: Codable {
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
    // Existing fields
    public let downloadDir: String
    public let version: String

    // Speed & Bandwidth
    public let speedLimitDown: Int64
    public let speedLimitDownEnabled: Bool
    public let speedLimitUp: Int64
    public let speedLimitUpEnabled: Bool
    public let altSpeedDown: Int64
    public let altSpeedUp: Int64
    public let altSpeedEnabled: Bool
    public let altSpeedTimeBegin: Int
    public let altSpeedTimeEnd: Int
    public let altSpeedTimeEnabled: Bool
    public let altSpeedTimeDay: Int

    // File Management
    public let incompleteDir: String
    public let incompleteDirEnabled: Bool
    public let startAddedTorrents: Bool
    public let trashOriginalTorrentFiles: Bool
    public let renamePartialFiles: Bool

    // Queue Management
    public let downloadQueueEnabled: Bool
    public let downloadQueueSize: Int
    public let seedQueueEnabled: Bool
    public let seedQueueSize: Int
    public let seedRatioLimited: Bool
    public let seedRatioLimit: Double
    public let idleSeedingLimit: Int
    public let idleSeedingLimitEnabled: Bool
    public let queueStalledEnabled: Bool
    public let queueStalledMinutes: Int

    // Network Settings
    public let peerPort: Int
    public let peerPortRandomOnStart: Bool
    public let portForwardingEnabled: Bool
    public let dhtEnabled: Bool
    public let pexEnabled: Bool
    public let lpdEnabled: Bool
    public let encryption: String
    public let utpEnabled: Bool
    public let peerLimitGlobal: Int
    public let peerLimitPerTorrent: Int

    // Blocklist
    public let blocklistEnabled: Bool
    public let blocklistSize: Int
    public let blocklistUrl: String

    // Default Trackers
    public let defaultTrackers: String

    public init(
        downloadDir: String,
        version: String,
        speedLimitDown: Int64,
        speedLimitDownEnabled: Bool,
        speedLimitUp: Int64,
        speedLimitUpEnabled: Bool,
        altSpeedDown: Int64,
        altSpeedUp: Int64,
        altSpeedEnabled: Bool,
        altSpeedTimeBegin: Int,
        altSpeedTimeEnd: Int,
        altSpeedTimeEnabled: Bool,
        altSpeedTimeDay: Int,
        incompleteDir: String,
        incompleteDirEnabled: Bool,
        startAddedTorrents: Bool,
        trashOriginalTorrentFiles: Bool,
        renamePartialFiles: Bool,
        downloadQueueEnabled: Bool,
        downloadQueueSize: Int,
        seedQueueEnabled: Bool,
        seedQueueSize: Int,
        seedRatioLimited: Bool,
        seedRatioLimit: Double,
        idleSeedingLimit: Int,
        idleSeedingLimitEnabled: Bool,
        queueStalledEnabled: Bool,
        queueStalledMinutes: Int,
        peerPort: Int,
        peerPortRandomOnStart: Bool,
        portForwardingEnabled: Bool,
        dhtEnabled: Bool,
        pexEnabled: Bool,
        lpdEnabled: Bool,
        encryption: String,
        utpEnabled: Bool,
        peerLimitGlobal: Int,
        peerLimitPerTorrent: Int,
        blocklistEnabled: Bool,
        blocklistSize: Int,
        blocklistUrl: String,
        defaultTrackers: String
    ) {
        self.downloadDir = downloadDir
        self.version = version
        self.speedLimitDown = speedLimitDown
        self.speedLimitDownEnabled = speedLimitDownEnabled
        self.speedLimitUp = speedLimitUp
        self.speedLimitUpEnabled = speedLimitUpEnabled
        self.altSpeedDown = altSpeedDown
        self.altSpeedUp = altSpeedUp
        self.altSpeedEnabled = altSpeedEnabled
        self.altSpeedTimeBegin = altSpeedTimeBegin
        self.altSpeedTimeEnd = altSpeedTimeEnd
        self.altSpeedTimeEnabled = altSpeedTimeEnabled
        self.altSpeedTimeDay = altSpeedTimeDay
        self.incompleteDir = incompleteDir
        self.incompleteDirEnabled = incompleteDirEnabled
        self.startAddedTorrents = startAddedTorrents
        self.trashOriginalTorrentFiles = trashOriginalTorrentFiles
        self.renamePartialFiles = renamePartialFiles
        self.downloadQueueEnabled = downloadQueueEnabled
        self.downloadQueueSize = downloadQueueSize
        self.seedQueueEnabled = seedQueueEnabled
        self.seedQueueSize = seedQueueSize
        self.seedRatioLimited = seedRatioLimited
        self.seedRatioLimit = seedRatioLimit
        self.idleSeedingLimit = idleSeedingLimit
        self.idleSeedingLimitEnabled = idleSeedingLimitEnabled
        self.queueStalledEnabled = queueStalledEnabled
        self.queueStalledMinutes = queueStalledMinutes
        self.peerPort = peerPort
        self.peerPortRandomOnStart = peerPortRandomOnStart
        self.portForwardingEnabled = portForwardingEnabled
        self.dhtEnabled = dhtEnabled
        self.pexEnabled = pexEnabled
        self.lpdEnabled = lpdEnabled
        self.encryption = encryption
        self.utpEnabled = utpEnabled
        self.peerLimitGlobal = peerLimitGlobal
        self.peerLimitPerTorrent = peerLimitPerTorrent
        self.blocklistEnabled = blocklistEnabled
        self.blocklistSize = blocklistSize
        self.blocklistUrl = blocklistUrl
        self.defaultTrackers = defaultTrackers
    }

    enum CodingKeys: String, CodingKey {
        case downloadDir = "download-dir"
        case version
        case speedLimitDown = "speed-limit-down"
        case speedLimitDownEnabled = "speed-limit-down-enabled"
        case speedLimitUp = "speed-limit-up"
        case speedLimitUpEnabled = "speed-limit-up-enabled"
        case altSpeedDown = "alt-speed-down"
        case altSpeedUp = "alt-speed-up"
        case altSpeedEnabled = "alt-speed-enabled"
        case altSpeedTimeBegin = "alt-speed-time-begin"
        case altSpeedTimeEnd = "alt-speed-time-end"
        case altSpeedTimeEnabled = "alt-speed-time-enabled"
        case altSpeedTimeDay = "alt-speed-time-day"
        case incompleteDir = "incomplete-dir"
        case incompleteDirEnabled = "incomplete-dir-enabled"
        case startAddedTorrents = "start-added-torrents"
        case trashOriginalTorrentFiles = "trash-original-torrent-files"
        case renamePartialFiles = "rename-partial-files"
        case downloadQueueEnabled = "download-queue-enabled"
        case downloadQueueSize = "download-queue-size"
        case seedQueueEnabled = "seed-queue-enabled"
        case seedQueueSize = "seed-queue-size"
        case seedRatioLimited = "seedRatioLimited"
        case seedRatioLimit = "seedRatioLimit"
        case idleSeedingLimit = "idle-seeding-limit"
        case idleSeedingLimitEnabled = "idle-seeding-limit-enabled"
        case queueStalledEnabled = "queue-stalled-enabled"
        case queueStalledMinutes = "queue-stalled-minutes"
        case peerPort = "peer-port"
        case peerPortRandomOnStart = "peer-port-random-on-start"
        case portForwardingEnabled = "port-forwarding-enabled"
        case dhtEnabled = "dht-enabled"
        case pexEnabled = "pex-enabled"
        case lpdEnabled = "lpd-enabled"
        case encryption = "encryption"
        case utpEnabled = "utp-enabled"
        case peerLimitGlobal = "peer-limit-global"
        case peerLimitPerTorrent = "peer-limit-per-torrent"
        case blocklistEnabled = "blocklist-enabled"
        case blocklistSize = "blocklist-size"
        case blocklistUrl = "blocklist-url"
        case defaultTrackers = "default-trackers"
    }
}

/// Response for torrent-rename-path
public struct TorrentRenameResponseArgs: Codable {
    public let path: String
    public let name: String
    public let id: Int
}

/// Response for free-space method
public struct FreeSpaceResponse: Codable {
    public let path: String
    public let sizeBytes: Int64
    public let totalSize: Int64

    enum CodingKeys: String, CodingKey {
        case path
        case sizeBytes = "size-bytes"
        case totalSize = "total_size"
    }
}

// MARK: - Session Set Request Models

/// Request arguments for session-set method
/// Contains all mutable session properties that can be modified
public struct TransmissionSessionSetRequestArgs: Codable {
    // Speed & Bandwidth
    public var speedLimitDown: Int64?
    public var speedLimitDownEnabled: Bool?
    public var speedLimitUp: Int64?
    public var speedLimitUpEnabled: Bool?
    public var altSpeedDown: Int64?
    public var altSpeedUp: Int64?
    public var altSpeedEnabled: Bool?
    public var altSpeedTimeBegin: Int?
    public var altSpeedTimeEnd: Int?
    public var altSpeedTimeEnabled: Bool?
    public var altSpeedTimeDay: Int?

    // File Management
    public var downloadDir: String?
    public var incompleteDir: String?
    public var incompleteDirEnabled: Bool?
    public var startAddedTorrents: Bool?
    public var trashOriginalTorrentFiles: Bool?
    public var renamePartialFiles: Bool?

    // Queue Management
    public var downloadQueueEnabled: Bool?
    public var downloadQueueSize: Int?
    public var seedQueueEnabled: Bool?
    public var seedQueueSize: Int?
    public var seedRatioLimited: Bool?
    public var seedRatioLimit: Double?
    public var idleSeedingLimit: Int?
    public var idleSeedingLimitEnabled: Bool?
    public var queueStalledEnabled: Bool?
    public var queueStalledMinutes: Int?

    // Network Settings
    public var peerPort: Int?
    public var peerPortRandomOnStart: Bool?
    public var portForwardingEnabled: Bool?
    public var dhtEnabled: Bool?
    public var pexEnabled: Bool?
    public var lpdEnabled: Bool?
    public var encryption: String?
    public var utpEnabled: Bool?
    public var peerLimitGlobal: Int?
    public var peerLimitPerTorrent: Int?

    // Blocklist
    public var blocklistEnabled: Bool?
    public var blocklistUrl: String?

    // Default Trackers
    public var defaultTrackers: String?

    // Cache
    public var cacheSizeMb: Int?

    // Scripts
    public var scriptTorrentDoneEnabled: Bool?
    public var scriptTorrentDoneFilename: String?
    public var scriptTorrentAddedEnabled: Bool?
    public var scriptTorrentAddedFilename: String?
    public var scriptTorrentDoneSeedingEnabled: Bool?
    public var scriptTorrentDoneSeedingFilename: String?

    public init() {}

    enum CodingKeys: String, CodingKey {
        case speedLimitDown = "speed-limit-down"
        case speedLimitDownEnabled = "speed-limit-down-enabled"
        case speedLimitUp = "speed-limit-up"
        case speedLimitUpEnabled = "speed-limit-up-enabled"
        case altSpeedDown = "alt-speed-down"
        case altSpeedUp = "alt-speed-up"
        case altSpeedEnabled = "alt-speed-enabled"
        case altSpeedTimeBegin = "alt-speed-time-begin"
        case altSpeedTimeEnd = "alt-speed-time-end"
        case altSpeedTimeEnabled = "alt-speed-time-enabled"
        case altSpeedTimeDay = "alt-speed-time-day"
        case downloadDir = "download-dir"
        case incompleteDir = "incomplete-dir"
        case incompleteDirEnabled = "incomplete-dir-enabled"
        case startAddedTorrents = "start-added-torrents"
        case trashOriginalTorrentFiles = "trash-original-torrent-files"
        case renamePartialFiles = "rename-partial-files"
        case downloadQueueEnabled = "download-queue-enabled"
        case downloadQueueSize = "download-queue-size"
        case seedQueueEnabled = "seed-queue-enabled"
        case seedQueueSize = "seed-queue-size"
        case seedRatioLimited = "seedRatioLimited"
        case seedRatioLimit = "seedRatioLimit"
        case idleSeedingLimit = "idle-seeding-limit"
        case idleSeedingLimitEnabled = "idle-seeding-limit-enabled"
        case queueStalledEnabled = "queue-stalled-enabled"
        case queueStalledMinutes = "queue-stalled-minutes"
        case peerPort = "peer-port"
        case peerPortRandomOnStart = "peer-port-random-on-start"
        case portForwardingEnabled = "port-forwarding-enabled"
        case dhtEnabled = "dht-enabled"
        case pexEnabled = "pex-enabled"
        case lpdEnabled = "lpd-enabled"
        case encryption = "encryption"
        case utpEnabled = "utp-enabled"
        case peerLimitGlobal = "peer-limit-global"
        case peerLimitPerTorrent = "peer-limit-per-torrent"
        case blocklistEnabled = "blocklist-enabled"
        case blocklistUrl = "blocklist-url"
        case defaultTrackers = "default-trackers"
        case cacheSizeMb = "cache-size-mb"
        case scriptTorrentDoneEnabled = "script-torrent-done-enabled"
        case scriptTorrentDoneFilename = "script-torrent-done-filename"
        case scriptTorrentAddedEnabled = "script-torrent-added-enabled"
        case scriptTorrentAddedFilename = "script-torrent-added-filename"
        case scriptTorrentDoneSeedingEnabled = "script-torrent-done-seeding-enabled"
        case scriptTorrentDoneSeedingFilename = "script-torrent-done-seeding-filename"
    }
}

// MARK: - Port Test Models

/// Request arguments for port-test method
public struct PortTestRequestArgs: Codable {
    public var ipProtocol: String?

    public init(ipProtocol: String? = nil) {
        self.ipProtocol = ipProtocol
    }

    enum CodingKeys: String, CodingKey {
        case ipProtocol = "ip_protocol"
    }
}

/// Response for port-test method
public struct PortTestResponse: Codable {
    public let portIsOpen: Bool?
    public let ipProtocol: String?

    enum CodingKeys: String, CodingKey {
        case portIsOpen = "port-is-open"
        case ipProtocol = "ip_protocol"
    }
}

/// Response for blocklist-update method
public struct BlocklistUpdateResponse: Codable {
    public let blocklistSize: Int

    enum CodingKeys: String, CodingKey {
        case blocklistSize = "blocklist-size"
    }
}

// MARK: - Peer Models

/// Represents a single peer returned by torrent-get `peers`
public struct Peer: Codable, Identifiable, Hashable {
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
public struct PeersFrom: Codable, Hashable {
    public let fromCache: Int
    public let fromDht: Int
    public let fromIncoming: Int
    public let fromLpd: Int
    public let fromLtep: Int
    public let fromPex: Int
    public let fromTracker: Int
}

/// Response object for peers inside torrents list
public struct TorrentPeersResponseData: Codable {
    public let peers: [Peer]
    public let peersFrom: PeersFrom?
}

/// Response wrapper for torrent peers `torrent-get` response
public struct TorrentPeersResponseTorrents: Codable {
    public let torrents: [TorrentPeersResponseData]
}

/// Response object for pieces inside torrents list
public struct TorrentPiecesResponseData: Codable {
    public let pieceCount: Int
    public let pieceSize: Int64
    public let pieces: String
}

/// Response wrapper for torrent pieces `torrent-get` response
public struct TorrentPiecesResponseTorrents: Codable {
    public let torrents: [TorrentPiecesResponseData]
}