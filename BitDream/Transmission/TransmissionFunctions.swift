import Foundation

// TODO: Remove the remaining legacy adapter and callback wrapper surface in
// phases 4/5 once write/detail callers have migrated to `TransmissionConnection`
// and typed error presentation.
internal struct TransmissionLegacyAdapter: Sendable {
    private let factory: TransmissionConnectionFactory

    init(factory: TransmissionConnectionFactory = TransmissionConnectionFactory()) {
        self.factory = factory
    }

    init(
        transport: TransmissionTransport = TransmissionTransport(),
        credentialResolver: TransmissionCredentialResolver = .live
    ) {
        self.factory = TransmissionConnectionFactory(
            transport: transport,
            credentialResolver: credentialResolver
        )
    }

    func performDataRequest<Args: Codable & Sendable, ResponseData: Codable & Sendable>(
        method: String,
        args: Args,
        config: TransmissionConfig,
        auth: TransmissionAuth,
        responseType: ResponseData.Type = ResponseData.self
    ) async -> Result<ResponseData, Error> {
        do {
            let connection = try await connection(for: config, auth: auth)
            let responseData = try await connection.sendRequiredArguments(
                method: method,
                arguments: args,
                responseType: responseType
            )
            return .success(responseData)
        } catch {
            return .failure(TransmissionLegacyCompatibility.localizedError(from: error))
        }
    }

    func performStatusRequest<Args: Codable & Sendable>(
        method: String,
        args: Args,
        config: TransmissionConfig,
        auth: TransmissionAuth
    ) async -> TransmissionResponse {
        do {
            let connection = try await connection(for: config, auth: auth)
            try await connection.sendStatusRequest(
                method: method,
                arguments: args
            )
            return .success
        } catch {
            return TransmissionLegacyCompatibility.response(from: error)
        }
    }

    func performTorrentAddRequest(
        args: StringArguments,
        config: TransmissionConfig,
        auth: TransmissionAuth
    ) async -> (response: TransmissionResponse, transferId: Int) {
        do {
            let connection = try await connection(for: config, auth: auth)
            let outcome = try await connection.sendTorrentAdd(arguments: args)

            switch outcome {
            case .added(let torrent), .duplicate(let torrent):
                return (.success, torrent.id)
            }
        } catch {
            return (TransmissionLegacyCompatibility.response(from: error), 0)
        }
    }

    func fetchTorrentFiles(
        transferID: Int,
        config: TransmissionConfig,
        auth: TransmissionAuth
    ) async -> Result<TorrentFilesResponseData, Error> {
        await performQuery(config: config, auth: auth) { connection in
            try await connection.fetchTorrentFiles(id: transferID)
        }
    }

    func fetchTorrentPeers(
        transferID: Int,
        config: TransmissionConfig,
        auth: TransmissionAuth
    ) async -> Result<TorrentPeersResponseData, Error> {
        await performQuery(config: config, auth: auth) { connection in
            try await connection.fetchTorrentPeers(id: transferID)
        }
    }

    func fetchTorrentPieces(
        transferID: Int,
        config: TransmissionConfig,
        auth: TransmissionAuth
    ) async -> Result<TorrentPiecesResponseData, Error> {
        await performQuery(config: config, auth: auth) { connection in
            try await connection.fetchTorrentPieces(id: transferID)
        }
    }

    private func connection(
        for config: TransmissionConfig,
        auth: TransmissionAuth
    ) async throws -> TransmissionConnection {
        try await factory.connection(for: TransmissionConnectionDescriptor(config: config, auth: auth))
    }

    private func performQuery<Success: Sendable>(
        config: TransmissionConfig,
        auth: TransmissionAuth,
        operation: (TransmissionConnection) async throws -> Success
    ) async -> Result<Success, Error> {
        do {
            let connection = try await connection(for: config, auth: auth)
            return .success(try await operation(connection))
        } catch {
            return .failure(TransmissionLegacyCompatibility.localizedError(from: error))
        }
    }
}

private let legacyTransmissionAdapter = TransmissionLegacyAdapter()

// MARK: - Generic API Method Factory

/// Generic method to perform any Transmission RPC action that returns data
public func performTransmissionDataRequest<Args: Codable & Sendable, ResponseData: Codable & Sendable>(
    method: String,
    args: Args,
    config: TransmissionConfig,
    auth: TransmissionAuth,
    completion: @MainActor @escaping (Result<ResponseData, Error>) -> Void
) {
    Task {
        let result = await legacyTransmissionAdapter.performDataRequest(
            method: method,
            args: args,
            config: config,
            auth: auth,
            responseType: ResponseData.self
        )
        await completion(result)
    }
}

/// Generic method to perform any Transmission RPC action that only needs status
public func performTransmissionStatusRequest<Args: Codable & Sendable>(
    method: String,
    args: Args,
    config: TransmissionConfig,
    auth: TransmissionAuth,
    completion: @MainActor @escaping (TransmissionResponse) -> Void
) {
    Task {
        let response = await legacyTransmissionAdapter.performStatusRequest(
            method: method,
            args: args,
            config: config,
            auth: auth
        )
        await completion(response)
    }
}

// MARK: - Torrent Action Helper

/// Executes a torrent action on a specific torrent
/// - Parameters:
///   - actionMethod: The action method name (torrent-start, torrent-stop, etc.)
///   - torrentId: The ID of the torrent to perform the action on
///   - config: Server configuration
///   - auth: Authentication credentials
///   - onResponse: Callback with the server's response
private func executeTorrentAction(actionMethod: String, torrentId: Int, config: TransmissionConfig, auth: TransmissionAuth, onResponse: @MainActor @escaping (TransmissionResponse) -> Void) {
    performTransmissionStatusRequest(
        method: actionMethod,
        args: ["ids": [torrentId]] as [String: [Int]],
        config: config,
        auth: auth,
        completion: onResponse
    )
}

// MARK: - API Functions

// TODO: Revisit this signature and reduce parameter count.
// swiftlint:disable function_parameter_count
/// Makes a request to the server containing either a base64 representation of a .torrent file or a magnet link
/// - Parameter fileUrl: Either a magnet link or base64 encoded file
/// - Parameter auth: A `TransmissionAuth` containing username and password for the server
/// - Parameter file: A boolean value; true if `fileUrl` is a base64 encoded file and false if `fileUrl` is a magnet link
/// - Parameter config: A `TransmissionConfig` containing the server's address and port
/// - Parameter onAdd: An escaping function that receives the servers response code represented as a `TransmissionResponse`
public func addTorrent(
    fileUrl: String,
    saveLocation: String,
    auth: TransmissionAuth,
    file: Bool,
    config: TransmissionConfig,
    onAdd: @MainActor @escaping ((response: TransmissionResponse, transferId: Int)) -> Void
) {
    // Create the torrent body based on the value of `fileUrl` and `file`
    let args: [String: String] = file ?
        ["metainfo": fileUrl, "download-dir": saveLocation] :
        ["filename": fileUrl, "download-dir": saveLocation]

    Task {
        let result = await legacyTransmissionAdapter.performTorrentAddRequest(
            args: args,
            config: config,
            auth: auth
        )
        await onAdd(result)
    }
}
// swiftlint:enable function_parameter_count

/// Gets the list of files in a torrent
/// - Parameter transferId: The ID of the torrent to get files for
/// - Parameter info: A tuple containing the server config and auth info
/// - Parameter onReceived: A callback that receives the list of files and their stats
public func getTorrentFiles(transferId: Int, info: (config: TransmissionConfig, auth: TransmissionAuth), onReceived: @MainActor @escaping ([TorrentFile], [TorrentFileStats]) -> Void) {
    Task {
        let result = await legacyTransmissionAdapter.fetchTorrentFiles(
            transferID: transferId,
            config: info.config,
            auth: info.auth
        )

        switch result {
        case .success(let response):
            await onReceived(response.files, response.fileStats)
        case .failure:
            await onReceived([], [])
        }
    }
}

/// Deletes a torrent from the queue
/// - Parameter torrent: The `Torrent` to be deleted
/// - Parameter erase: Whether or not to delete the downloaded data from the server along with the transfer in Transmssion
/// - Parameter config: A `TransmissionConfig` containing the server's address and port
/// - Parameter auth: A `TransmissionAuth` containing username and password for the server
/// - Parameter onDel: An escaping function that receives the server's response code as a `TransmissionResponse`
public func deleteTorrent(torrent: Torrent, erase: Bool, config: TransmissionConfig, auth: TransmissionAuth, onDel: @MainActor @escaping (TransmissionResponse) -> Void) {
    let args = TransmissionRemoveRequestArgs(
        ids: [torrent.id],
        deleteLocalData: erase
    )

    performTransmissionStatusRequest(
        method: "torrent-remove",
        args: args,
        config: config,
        auth: auth,
        completion: onDel
    )
}

public func playPauseTorrent(torrent: Torrent, config: TransmissionConfig, auth: TransmissionAuth, onResponse: @MainActor @escaping (TransmissionResponse) -> Void) {
    // If the torrent already has `stopped` status, start it. Otherwise, stop it.
    let actionMethod = torrent.status == TorrentStatus.stopped.rawValue ? "torrent-start" : "torrent-stop"
    executeTorrentAction(actionMethod: actionMethod, torrentId: torrent.id, config: config, auth: auth, onResponse: onResponse)
}

/// Play/Pause all active transfers
/// - Parameter start: True if we are starting all transfers, false if we are stopping them
/// - Parameter info: An info struct generated from makeConfig
/// - Parameter onResponse: Called when the request is complete
public func playPauseAllTorrents(start: Bool, info: (config: TransmissionConfig, auth: TransmissionAuth), onResponse: @MainActor @escaping (TransmissionResponse) -> Void) {
    // If the torrent already has `stopped` status, start it. Otherwise, stop it.
    let method = start ? "torrent-start" : "torrent-stop"

    performTransmissionStatusRequest(
        method: method,
        args: EmptyArguments(),
        config: info.config,
        auth: info.auth,
        completion: onResponse
    )
}

/// Pause multiple torrents by IDs
public func pauseTorrents(
    ids: [Int],
    info: (config: TransmissionConfig, auth: TransmissionAuth),
    onResponse: @MainActor @escaping (TransmissionResponse) -> Void
) {
    performTransmissionStatusRequest(
        method: "torrent-stop",
        args: ["ids": ids] as [String: [Int]],
        config: info.config,
        auth: info.auth,
        completion: onResponse
    )
}

/// Resume multiple torrents by IDs
public func resumeTorrents(
    ids: [Int],
    info: (config: TransmissionConfig, auth: TransmissionAuth),
    onResponse: @MainActor @escaping (TransmissionResponse) -> Void
) {
    performTransmissionStatusRequest(
        method: "torrent-start",
        args: ["ids": ids] as [String: [Int]],
        config: info.config,
        auth: info.auth,
        completion: onResponse
    )
}

public func verifyTorrent(torrent: Torrent, config: TransmissionConfig, auth: TransmissionAuth, onResponse: @MainActor @escaping (TransmissionResponse) -> Void) {
    executeTorrentAction(actionMethod: "torrent-verify", torrentId: torrent.id, config: config, auth: auth, onResponse: onResponse)
}

/// Update torrent properties using the torrent-set method
/// - Parameter args: TorrentSetRequestArgs containing the properties and IDs to update
/// - Parameter info: Tuple containing server config and auth info
/// - Parameter onComplete: Called when the server's response is received
public func updateTorrent(args: TorrentSetRequestArgs, info: (config: TransmissionConfig, auth: TransmissionAuth), onComplete: @MainActor @escaping (TransmissionResponse) -> Void) {
    performTransmissionStatusRequest(
        method: "torrent-set",
        args: args,
        config: info.config,
        auth: info.auth,
        completion: onComplete
    )
}

public func startTorrentNow(torrent: Torrent, config: TransmissionConfig, auth: TransmissionAuth, onResponse: @MainActor @escaping (TransmissionResponse) -> Void) {
    executeTorrentAction(actionMethod: "torrent-start-now", torrentId: torrent.id, config: config, auth: auth, onResponse: onResponse)
}

public func reAnnounceTorrent(torrent: Torrent, config: TransmissionConfig, auth: TransmissionAuth, onResponse: @MainActor @escaping (TransmissionResponse) -> Void) {
    executeTorrentAction(actionMethod: "torrent-reannounce", torrentId: torrent.id, config: config, auth: auth, onResponse: onResponse)
}

// MARK: - File Operation Functions

/// Set wanted status for specific files in a torrent
public func setFileWantedStatus(
    torrentId: Int,
    fileIndices: [Int],
    wanted: Bool,
    info: (config: TransmissionConfig, auth: TransmissionAuth),
    completion: @MainActor @escaping (TransmissionResponse) -> Void
) {
    var args = TorrentSetRequestArgs(ids: [torrentId])
    if wanted {
        args.filesWanted = fileIndices
    } else {
        args.filesUnwanted = fileIndices
    }

    updateTorrent(args: args, info: info, onComplete: completion)
}

/// Move or relocate torrent data on the server
/// - Parameters:
///   - args: TorrentSetLocationRequestArgs with ids, destination location, and move flag
///   - info: Tuple containing server config and auth info
///   - completion: Called with TransmissionResponse status
public func setTorrentLocation(
    args: TorrentSetLocationRequestArgs,
    info: (config: TransmissionConfig, auth: TransmissionAuth),
    completion: @MainActor @escaping (TransmissionResponse) -> Void
) {
    performTransmissionStatusRequest(
        method: "torrent-set-location",
        args: args,
        config: info.config,
        auth: info.auth,
        completion: completion
    )
}

// TODO: Revisit this signature and reduce parameter count.
// swiftlint:disable function_parameter_count
/// Rename a path (file or folder) within a torrent
/// - Parameters:
///   - torrentId: The torrent ID (Transmission expects exactly one id)
///   - path: The current path (relative to torrent root) to rename. For renaming the torrent root, pass the torrent name.
///   - newName: The new name for the path component
///   - config: Server configuration
///   - auth: Authentication credentials
///   - completion: Result containing the server's rename response args or an error
public func renameTorrentPath(
    torrentId: Int,
    path: String,
    newName: String,
    config: TransmissionConfig,
    auth: TransmissionAuth,
    completion: @MainActor @escaping (Result<TorrentRenameResponseArgs, Error>) -> Void
) {
    let args = TorrentRenameRequestArgs(ids: [torrentId], path: path, name: newName)
    performTransmissionDataRequest(
        method: "torrent-rename-path",
        args: args,
        config: config,
        auth: auth,
        completion: { (result: Result<TorrentRenameResponseArgs, Error>) in
            switch result {
            case .success(let response):
                completion(.success(response))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    )
}
// swiftlint:enable function_parameter_count

/// Set priority for specific files in a torrent
public func setFilePriority(
    torrentId: Int,
    fileIndices: [Int],
    priority: FilePriority,
    info: (config: TransmissionConfig, auth: TransmissionAuth),
    completion: @MainActor @escaping (TransmissionResponse) -> Void
) {
    var args = TorrentSetRequestArgs(ids: [torrentId])

    switch priority {
    case .low: args.priorityLow = fileIndices
    case .normal: args.priorityNormal = fileIndices
    case .high: args.priorityHigh = fileIndices
    }

    updateTorrent(args: args, info: info, onComplete: completion)
}

// MARK: - Queue Management Functions

/// Move torrents to the top of the queue
/// - Parameters:
///   - ids: Array of torrent IDs to move
///   - info: Tuple containing server config and auth info
///   - completion: Called when the server's response is received
public func queueMoveTop(
    ids: [Int],
    info: (config: TransmissionConfig, auth: TransmissionAuth),
    completion: @MainActor @escaping (TransmissionResponse) -> Void
) {
    performTransmissionStatusRequest(
        method: "queue-move-top",
        args: ["ids": ids] as [String: [Int]],
        config: info.config,
        auth: info.auth,
        completion: completion
    )
}

/// Move torrents up one position in the queue
/// - Parameters:
///   - ids: Array of torrent IDs to move
///   - info: Tuple containing server config and auth info
///   - completion: Called when the server's response is received
public func queueMoveUp(
    ids: [Int],
    info: (config: TransmissionConfig, auth: TransmissionAuth),
    completion: @MainActor @escaping (TransmissionResponse) -> Void
) {
    performTransmissionStatusRequest(
        method: "queue-move-up",
        args: ["ids": ids] as [String: [Int]],
        config: info.config,
        auth: info.auth,
        completion: completion
    )
}

/// Move torrents down one position in the queue
/// - Parameters:
///   - ids: Array of torrent IDs to move
///   - info: Tuple containing server config and auth info
///   - completion: Called when the server's response is received
public func queueMoveDown(
    ids: [Int],
    info: (config: TransmissionConfig, auth: TransmissionAuth),
    completion: @MainActor @escaping (TransmissionResponse) -> Void
) {
    performTransmissionStatusRequest(
        method: "queue-move-down",
        args: ["ids": ids] as [String: [Int]],
        config: info.config,
        auth: info.auth,
        completion: completion
    )
}

/// Move torrents to the bottom of the queue
/// - Parameters:
///   - ids: Array of torrent IDs to move
///   - info: Tuple containing server config and auth info
///   - completion: Called when the server's response is received
public func queueMoveBottom(
    ids: [Int],
    info: (config: TransmissionConfig, auth: TransmissionAuth),
    completion: @MainActor @escaping (TransmissionResponse) -> Void
) {
    performTransmissionStatusRequest(
        method: "queue-move-bottom",
        args: ["ids": ids] as [String: [Int]],
        config: info.config,
        auth: info.auth,
        completion: completion
    )
}

// MARK: - Peer Queries

/// Gets the list of peers (and peersFrom breakdown) for a torrent
/// - Parameters:
///   - transferId: The ID of the torrent
///   - info: Tuple containing server config and auth info
///   - onReceived: Callback providing peers and optional peersFrom breakdown
public func getTorrentPeers(
    transferId: Int,
    info: (config: TransmissionConfig, auth: TransmissionAuth),
    onReceived: @MainActor @escaping (_ peers: [Peer], _ peersFrom: PeersFrom?) -> Void
) {
    Task {
        let result = await legacyTransmissionAdapter.fetchTorrentPeers(
            transferID: transferId,
            config: info.config,
            auth: info.auth
        )

        switch result {
        case .success(let response):
            await onReceived(response.peers, response.peersFrom)
        case .failure:
            await onReceived([], nil)
        }
    }
}

// MARK: - Pieces Queries

/// Gets the pieces bitfield and metadata for a torrent
/// - Parameters:
///   - transferId: The ID of the torrent
///   - info: Tuple containing server config and auth info
///   - onReceived: Callback providing pieceCount, pieceSize, and base64-encoded pieces bitfield
public func getTorrentPieces(
    transferId: Int,
    info: (config: TransmissionConfig, auth: TransmissionAuth),
    onReceived: @MainActor @escaping (_ pieceCount: Int, _ pieceSize: Int64, _ piecesBitfieldBase64: String) -> Void
) {
    Task {
        let result = await legacyTransmissionAdapter.fetchTorrentPieces(
            transferID: transferId,
            config: info.config,
            auth: info.auth
        )

        switch result {
        case .success(let response):
            await onReceived(response.pieceCount, response.pieceSize, response.pieces)
        case .failure:
            await onReceived(0, 0, "")
        }
    }
}
