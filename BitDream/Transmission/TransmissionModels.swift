//
//  TransmissionModels.swift
//  BitDream
//
//  Created by Austin Smith on 12/29/22.
//

import Foundation

public enum TorrentStatus: Int {
    case stopped = 0
    case queuedToVerify = 1
    case verifying = 2
    case queuedToDownload = 3
    case downloading = 4
    case queuedToSeed = 5
    case seeding = 6
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

public struct Torrent: Codable, Hashable, Identifiable {
    let activityDate: Int
    let addedDate: Int
    let desiredAvailable: Int64
    let eta: Int
    let haveUnchecked: Int64
    let haveValid: Int64
    public let id: Int
    let isFinished: Bool
    let isStalled: Bool
    let leftUntilDone: Int64
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
        if percentDone == 1 {
            return TorrentStatusCalc.complete
        }
        else if status == TorrentStatus.stopped.rawValue {
            return TorrentStatusCalc.paused
        }
        else if status == TorrentStatus.queuedToVerify.rawValue || status == TorrentStatus.queuedToDownload.rawValue || status == TorrentStatus.queuedToSeed.rawValue {
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

public struct SessionStats: Codable, Hashable {
    let activeTorrentCount: Int
    let downloadSpeed: Int64
    let pausedTorrentCount: Int
    let torrentCount: Int
    let uploadSpeed: Int64
}
