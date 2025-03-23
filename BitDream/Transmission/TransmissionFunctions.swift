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

public struct TransmissionAuth {
    let username: String
    let password: String
}

/// A standard request containing a list of string-only arguments.
struct TransmissionRequest: Codable {
    let method: String
    let arguments: [String: String]
}

/// A request sent to the server asking for a list of torrents and certain properties
struct TransmissionListRequest: Codable {
    let method: String
    let arguments: [String: [String]]
}

/// A response from the server sent after a torrent-get request
struct TransmissionListResponse: Codable {
    let arguments: [String: [Torrent]]
}

/// Makes a request to the server for a list of the currently running torrents
public func getTorrents(config: TransmissionConfig, auth: TransmissionAuth, onReceived: @escaping ([Torrent]?, String?) -> Void) -> Void {
    url = config
    url?.path = "/transmission/rpc"
    
    let requestBody = TransmissionListRequest(
        method: "torrent-get",
        arguments: [
            "fields": ["activityDate", "addedDate", "desiredAvailable", "error", "errorString", "eta", "haveUnchecked", "haveValid", "id", "isFinished", "isStalled", "labels", "leftUntilDone", "magnetLink", "metadataPercentComplete", "name", "peersConnected", "peersGettingFromUs", "peersSendingToUs", "percentDone", "rateDownload", "rateUpload", "sizeWhenDone", "totalSize", "status" ]
        ]
    )
    
    guard let req = buildRequest(requestBody: requestBody, auth: auth) else {
        onReceived(nil, "Failed to build request - URL not configured")
        return
    }
    
    // Send the request
    let task = URLSession.shared.dataTask(with: req) { (data, resp, error) in
        if error != nil {
            return onReceived(nil, error.debugDescription)
        }
        let httpResp = resp as? HTTPURLResponse
        switch httpResp?.statusCode {
        case 409?: // If we get a 409, save the session token and try again
            authorize(httpResp: httpResp, ssl: (config.scheme == "https"))
            getTorrents(config: config, auth: auth, onReceived: onReceived)
            return
        case 200?:
            let response = try? JSONDecoder().decode(TransmissionListResponse.self, from: data!)
            let torrents = response?.arguments["torrents"]
            
            return onReceived(torrents, nil)
        default:
            return onReceived(nil, String(decoding: data!, as: UTF8.self))
        }
    }
    task.resume()
}

struct TransmissionSessionStatsResponse: Codable {
    let arguments: SessionStats
}

public func getSessionStats(config: TransmissionConfig, auth: TransmissionAuth, onReceived: @escaping (SessionStats?, String?) -> Void) -> Void {
    url = config
    url?.path = "/transmission/rpc"
    
    let requestBody = TransmissionListRequest(
        method: "session-stats",
        arguments: [:]
    )
    
    guard let req = buildRequest(requestBody: requestBody, auth: auth) else {
        onReceived(nil, "Failed to build request - URL not configured")
        return
    }
    
    // Send the request
    let task = URLSession.shared.dataTask(with: req) { (data, resp, error) in
        if error != nil {
            return onReceived(nil, error.debugDescription)
        }
        let httpResp = resp as? HTTPURLResponse
        switch httpResp?.statusCode {
        case 409?: // If we get a 409, save the session token and try again
            authorize(httpResp: httpResp, ssl: (config.scheme == "https"))
            getSessionStats(config: config, auth: auth, onReceived: onReceived)
            return
        case 200?:
            let response = try? JSONDecoder().decode(TransmissionSessionStatsResponse.self, from: data!)
            let sessionStats = response?.arguments
            
            return onReceived(sessionStats, nil)
        default:
            return onReceived(nil, String(decoding: data!, as: UTF8.self))
        }
    }
    task.resume()
}

struct TorrentAddResponseArgs: Codable {
    var hashString: String
    var id: Int
    var name: String
}

struct TorrentAddResponse: Codable {
    var arguments: [String: TorrentAddResponseArgs]
}

/// Makes a request to the server containing either a base64 representation of a .torrent file or a magnet link
/// - Parameter fileUrl: Either a magnet link or base64 encoded file
/// - Parameter auth: A `TransmissionAuth` containing username and password for the server
/// - Parameter file: A boolean value; true if `fileUrl` is a base64 encoded file and false if `fileUrl` is a magnet link
/// - Parameter config: A `TransmissionConfig` containing the server's address and port
/// - Parameter onAdd: An escaping function that receives the servers response code represented as a `TransmissionResponse`
public func addTorrent(fileUrl: String, saveLocation: String, auth: TransmissionAuth, file: Bool, config: TransmissionConfig, onAdd: @escaping ((response: TransmissionResponse, transferId: Int)) -> Void) -> Void {
    url = config
    url?.path = "/transmission/rpc"
    
    // Create the torrent body based on the value of `fileUrl` and `file`
    let requestBody = file ? TransmissionRequest(
        method: "torrent-add",
        arguments: ["metainfo": fileUrl, "download-dir": saveLocation]
    ) : TransmissionRequest(
        method: "torrent-add",
        arguments: ["filename": fileUrl, "download-dir": saveLocation]
    )
    
    guard let req = buildRequest(requestBody: requestBody, auth: auth) else {
        onAdd((TransmissionResponse.configError, 0))
        return
    }
    
    // Send request to server
    let task = URLSession.shared.dataTask(with: req) { (data, resp, error) in
        if error != nil {
            return onAdd((TransmissionResponse.configError, 0))
        }
        
        let httpResp = resp as? HTTPURLResponse
        // Call `onAdd` with the status code
        switch httpResp?.statusCode {
        case 409?: // If we get a 409, save the token and try again
            authorize(httpResp: httpResp, ssl: (config.scheme == "https"))
            addTorrent(fileUrl: fileUrl, saveLocation: saveLocation, auth: auth, file: file, config: config, onAdd: onAdd)
            return
        case 401?:
            return onAdd((TransmissionResponse.unauthorized, 0))
        case 200?:
            let response = try? JSONDecoder().decode(TorrentAddResponse.self, from: data!)
            
            // Safely unwrap the response and extract the transfer ID
            if let response = response, 
               let torrentAdded = response.arguments["torrent-added"] {
                return onAdd((TransmissionResponse.success, torrentAdded.id))
            } else {
                // If we can't get the transfer ID, print the response for debugging
                if let responseData = data {
                    print("Unexpected response format: \(String(data: responseData, encoding: .utf8) ?? "Unable to decode response")")
                }
                return onAdd((TransmissionResponse.failed, 0))
            }
        default:
            return onAdd((TransmissionResponse.failed, 0))
        }
    }
    task.resume()
}

struct TorrentFilesRequestArgs: Codable {
    var fields: [String]
    var ids: [Int]
}

struct TorrentFilesRequest: Codable {
    var method: String
    var arguments: TorrentFilesRequestArgs
}

struct TorrentFilesResponseFiles: Codable {
    let files: [TorrentFile]
    let fileStats: [TorrentFileStats]
}

struct TorrentFilesResponseTorrents: Codable {
    let torrents: [TorrentFilesResponseFiles]
}

struct TorrentFilesResponse: Codable {
    let arguments: TorrentFilesResponseTorrents
}

/// Gets the list of files in a torrent
/// - Parameter transferId: The ID of the torrent to get files for
/// - Parameter info: A tuple containing the server config and auth info
/// - Parameter onReceived: A callback that receives the list of files and their stats
public func getTorrentFiles(transferId: Int, info: (config: TransmissionConfig, auth: TransmissionAuth), onReceived: @escaping ([TorrentFile], [TorrentFileStats])->(Void)) {
    url = info.config
    url?.path = "/transmission/rpc"
    
    let requestBody = TorrentFilesRequest(
        method: "torrent-get",
        arguments: TorrentFilesRequestArgs(
            fields: ["files", "fileStats"],
            ids: [transferId]
        )
    )
    
    guard let req = buildRequest(requestBody: requestBody, auth: info.auth) else {
        onReceived([], [])
        return
    }
    
    let task = URLSession.shared.dataTask(with: req) { (data, resp, error) in
        if error != nil {
            return onReceived([], [])
        }
        
        let httpResp = resp as? HTTPURLResponse
        switch httpResp?.statusCode {
        case 409?: // If we get a 409, save the session token and try again
            authorize(httpResp: httpResp, ssl: (info.config.scheme == "https"))
            getTorrentFiles(transferId: transferId, info: info, onReceived: onReceived)
            return
        case 200?:
            let response = try? JSONDecoder().decode(TorrentFilesResponse.self, from: data!)
            if let responseFiles = response?.arguments.torrents.first?.files,
               let responseStats = response?.arguments.torrents.first?.fileStats {
                return onReceived(responseFiles, responseStats)
            } else {
                return onReceived([], [])
            }
        default:
            return onReceived([], [])
        }
    }
    task.resume()
}

/// The remove body is weird and the delete-local-data argument has hyphens in it
/// so we need **another** dictionary with `CodingKeys` to make it work
struct TransmissionRemoveRequestArgs: Codable {
    var ids: [Int]
    var deleteLocalData: Bool
    
    enum CodingKeys: String, CodingKey {
        case ids
        case deleteLocalData = "delete-local-data"
    }
}

struct TransmissionRemoveRequest: Codable {
    var method: String
    var arguments: TransmissionRemoveRequestArgs
}

/// Deletes a torrent from the queue
/// - Parameter torrent: The `Torrent` to be deleted
/// - Parameter erase: Whether or not to delete the downloaded data from the server along with the transfer in Transmssion
/// - Parameter config: A `TransmissionConfig` containing the server's address and port
/// - Parameter auth: A `TransmissionAuth` containing username and password for the server
/// - Parameter onDel: An escaping function that receives the server's response code as a `TransmissionResponse`
public func deleteTorrent(torrent: Torrent, erase: Bool, config: TransmissionConfig, auth: TransmissionAuth, onDel: @escaping (TransmissionResponse) -> Void) -> Void {
    url = config
    url?.path = "/transmission/rpc"
    
    let requestBody = TransmissionRemoveRequest(
        method: "torrent-remove",
        arguments: TransmissionRemoveRequestArgs(
            ids: [torrent.id],
            deleteLocalData: erase
        )
    )
    
    guard let req = buildRequest(requestBody: requestBody, auth: auth) else {
        onDel(TransmissionResponse.configError)
        return
    }
    
    // Send request to server
    let task = URLSession.shared.dataTask(with: req) { (data, resp, error) in
        if error != nil {
            return onDel(TransmissionResponse.configError)
        }
        
        let httpResp = resp as? HTTPURLResponse
        // Call `onAdd` with the status code
        switch httpResp?.statusCode {
        case 409?: // If we get a 409, save the token and try again
            authorize(httpResp: httpResp, ssl: (config.scheme == "https"))
            deleteTorrent(torrent: torrent, erase: erase, config: config, auth: auth, onDel: onDel)
            return
        case 401?:
            return onDel(TransmissionResponse.unauthorized)
        case 200?:
            return onDel(TransmissionResponse.success)
        default:
            return onDel(TransmissionResponse.failed)
        }
    }
    task.resume()
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
    url = config
    url?.path = "/transmission/rpc"
    
    let requestBody = TransmissionListRequest(
        method: "session-get",
        arguments: [
            "fields": ["download-dir", "version"]
        ]
    )
    
    guard let req = buildRequest(requestBody: requestBody, auth: auth) else {
        onResponse(TransmissionSessionResponseArguments())
        return
    }
    
    let task = URLSession.shared.dataTask(with: req) { (data, resp, error) in
        if error != nil {
            return onResponse(TransmissionSessionResponseArguments())
        }
        
        let httpResp = resp as? HTTPURLResponse
        // Call `onAdd` with the status code
        switch httpResp?.statusCode {
        case 409?: // If we get a 409, save the token and try again
            authorize(httpResp: httpResp, ssl: (config.scheme == "https"))
            getSession(config: config, auth: auth, onResponse: onResponse)
            return
        case 401?:
            return onResponse(TransmissionSessionResponseArguments())
        case 200?:
            let response = try? JSONDecoder().decode(TransmissionSessionResponse.self, from: data!)
            return onResponse(
                response?.arguments ?? TransmissionSessionResponseArguments()
            )
        default:
            return onResponse(TransmissionSessionResponseArguments())
        }
    }
    task.resume()
}

/// A torrent action request
/// - Parameter method: One of [torrent-start, torrent-stop]. See RPC-Spec
/// - Parameter arguments: A list of torrent ids to perform the action on
struct TorrentActionRequest: Codable {
    let method: String
    let arguments: [String: [Int]]
}

public func playPauseTorrent(torrent: Torrent, config: TransmissionConfig, auth: TransmissionAuth, onResponse: @escaping (TransmissionResponse) -> Void) {
    url = config
    url?.path = "/transmission/rpc"
    
    // If the torrent already has `stopped` status, start it. Otherwise, stop it.
    let requestBody = torrent.status == TorrentStatus.stopped.rawValue ? TorrentActionRequest(
        method: "torrent-start",
        arguments: ["ids": [torrent.id]]
    ) : TorrentActionRequest(
        method: "torrent-stop",
        arguments: ["ids": [torrent.id]]
    )
    
    guard let req = buildRequest(requestBody: requestBody, auth: auth) else {
        onResponse(TransmissionResponse.configError)
        return
    }
    
    let task = URLSession.shared.dataTask(with: req) { (data, resp, err) in
        if err != nil {
            onResponse(TransmissionResponse.configError)
        }
        
        let httpResp = resp as? HTTPURLResponse
        // Call `onAdd` with the status code
        switch httpResp?.statusCode {
        case 409?: // If we get a 409, save the token and try again
            authorize(httpResp: httpResp, ssl: (config.scheme == "https"))
            playPauseTorrent(torrent: torrent, config: config, auth: auth, onResponse: onResponse)
            return
        case 401?:
            return onResponse(TransmissionResponse.unauthorized)
        case 200?:
            return onResponse(TransmissionResponse.success)
        default:
            return onResponse(TransmissionResponse.failed)
        }
    }
    task.resume()
}

/// Play/Pause all active transfers
/// - Parameter start: True if we are starting all transfers, false if we are stopping them
/// - Parameter info: An info struct generated from makeConfig
/// - Parameter onResponse: Called when the request is complete
public func playPauseAllTorrents(start: Bool, info: (config: TransmissionConfig, auth: TransmissionAuth), onResponse: @escaping (TransmissionResponse) -> Void) {
    url = info.config
    url?.path = "/transmission/rpc"
    
    // If the torrent already has `stopped` status, start it. Otherwise, stop it.
    let requestBody = start ? TransmissionRequest(
        method: "torrent-start",
        arguments: [:]
    ) : TransmissionRequest(
        method: "torrent-stop",
        arguments: [:]
    )
    
    guard let req = buildRequest(requestBody: requestBody, auth: info.auth) else {
        onResponse(TransmissionResponse.configError)
        return
    }
    
    let task = URLSession.shared.dataTask(with: req) { (data, resp, err) in
        if err != nil {
            onResponse(TransmissionResponse.configError)
        }
        
        let httpResp = resp as? HTTPURLResponse
        // Call `onAdd` with the status code
        switch httpResp?.statusCode {
        case 409?: // If we get a 409, save the token and try again
            authorize(httpResp: httpResp, ssl: (info.config.scheme == "https"))
            playPauseAllTorrents(start: start, info: info, onResponse: onResponse)
            return
        case 401?:
            return onResponse(TransmissionResponse.unauthorized)
        case 200?:
            return onResponse(TransmissionResponse.success)
        default:
            return onResponse(TransmissionResponse.failed)
        }
    }
    task.resume()
}

/// A torrent action request
/// - Parameter method: One of [torrent-start, torrent-stop]. See RPC-Spec
/// - Parameter arguments: A list of torrent ids to perform the action on
public func verifyTorrent(torrent: Torrent, config: TransmissionConfig, auth: TransmissionAuth, onResponse: @escaping (TransmissionResponse) -> Void) {
    url = config
    url?.path = "/transmission/rpc"
    
    let requestBody = TorrentActionRequest(
        method: "torrent-verify",
        arguments: ["ids": [torrent.id]]
    )
    
    guard let req = buildRequest(requestBody: requestBody, auth: auth) else {
        onResponse(TransmissionResponse.configError)
        return
    }
    
    let task = URLSession.shared.dataTask(with: req) { (data, resp, err) in
        if err != nil {
            onResponse(TransmissionResponse.configError)
            return
        }
        
        let httpResp = resp as? HTTPURLResponse
        switch httpResp?.statusCode {
        case 409?: // If we get a 409, save the token and try again
            authorize(httpResp: httpResp, ssl: (config.scheme == "https"))
            verifyTorrent(torrent: torrent, config: config, auth: auth, onResponse: onResponse)
            return
        case 401?:
            return onResponse(TransmissionResponse.unauthorized)
        case 200?:
            return onResponse(TransmissionResponse.success)
        default:
            return onResponse(TransmissionResponse.failed)
        }
    }
    task.resume()
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
    }
}

public struct TorrentSetRequest: Codable {
    public let method: String
    public let arguments: TorrentSetRequestArgs
}

/// Update torrent properties using the torrent-set method
/// - Parameter args: TorrentSetRequestArgs containing the properties and IDs to update
/// - Parameter info: Tuple containing server config and auth info
/// - Parameter onComplete: Called when the server's response is received
public func updateTorrent(args: TorrentSetRequestArgs, info: (config: TransmissionConfig, auth: TransmissionAuth), onComplete: @escaping (TransmissionResponse) -> Void) {
    url = info.config
    url?.path = "/transmission/rpc"
    
    let requestBody = TorrentSetRequest(
        method: "torrent-set",
        arguments: args
    )
    
    guard let req = buildRequest(requestBody: requestBody, auth: info.auth) else {
        onComplete(TransmissionResponse.configError)
        return
    }
    
    let task = URLSession.shared.dataTask(with: req) { (data, resp, err) in
        if err != nil {
            onComplete(TransmissionResponse.configError)
            return
        }
        
        let httpResp = resp as? HTTPURLResponse
        switch httpResp?.statusCode {
        case 409?: // If we get a 409, save the token and try again
            authorize(httpResp: httpResp, ssl: (info.config.scheme == "https"))
            updateTorrent(args: args, info: info, onComplete: onComplete)
            return
        case 401?:
            return onComplete(TransmissionResponse.unauthorized)
        case 200?:
            return onComplete(TransmissionResponse.success)
        default:
            return onComplete(TransmissionResponse.failed)
        }
    }
    task.resume()
}

/// Gets the session-token from the response and sets it as the `lastSessionToken`
public func authorize(httpResp: HTTPURLResponse?, ssl: Bool) {
    TOKEN_HEAD = ssl ? TOKEN_HEAD : "X-Transmission-Session-Id" // Aparently it's different with SSL 🤦‍♂️
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

/// A function to start a torrent immediately, disregarding its queue position
/// - Parameter torrent: The torrent to start immediately
/// - Parameter config: The server's configuration
/// - Parameter auth: Authentication credentials
/// - Parameter onResponse: Callback with the server's response
public func startTorrentNow(torrent: Torrent, config: TransmissionConfig, auth: TransmissionAuth, onResponse: @escaping (TransmissionResponse) -> Void) {
    url = config
    url?.path = "/transmission/rpc"
    
    let requestBody = TorrentActionRequest(
        method: "torrent-start-now",
        arguments: ["ids": [torrent.id]]
    )
    
    guard let req = buildRequest(requestBody: requestBody, auth: auth) else {
        onResponse(TransmissionResponse.configError)
        return
    }
    
    let task = URLSession.shared.dataTask(with: req) { (data, resp, err) in
        if err != nil {
            onResponse(TransmissionResponse.configError)
            return
        }
        
        let httpResp = resp as? HTTPURLResponse
        switch httpResp?.statusCode {
        case 409?: // If we get a 409, save the token and try again
            authorize(httpResp: httpResp, ssl: (config.scheme == "https"))
            startTorrentNow(torrent: torrent, config: config, auth: auth, onResponse: onResponse)
            return
        case 401?:
            return onResponse(TransmissionResponse.unauthorized)
        case 200?:
            return onResponse(TransmissionResponse.success)
        default:
            return onResponse(TransmissionResponse.failed)
        }
    }
    task.resume()
}

/// Re-announces the torrent to trackers immediately
/// - Parameter torrent: The torrent to re-announce
/// - Parameter config: The server's configuration
/// - Parameter auth: Authentication credentials
/// - Parameter onResponse: Callback with the server's response
public func reAnnounceTorrent(torrent: Torrent, config: TransmissionConfig, auth: TransmissionAuth, onResponse: @escaping (TransmissionResponse) -> Void) {
    url = config
    url?.path = "/transmission/rpc"
    
    let requestBody = TorrentActionRequest(
        method: "torrent-reannounce",
        arguments: ["ids": [torrent.id]]
    )
    
    guard let req = buildRequest(requestBody: requestBody, auth: auth) else {
        onResponse(TransmissionResponse.configError)
        return
    }
    
    let task = URLSession.shared.dataTask(with: req) { (data, resp, err) in
        if err != nil {
            onResponse(TransmissionResponse.configError)
            return
        }
        
        let httpResp = resp as? HTTPURLResponse
        switch httpResp?.statusCode {
        case 409?: // If we get a 409, save the token and try again
            authorize(httpResp: httpResp, ssl: (config.scheme == "https"))
            reAnnounceTorrent(torrent: torrent, config: config, auth: auth, onResponse: onResponse)
            return
        case 401?:
            return onResponse(TransmissionResponse.unauthorized)
        case 200?:
            return onResponse(TransmissionResponse.success)
        default:
            return onResponse(TransmissionResponse.failed)
        }
    }
    task.resume()
}