//
//  TransmissionFunctions.swift
//  BitDream
//
//  Created by Austin Smith on 12/29/22.
//

import Foundation

var TOKEN_HEAD = "x-transmission-session-id"
public typealias TransmissionConfig = URLComponents
var lastSessionToken: String?
var url: TransmissionConfig?

public struct TransmissionAuth {
    let username: String
    let password: String
}

// MARK: - Core Request Functions

/// Core private request function that handles common functionality
private func sendRPCRequest<T: Codable>(
    method: String,
    requestBody: T,
    config: TransmissionConfig,
    auth: TransmissionAuth,
    retrying: Bool = false,
    responseHandler: @escaping (Data?, HTTPURLResponse?, Error?) -> Void
) {
    url = config
    url?.path = "/transmission/rpc"
    
    guard let req = buildRequest(requestBody: requestBody, auth: auth) else {
        responseHandler(nil, nil, NSError(domain: "com.bitdream.transmission", code: -1, 
                        userInfo: [NSLocalizedDescriptionKey: "Failed to build request - URL not configured"]))
        return
    }
    
    let task = URLSession.shared.dataTask(with: req) { (data, resp, error) in
        if let error = error {
            return responseHandler(nil, resp as? HTTPURLResponse, error)
        }
        
        let httpResp = resp as? HTTPURLResponse
        switch httpResp?.statusCode {
        case 409?: // If we get a 409, save the session token and try again
            authorize(httpResp: httpResp, ssl: (config.scheme == "https"))
            if !retrying {
                sendRPCRequest(method: method, requestBody: requestBody, 
                               config: config, auth: auth, retrying: true, 
                               responseHandler: responseHandler)
            } else {
                responseHandler(nil, httpResp, NSError(domain: "com.bitdream.transmission", code: 409, 
                                userInfo: [NSLocalizedDescriptionKey: "Session token error after retry"]))
            }
            return
        default:
            responseHandler(data, httpResp, error)
        }
    }
    task.resume()
}

/// For requests that return decoded data
private func executeAndDecodeRequest<T: Codable, R: Codable>(
    method: String,
    requestBody: T,
    config: TransmissionConfig,
    auth: TransmissionAuth,
    retrying: Bool = false,
    completion: @escaping (Result<R, Error>) -> Void
) {
    sendRPCRequest(method: method, requestBody: requestBody, config: config, auth: auth, retrying: retrying) { (data, resp, error) in
        if let error = error {
            return completion(.failure(error))
        }
        
        let httpResp = resp
        switch httpResp?.statusCode {
        case 401?:
            return completion(.failure(NSError(domain: "com.bitdream.transmission", code: 401, 
                              userInfo: [NSLocalizedDescriptionKey: "Unauthorized"])))
        case 200?:
            do {
                guard let data = data else {
                    throw NSError(domain: "com.bitdream.transmission", code: -1, 
                                 userInfo: [NSLocalizedDescriptionKey: "No data in response"])
                }
                let decoded = try JSONDecoder().decode(R.self, from: data)
                return completion(.success(decoded))
            } catch {
                return completion(.failure(error))
            }
        default:
            let errorMessage = data != nil ? String(decoding: data!, as: UTF8.self) : "Unknown error"
            completion(.failure(NSError(domain: "com.bitdream.transmission", code: httpResp?.statusCode ?? -1, 
                                userInfo: [NSLocalizedDescriptionKey: errorMessage])))
        }
    }
}

/// For requests that only need status
private func executeStatusOnlyRequest<T: Codable>(
    method: String,
    requestBody: T,
    config: TransmissionConfig,
    auth: TransmissionAuth,
    retrying: Bool = false,
    completion: @escaping (TransmissionResponse) -> Void
) {
    sendRPCRequest(method: method, requestBody: requestBody, config: config, auth: auth, retrying: retrying) { (data, resp, error) in
        if error != nil {
            return completion(TransmissionResponse.configError)
        }
        
        let httpResp = resp
        switch httpResp?.statusCode {
        case 401?:
            return completion(TransmissionResponse.unauthorized)
        case 200?:
            return completion(TransmissionResponse.success)
        default:
            return completion(TransmissionResponse.failed)
        }
    }
}

// MARK: - Generic API Method Factory

/// Generic method to perform any Transmission RPC action that returns data
public func performTransmissionDataRequest<Args: Codable, ResponseData: Codable>(
    method: String,
    args: Args,
    config: TransmissionConfig,
    auth: TransmissionAuth,
    completion: @escaping (Result<ResponseData, Error>) -> Void
) {
    let requestBody = TransmissionGenericRequest(method: method, arguments: args)
    executeAndDecodeRequest(
        method: method,
        requestBody: requestBody,
        config: config,
        auth: auth,
        completion: completion
    )
}

/// Generic method to perform any Transmission RPC action that only needs status
public func performTransmissionStatusRequest<Args: Codable>(
    method: String,
    args: Args,
    config: TransmissionConfig,
    auth: TransmissionAuth,
    completion: @escaping (TransmissionResponse) -> Void
) {
    let requestBody = TransmissionGenericRequest(method: method, arguments: args)
    executeStatusOnlyRequest(
        method: method,
        requestBody: requestBody,
        config: config,
        auth: auth,
        completion: completion
    )
}

// MARK: - Torrent Action Helper

/// Executes a torrent action on a specific torrent
/// - Parameters:
///   - actionMethod: The action method name (torrent-start, torrent-stop, etc.)
///   - torrentId: The ID of the torrent to perform the action on
///   - config: Server configuration
///   - auth: Authentication credentials
///   - onResponse: Callback with the server's response
private func executeTorrentAction(actionMethod: String, torrentId: Int, config: TransmissionConfig, auth: TransmissionAuth, onResponse: @escaping (TransmissionResponse) -> Void) {
    performTransmissionStatusRequest(
        method: actionMethod,
        args: ["ids": [torrentId]] as [String: [Int]],
        config: config,
        auth: auth,
        completion: onResponse
    )
}

// MARK: - API Functions

/// Makes a request to the server for a list of the currently running torrents
public func getTorrents(config: TransmissionConfig, auth: TransmissionAuth, onReceived: @escaping ([Torrent]?, String?) -> Void) -> Void {
    let fields: [String] = [
        "activityDate", "addedDate", "desiredAvailable", "error", "errorString", 
        "eta", "haveUnchecked", "haveValid", "id", "isFinished", "isStalled", 
        "labels", "leftUntilDone", "magnetLink", "metadataPercentComplete", 
        "name", "peersConnected", "peersGettingFromUs", "peersSendingToUs", 
        "percentDone", "rateDownload", "rateUpload", "sizeWhenDone", "totalSize", "status"
    ]
    
    performTransmissionDataRequest(
        method: "torrent-get",
        args: ["fields": fields] as StringListArguments,
        config: config,
        auth: auth
    ) { (result: Result<TransmissionGenericResponse<[String: [Torrent]]>, Error>) in
        switch result {
        case .success(let response):
            onReceived(response.arguments["torrents"], nil)
        case .failure(let error):
            onReceived(nil, error.localizedDescription)
        }
    }
}

public func getSessionStats(config: TransmissionConfig, auth: TransmissionAuth, onReceived: @escaping (SessionStats?, String?) -> Void) -> Void {
    performTransmissionDataRequest(
        method: "session-stats",
        args: EmptyArguments(),
        config: config,
        auth: auth
    ) { (result: Result<TransmissionGenericResponse<SessionStats>, Error>) in
        switch result {
        case .success(let response):
            onReceived(response.arguments, nil)
        case .failure(let error):
            onReceived(nil, error.localizedDescription)
        }
    }
}

/// Makes a request to the server containing either a base64 representation of a .torrent file or a magnet link
/// - Parameter fileUrl: Either a magnet link or base64 encoded file
/// - Parameter auth: A `TransmissionAuth` containing username and password for the server
/// - Parameter file: A boolean value; true if `fileUrl` is a base64 encoded file and false if `fileUrl` is a magnet link
/// - Parameter config: A `TransmissionConfig` containing the server's address and port
/// - Parameter onAdd: An escaping function that receives the servers response code represented as a `TransmissionResponse`
public func addTorrent(fileUrl: String, saveLocation: String, auth: TransmissionAuth, file: Bool, config: TransmissionConfig, onAdd: @escaping ((response: TransmissionResponse, transferId: Int)) -> Void) -> Void {
    // Create the torrent body based on the value of `fileUrl` and `file`
    let args: [String: String] = file ? 
        ["metainfo": fileUrl, "download-dir": saveLocation] : 
        ["filename": fileUrl, "download-dir": saveLocation]
    
    performTransmissionDataRequest(
        method: "torrent-add",
        args: args,
        config: config,
        auth: auth
    ) { (result: Result<TransmissionGenericResponse<[String: TorrentAddResponseArgs]>, Error>) in
        switch result {
        case .success(let response):
            if let torrentAdded = response.arguments["torrent-added"] {
                onAdd((TransmissionResponse.success, torrentAdded.id))
            } else {
                onAdd((TransmissionResponse.failed, 0))
            }
        case .failure(_):
            onAdd((TransmissionResponse.failed, 0))
        }
    }
}

/// Gets the list of files in a torrent
/// - Parameter transferId: The ID of the torrent to get files for
/// - Parameter info: A tuple containing the server config and auth info
/// - Parameter onReceived: A callback that receives the list of files and their stats
public func getTorrentFiles(transferId: Int, info: (config: TransmissionConfig, auth: TransmissionAuth), onReceived: @escaping ([TorrentFile], [TorrentFileStats])->(Void)) {
    let args = TorrentFilesRequestArgs(
        fields: ["files", "fileStats"],
        ids: [transferId]
    )
    
    performTransmissionDataRequest(
        method: "torrent-get",
        args: args,
        config: info.config,
        auth: info.auth
    ) { (result: Result<TransmissionGenericResponse<TorrentFilesResponseTorrents>, Error>) in
        switch result {
        case .success(let response):
            if let responseFiles = response.arguments.torrents.first?.files,
               let responseStats = response.arguments.torrents.first?.fileStats {
                onReceived(responseFiles, responseStats)
            } else {
                onReceived([], [])
            }
        case .failure(_):
            onReceived([], [])
        }
    }
}

/// Deletes a torrent from the queue
/// - Parameter torrent: The `Torrent` to be deleted
/// - Parameter erase: Whether or not to delete the downloaded data from the server along with the transfer in Transmssion
/// - Parameter config: A `TransmissionConfig` containing the server's address and port
/// - Parameter auth: A `TransmissionAuth` containing username and password for the server
/// - Parameter onDel: An escaping function that receives the server's response code as a `TransmissionResponse`
public func deleteTorrent(torrent: Torrent, erase: Bool, config: TransmissionConfig, auth: TransmissionAuth, onDel: @escaping (TransmissionResponse) -> Void) -> Void {
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

/// Model representing session information from the server
public struct SessionInfo {
    let downloadDir: String
    let version: String
    
    init(downloadDir: String = "unknown", version: String = "unknown") {
        self.downloadDir = downloadDir
        self.version = version
    }
}

/// Get the server's session information including download directory and version
/// - Parameter config: The server's config
/// - Parameter auth: The username and password for the server
/// - Parameter onResponse: An escaping function that receives session information from the server
public func getSession(config: TransmissionConfig, auth: TransmissionAuth, onResponse: @escaping (TransmissionSessionResponseArguments) -> Void) {
    performTransmissionDataRequest(
        method: "session-get",
        args: ["fields": ["download-dir", "version"]] as StringListArguments,
        config: config,
        auth: auth
    ) { (result: Result<TransmissionGenericResponse<TransmissionSessionResponseArguments>, Error>) in
        switch result {
        case .success(let response):
            onResponse(response.arguments)
        case .failure(_):
            onResponse(TransmissionSessionResponseArguments())
        }
    }
}

public func playPauseTorrent(torrent: Torrent, config: TransmissionConfig, auth: TransmissionAuth, onResponse: @escaping (TransmissionResponse) -> Void) {
    // If the torrent already has `stopped` status, start it. Otherwise, stop it.
    let actionMethod = torrent.status == TorrentStatus.stopped.rawValue ? "torrent-start" : "torrent-stop"
    executeTorrentAction(actionMethod: actionMethod, torrentId: torrent.id, config: config, auth: auth, onResponse: onResponse)
}

/// Play/Pause all active transfers
/// - Parameter start: True if we are starting all transfers, false if we are stopping them
/// - Parameter info: An info struct generated from makeConfig
/// - Parameter onResponse: Called when the request is complete
public func playPauseAllTorrents(start: Bool, info: (config: TransmissionConfig, auth: TransmissionAuth), onResponse: @escaping (TransmissionResponse) -> Void) {
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

public func verifyTorrent(torrent: Torrent, config: TransmissionConfig, auth: TransmissionAuth, onResponse: @escaping (TransmissionResponse) -> Void) {
    executeTorrentAction(actionMethod: "torrent-verify", torrentId: torrent.id, config: config, auth: auth, onResponse: onResponse)
}

/// Update torrent properties using the torrent-set method
/// - Parameter args: TorrentSetRequestArgs containing the properties and IDs to update
/// - Parameter info: Tuple containing server config and auth info
/// - Parameter onComplete: Called when the server's response is received
public func updateTorrent(args: TorrentSetRequestArgs, info: (config: TransmissionConfig, auth: TransmissionAuth), onComplete: @escaping (TransmissionResponse) -> Void) {
    performTransmissionStatusRequest(
        method: "torrent-set",
        args: args,
        config: info.config,
        auth: info.auth,
        completion: onComplete
    )
}

/// Gets the session-token from the response and sets it as the `lastSessionToken`
public func authorize(httpResp: HTTPURLResponse?, ssl: Bool) {
    TOKEN_HEAD = ssl ? TOKEN_HEAD : "X-Transmission-Session-Id" // Apparently it's different with SSL 🤦‍♂️
    if let headers = httpResp?.allHeaderFields {
        lastSessionToken = headers[TOKEN_HEAD] as? String
    }
}

/// Creates a `URLRequest` with provided body and TransmissionAuth
/// - Parameter requestBody: Any struct that conforms to `Codable` to be sent as the request body
/// - Parameter auth: The authorization values username and password to authorize the request with credentials
/// - Returns: A `URLRequest` with the provided body and auth values
private func buildRequest<T: Codable>(requestBody: T, auth: TransmissionAuth) -> URLRequest? {    
    // Create the request with auth values
    guard let url = url, let urlValue = url.url else {
        return nil
    }
    
    var req = URLRequest(url: urlValue)
    req.httpMethod = "POST"
    req.httpBody = try? JSONEncoder().encode(requestBody)
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue(lastSessionToken, forHTTPHeaderField: TOKEN_HEAD)
    let loginString = String(format: "%@:%@", auth.username, auth.password)
    let loginData = loginString.data(using: String.Encoding.utf8)!
    let base64LoginString = loginData.base64EncodedString()
    req.setValue("Basic \(base64LoginString)", forHTTPHeaderField: "Authorization")
    
    return req
}

public func startTorrentNow(torrent: Torrent, config: TransmissionConfig, auth: TransmissionAuth, onResponse: @escaping (TransmissionResponse) -> Void) {
    executeTorrentAction(actionMethod: "torrent-start-now", torrentId: torrent.id, config: config, auth: auth, onResponse: onResponse)
}

public func reAnnounceTorrent(torrent: Torrent, config: TransmissionConfig, auth: TransmissionAuth, onResponse: @escaping (TransmissionResponse) -> Void) {
    executeTorrentAction(actionMethod: "torrent-reannounce", torrentId: torrent.id, config: config, auth: auth, onResponse: onResponse)
}