#if BITDREAM_SAMPLE_SUPPORT
import Foundation
import SwiftData

/// Adapts the shared catalog to the app's actual RPC models.
enum SampleFixtures {
    static let torrents = SampleLibrary.items.map(torrent)
    static let details = SampleLibrary.items.map(detail)
    static var sessionStats: SessionStats { statistics(for: torrents) }
    static let remoteServerAddress = "remote.example.invalid"

    @MainActor
    static func makeHosts() -> [Host] {
        [Host(serverID: SampleLibrary.serverID, isDefault: true, isSSL: true,
              name: SampleLibrary.serverName, port: 9091, server: "demo.example.invalid",
              username: "demo", version: sessionConfiguration.version),
         Host(serverID: "sample-remote-server", isSSL: true, name: "Remote Server",
              port: 9091, server: remoteServerAddress, username: "demo")]
    }

    @MainActor
    static func makeModelContainer(hosts: [Host]) -> ModelContainer {
        let persistence = PersistenceController(inMemory: true)
        hosts.forEach(persistence.container.mainContext.insert)
        do {
            try persistence.container.mainContext.save()
        } catch {
            preconditionFailure("Unable to seed sample hosts: \(error)")
        }
        return persistence.container
    }

    static func torrent(_ item: SampleLibrary.Item) -> Torrent {
        let remaining = item.size - item.completed
        return Torrent(
            activityDate: Int(SampleLibrary.referenceDate.timeIntervalSince1970),
            addedDate: Int(SampleLibrary.referenceDate.addingTimeInterval(-86_400 * Double(item.addedDaysAgo)).timeIntervalSince1970),
            desiredAvailable: remaining, error: 0, errorString: "",
            eta: item.downloadSpeed > 0 ? Int(remaining / item.downloadSpeed) : -1,
            haveUnchecked: 0, haveValid: item.completed, id: item.id,
            isFinished: item.status == 0 && remaining == 0, isStalled: item.isStalled, labels: item.labels,
            leftUntilDone: remaining, magnetLink: magnet(id: item.id), metadataPercentComplete: 1,
            name: item.name, peersConnected: item.peerCount,
            peersGettingFromUs: item.uploadSpeed > 0 ? item.peerCount : 0,
            peersSendingToUs: item.downloadSpeed > 0 ? item.peerCount : 0,
            percentDone: Double(item.completed) / Double(item.size), primaryMimeType: item.mimeType,
            downloadDir: SampleLibrary.downloadDirectory, queuePosition: item.id - 1,
            rateDownload: item.downloadSpeed, rateUpload: item.uploadSpeed, sizeWhenDone: item.size,
            status: item.status, totalSize: item.size,
            uploadRatioRaw: item.completed > 0 ? Double(item.uploaded) / Double(item.completed) : -1,
            uploadedEver: item.uploaded, downloadedEver: item.completed
        )
    }

    static func magnet(id: Int) -> String {
        "magnet:?xt=urn:btih:\(String(format: "%040x", id))"
    }

    static func detail(_ item: SampleLibrary.Item) -> TorrentDetailResponseData {
        var remaining = item.completed
        let files = item.files.map { file in
            let completed = min(remaining, file.length)
            remaining -= completed
            return TorrentFile(bytesCompleted: completed, length: file.length, name: file.name)
        }
        let stats = files.map { TorrentFileStats(bytesCompleted: $0.bytesCompleted, wanted: true, priority: 0) }
        let pieceSize = item.pieceSize
        let pieceCount = Int((item.size + pieceSize - 1) / pieceSize)
        let completePieces = item.completed == item.size ? pieceCount : Int(item.completed / pieceSize)
        var bits = [UInt8](repeating: 0, count: (pieceCount + 7) / 8)
        for index in 0..<completePieces { bits[index / 8] |= 1 << (7 - index % 8) }
        let peers = (0..<item.peerCount).map { index in
            Peer(
                address: index == 1 ? "2001:db8::42" : "203.0.113.\(index + 10)",
                clientName: index.isMultiple(of: 2) ? "Transmission 4.0.6" : "qBittorrent 5.0",
                clientIsChoked: false, clientIsInterested: item.downloadSpeed > 0,
                flagStr: (item.downloadSpeed > 0 ? "D" : "") + (item.uploadSpeed > 0 ? "U" : "") + "E",
                isDownloadingFrom: item.downloadSpeed > 0,
                isEncrypted: true, isIncoming: index.isMultiple(of: 2), isUploadingTo: item.uploadSpeed > 0,
                isUTP: true, peerIsChoked: false, peerIsInterested: item.uploadSpeed > 0, port: 51_413,
                progress: item.uploadSpeed > 0 ? 0.72 : 1,
                rateToClient: item.downloadSpeed / Int64(max(1, item.peerCount))
                    + (index == 0 ? item.downloadSpeed % Int64(max(1, item.peerCount)) : 0),
                rateToPeer: item.uploadSpeed / Int64(max(1, item.peerCount))
                    + (index == 0 ? item.uploadSpeed % Int64(max(1, item.peerCount)) : 0)
            )
        }
        return TorrentDetailResponseData(
            files: files, fileStats: stats, peers: peers,
            peersFrom: PeersFrom(fromCache: 0, fromDht: item.peerCount, fromIncoming: 0,
                                 fromLpd: 0, fromLtep: 0, fromPex: 0, fromTracker: 0),
            pieceCount: pieceCount, pieceSize: pieceSize, pieces: Data(bits).base64EncodedString()
        )
    }

    static func statistics(for torrents: [Torrent]) -> SessionStats {
        SessionStats(
            activeTorrentCount: torrents.filter { $0.status != 0 }.count,
            downloadSpeed: torrents.reduce(0) { $0 + $1.rateDownload },
            pausedTorrentCount: torrents.filter { $0.status == 0 }.count,
            torrentCount: torrents.count, uploadSpeed: torrents.reduce(0) { $0 + $1.rateUpload },
            cumulativeStats: TransmissionCumulativeStats(
                downloadedBytes: SampleLibrary.sessionDownloaded * 10, filesAdded: 412,
                secondsActive: 3_153_600, sessionCount: 86, uploadedBytes: SampleLibrary.sessionUploaded * 10
            ),
            currentStats: TransmissionCumulativeStats(
                downloadedBytes: SampleLibrary.sessionDownloaded, filesAdded: 7,
                secondsActive: 86_400, sessionCount: 1, uploadedBytes: SampleLibrary.sessionUploaded
            )
        )
    }
}
#endif
