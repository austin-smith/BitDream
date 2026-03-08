import Foundation

internal enum TransmissionTorrentQueueMoveDirection: Sendable {
    case top
    case upward
    case downward
    case bottom
}

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
    func addTorrent(
        fileURL: String,
        saveLocation: String,
        isTorrentFile: Bool
    ) async throws -> TransmissionTorrentAddOutcome {
        let arguments: StringArguments = isTorrentFile
            ? ["metainfo": fileURL, "download-dir": saveLocation]
            : ["filename": fileURL, "download-dir": saveLocation]

        return try await sendTorrentAdd(arguments: arguments)
    }

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

    func removeTorrents(ids: [Int], deleteLocalData: Bool) async throws {
        guard !ids.isEmpty else { return }

        try await sendStatusRequest(
            method: "torrent-remove",
            arguments: TransmissionRemoveRequestArgs(
                ids: ids,
                deleteLocalData: deleteLocalData
            )
        )
    }

    func pauseTorrents(ids: [Int]) async throws {
        try await performBatchTorrentAction(method: "torrent-stop", ids: ids)
    }

    func resumeTorrents(ids: [Int]) async throws {
        try await performBatchTorrentAction(method: "torrent-start", ids: ids)
    }

    func pauseAllTorrents() async throws {
        try await sendStatusRequest(
            method: "torrent-stop",
            arguments: EmptyArguments()
        )
    }

    func resumeAllTorrents() async throws {
        try await sendStatusRequest(
            method: "torrent-start",
            arguments: EmptyArguments()
        )
    }

    func startTorrentsNow(ids: [Int]) async throws {
        try await performBatchTorrentAction(method: "torrent-start-now", ids: ids)
    }

    func verifyTorrents(ids: [Int]) async throws {
        try await performBatchTorrentAction(method: "torrent-verify", ids: ids)
    }

    func reannounceTorrents(ids: [Int]) async throws {
        try await performBatchTorrentAction(method: "torrent-reannounce", ids: ids)
    }

    func updateTorrents(_ args: TorrentSetRequestArgs) async throws {
        guard !args.ids.isEmpty else { return }

        try await sendStatusRequest(
            method: "torrent-set",
            arguments: args
        )
    }

    func setTorrentPriority(ids: [Int], priority: TorrentPriority) async throws {
        try await updateTorrents(
            TorrentSetRequestArgs(ids: ids, priority: priority)
        )
    }

    func setTorrentLabels(ids: [Int], labels: [String]) async throws {
        guard !ids.isEmpty else { return }

        let normalizedLabels = labels.sorted()
        try await updateTorrents(
            TorrentSetRequestArgs(ids: ids, labels: normalizedLabels)
        )
    }

    func setFileWantedStatus(
        torrentID: Int,
        fileIndices: [Int],
        wanted: Bool
    ) async throws {
        guard !fileIndices.isEmpty else { return }

        var args = TorrentSetRequestArgs(ids: [torrentID])
        if wanted {
            args.filesWanted = fileIndices
        } else {
            args.filesUnwanted = fileIndices
        }

        try await updateTorrents(args)
    }

    func setFilePriority(
        torrentID: Int,
        fileIndices: [Int],
        priority: FilePriority
    ) async throws {
        guard !fileIndices.isEmpty else { return }

        var args = TorrentSetRequestArgs(ids: [torrentID])
        switch priority {
        case .low:
            args.priorityLow = fileIndices
        case .normal:
            args.priorityNormal = fileIndices
        case .high:
            args.priorityHigh = fileIndices
        }

        try await updateTorrents(args)
    }

    func setTorrentLocation(
        ids: [Int],
        location: String,
        move: Bool
    ) async throws {
        guard !ids.isEmpty else { return }

        try await sendStatusRequest(
            method: "torrent-set-location",
            arguments: TorrentSetLocationRequestArgs(
                ids: ids,
                location: location,
                move: move
            )
        )
    }

    func renameTorrentPath(
        torrentID: Int,
        path: String,
        newName: String
    ) async throws -> TorrentRenameResponseArgs {
        try await sendRequiredArguments(
            method: "torrent-rename-path",
            arguments: TorrentRenameRequestArgs(
                ids: [torrentID],
                path: path,
                name: newName
            ),
            responseType: TorrentRenameResponseArgs.self
        )
    }

    func queueMove(_ direction: TransmissionTorrentQueueMoveDirection, ids: [Int]) async throws {
        let method: String
        switch direction {
        case .top:
            method = "queue-move-top"
        case .upward:
            method = "queue-move-up"
        case .downward:
            method = "queue-move-down"
        case .bottom:
            method = "queue-move-bottom"
        }

        try await performBatchTorrentAction(method: method, ids: ids)
    }

    private func performBatchTorrentAction(method: String, ids: [Int]) async throws {
        guard !ids.isEmpty else { return }

        try await sendStatusRequest(
            method: method,
            arguments: TorrentIDsArgument(ids: ids)
        )
    }
}
