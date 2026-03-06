import Foundation

// MARK: - Session Response Models

/// Session info response arguments
public struct TransmissionSessionResponseArguments: Codable, Hashable, Sendable {
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
    public let downloadDir: String
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

/// Response for free-space method
public struct FreeSpaceResponse: Codable, Sendable {
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
public struct PortTestResponse: Codable, Sendable {
    public let portIsOpen: Bool?
    public let ipProtocol: String?

    enum CodingKeys: String, CodingKey {
        case portIsOpen = "port-is-open"
        case ipProtocol = "ip_protocol"
    }
}

/// Response for blocklist-update method
public struct BlocklistUpdateResponse: Codable, Sendable {
    public let blocklistSize: Int

    enum CodingKeys: String, CodingKey {
        case blocklistSize = "blocklist-size"
    }
}
