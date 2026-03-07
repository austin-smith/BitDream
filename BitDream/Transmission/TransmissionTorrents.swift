import Foundation

internal struct TransmissionTorrentListQuerySpec: Sendable {
    let fields: [String]

    var arguments: StringListArguments {
        ["fields": fields]
    }
}

internal struct TransmissionTorrentDetailQuerySpec: Sendable {
    let fields: [String]
    let id: Int

    var arguments: TorrentFilesRequestArgs {
        TorrentFilesRequestArgs(fields: fields, ids: [id])
    }
}

internal enum TransmissionTorrentQuerySpec {
    static let torrentSummary = TransmissionTorrentListQuerySpec(fields: [
        "activityDate", "addedDate", "desiredAvailable", "error", "errorString",
        "eta", "haveUnchecked", "haveValid", "id", "isFinished", "isStalled",
        "labels", "leftUntilDone", "magnetLink", "metadataPercentComplete",
        "name", "peersConnected", "peersGettingFromUs", "peersSendingToUs",
        "percentDone", "primary-mime-type", "downloadDir", "queuePosition",
        "rateDownload", "rateUpload", "sizeWhenDone", "totalSize", "status",
        "uploadRatio", "uploadedEver", "downloadedEver"
    ])

    static let widgetSummary = TransmissionTorrentListQuerySpec(fields: [
        "activityDate", "addedDate", "desiredAvailable", "error", "errorString",
        "eta", "haveUnchecked", "haveValid", "id", "isFinished", "isStalled",
        "labels", "leftUntilDone", "magnetLink", "metadataPercentComplete",
        "name", "peersConnected", "peersGettingFromUs", "peersSendingToUs",
        "percentDone", "primary-mime-type", "downloadDir", "queuePosition",
        "rateDownload", "rateUpload", "sizeWhenDone", "totalSize", "status",
        "uploadRatio", "uploadedEver", "downloadedEver"
    ])

    static func torrentFiles(id: Int) -> TransmissionTorrentDetailQuerySpec {
        TransmissionTorrentDetailQuerySpec(fields: ["files", "fileStats"], id: id)
    }

    static func torrentPeers(id: Int) -> TransmissionTorrentDetailQuerySpec {
        TransmissionTorrentDetailQuerySpec(fields: ["peers", "peersFrom"], id: id)
    }

    static func torrentPieces(id: Int) -> TransmissionTorrentDetailQuerySpec {
        TransmissionTorrentDetailQuerySpec(fields: ["pieceCount", "pieceSize", "pieces"], id: id)
    }
}

internal extension TransmissionConnection {
    func fetchTorrentSummary() async throws -> [Torrent] {
        let response = try await sendRequiredArguments(
            method: "torrent-get",
            arguments: TransmissionTorrentQuerySpec.torrentSummary.arguments,
            responseType: TorrentListResponse.self
        )

        return response.torrents
    }

    func fetchWidgetSummary() async throws -> [Torrent] {
        let response = try await sendRequiredArguments(
            method: "torrent-get",
            arguments: TransmissionTorrentQuerySpec.widgetSummary.arguments,
            responseType: TorrentListResponse.self
        )

        return response.torrents
    }

    func fetchTorrentFiles(id: Int) async throws -> TorrentFilesResponseData {
        let response = try await sendRequiredArguments(
            method: "torrent-get",
            arguments: TransmissionTorrentQuerySpec.torrentFiles(id: id).arguments,
            responseType: TorrentFilesResponseTorrents.self
        )

        guard let torrent = response.torrents.first else {
            throw TransmissionError.invalidResponse
        }

        return torrent
    }

    func fetchTorrentPeers(id: Int) async throws -> TorrentPeersResponseData {
        let response = try await sendRequiredArguments(
            method: "torrent-get",
            arguments: TransmissionTorrentQuerySpec.torrentPeers(id: id).arguments,
            responseType: TorrentPeersResponseTorrents.self
        )

        guard let torrent = response.torrents.first else {
            throw TransmissionError.invalidResponse
        }

        return torrent
    }

    func fetchTorrentPieces(id: Int) async throws -> TorrentPiecesResponseData {
        let response = try await sendRequiredArguments(
            method: "torrent-get",
            arguments: TransmissionTorrentQuerySpec.torrentPieces(id: id).arguments,
            responseType: TorrentPiecesResponseTorrents.self
        )

        guard let torrent = response.torrents.first else {
            throw TransmissionError.invalidResponse
        }

        return torrent
    }
}
