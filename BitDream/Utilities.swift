//
//  Utilities.swift
//  BitDream
//
//  Created by Austin Smith on 12/29/22.
//

import Foundation
import SwiftUI
import CoreData
import KeychainAccess

/*--------------------------------------------------------------------------------------------
 Sorting stuff
 -------------------------------------------------------------------------------------------*/

struct SortDescriptor<Value> {
    var comparator: (Value, Value) -> ComparisonResult
}

extension SortDescriptor {
    static func keyPath<T: Comparable>(_ keyPath: KeyPath<Value, T>) -> Self {
        Self { rootA, rootB in
            let valueA = rootA[keyPath: keyPath]
            let valueB = rootB[keyPath: keyPath]

            guard valueA != valueB else {
                return .orderedSame
            }

            return valueA < valueB ? .orderedAscending : .orderedDescending
        }
    }
}

enum SortOrder {
    case ascending
    case descending
}

extension Sequence {
    func sorted(using descriptors: [SortDescriptor<Element>],
                order: SortOrder) -> [Element] {
        sorted { valueA, valueB in
            for descriptor in descriptors {
                let result = descriptor.comparator(valueA, valueB)

                switch result {
                case .orderedSame:
                    // Keep iterating if the two elements are equal,
                    // since that'll let the next descriptor determine
                    // the sort order:
                    break
                case .orderedAscending:
                    return order == .ascending
                case .orderedDescending:
                    return order == .descending
                }
            }

            // If no descriptor was able to determine the sort
            // order, we'll default to false (similar to when
            // using the '<' operator with the built-in API):
            return false
        }
    }
}


extension Sequence {
    func sortedAscending(using descriptors: SortDescriptor<Element>...) -> [Element] {
        sorted(using: descriptors, order: .ascending)
    }
}

extension Sequence {
    func sortedDescending(using descriptors: SortDescriptor<Element>...) -> [Element] {
        sorted(using: descriptors, order: .descending)
    }
}

public enum SortProperty: String, CaseIterable {
    case name = "Name"
    case size = "Size"
    case status = "Status"
    case dateAdded = "Date Added"
    case eta = "Remaining Time"
}

func sortTorrents(_ torrents: [Torrent], by property: SortProperty, order: SortOrder) -> [Torrent] {
    let sortedList = torrents.sortedAscending(using: .keyPath(\.name))
    switch property {
    case .name:
        return order == .ascending ? torrents.sortedAscending(using: .keyPath(\.name)) : torrents.sortedDescending(using: .keyPath(\.name))
    case .dateAdded:
        return order == .ascending ? sortedList.sortedAscending(using: .keyPath(\.addedDate)) : sortedList.sortedDescending(using: .keyPath(\.addedDate))
    case .status:
        return order == .ascending ? sortedList.sortedAscending(using: .keyPath(\.statusCalc.rawValue)) : sortedList.sortedDescending(using: .keyPath(\.statusCalc.rawValue))
    case .eta:
        let ascending = (order == .ascending)
        return sortedList.sorted { a, b in
            func getPriority(_ torrent: Torrent) -> Int {
                if torrent.statusCalc == .complete { return 5 }
                if torrent.statusCalc == .seeding { return 4 }
                if torrent.statusCalc == .paused { return 3 }
                if torrent.statusCalc == .stalled { return 2 }
                if torrent.eta <= 0 { return 1 }
                return 0
            }
            let priorityA = getPriority(a)
            let priorityB = getPriority(b)
            if priorityA != priorityB {
                return ascending ? (priorityA < priorityB) : (priorityA > priorityB)
            }
            return ascending ? (a.eta < b.eta) : (a.eta > b.eta)
        }
    case .size:
        return order == .ascending ? sortedList.sortedAscending(using: .keyPath(\.sizeWhenDone)) : sortedList.sortedDescending(using: .keyPath(\.sizeWhenDone))
    }
}

/*--------------------------------------------------------------------------------------------
 Formatting stuff
 -------------------------------------------------------------------------------------------*/

public let byteCountFormatter: ByteCountFormatter = {
    var formatter = ByteCountFormatter()
    formatter.allowsNonnumericFormatting = false // Uses '0' instead of 'Zero'
    formatter.countStyle = .file
    formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
    
    return formatter
}()

/*--------------------------------------------------------------------------------------------
 Colors
 -------------------------------------------------------------------------------------------*/

// extension Color {
//     static let primary = Color("AccemtColor")
//     static let secondary = Color("SecondaryColor")
//     static let third = Color("ThirdColor")
// }

/*--------------------------------------------------------------------------------------------
 Refresh transmission data functions
 -------------------------------------------------------------------------------------------*/

/// Updates the list of torrents when called
func updateList(store: Store, update: @escaping ([Torrent]) -> Void, retry: Int = 0) {
    // Skip connection attempts if user is actively editing server settings
    if store.isEditingServerSettings {
        return
    }
    
    let info = makeConfig(store: store)
    getTorrents(config: info.config, auth: info.auth, onReceived: { torrents, err in
        if (err != nil) {
            print("Connection error...")
            store.handleConnectionError(message: err!)
        } else if (torrents == nil) {
            if (retry > 3) {
                print("Connection error after retries...")
                store.handleConnectionError(message: "Could not reach server after multiple attempts. Please check your connection.")
            } else {
                updateList(store: store, update: update, retry: retry + 1)
            }
        } else {
            // Clear connection error state on successful response
            DispatchQueue.main.async {
                // If we were in an error state before, this means we've successfully reconnected
                let wasInErrorState = store.connectionError
                
                // Clear error state
                store.connectionError = false
                store.connectionErrorMessage = ""
                
                // Auto-dismiss the alert when connection is restored
                if wasInErrorState {
                    store.showConnectionErrorAlert = false
                }
            }
            update(torrents!)
        }
    })
}

/// Updates the list of torrents when called
func updateSessionStats(store: Store, update: @escaping (SessionStats) -> Void, retry: Int = 0) {
    // Skip connection attempts if user is actively editing server settings
    if store.isEditingServerSettings {
        return
    }
    
    let info = makeConfig(store: store)
    getSessionStats(config: info.config, auth: info.auth, onReceived: { sessions, err in
        if (err != nil) {
            print("Connection error...")
            store.handleConnectionError(message: err!)
        } else if (sessions == nil) {
            if (retry > 3) {
                print("Connection error after retries...")
                store.handleConnectionError(message: "Could not reach server after multiple attempts. Please check your connection.")
            } else {
                updateSessionStats(store: store, update: update, retry: retry + 1)
            }
        } else {
            // Clear connection error state on successful response
            DispatchQueue.main.async {
                // If we were in an error state before, this means we've successfully reconnected
                let wasInErrorState = store.connectionError
                
                // Clear error state
                store.connectionError = false
                store.connectionErrorMessage = ""
                
                // Auto-dismiss the alert when connection is restored
                if wasInErrorState {
                    store.showConnectionErrorAlert = false
                }
            }
            update(sessions!)
        }
    })
}

// updates all Transmission data based on current host
func refreshTransmissionData(store: Store) {
    // update the list of torrents when new host is set
    updateList(store: store, update: { vals in
        DispatchQueue.main.async {
            store.objectWillChange.send()
            store.torrents = vals
        }
    })
    
    updateSessionStats(store: store, update: { vals in
        DispatchQueue.main.async {
            store.objectWillChange.send()
            store.sessionStats = vals
        }
    })
    
    let info = makeConfig(store: store)
    // also reset default download directory when new host is set
    getSession(config: info.config, auth: info.auth) { sessionInfo in
        DispatchQueue.main.async {
            store.objectWillChange.send()
            store.defaultDownloadDir = sessionInfo.downloadDir
            
            // Update version in CoreData
            if let host = store.host {
                host.version = sessionInfo.version
                try? PersistenceController.shared.container.viewContext.save()
            }
        }
    }
}

/*--------------------------------------------------------------------------------------------
 More functions
 -------------------------------------------------------------------------------------------*/

/// Function for generating config and auth for API calls
/// - Parameter store: The current `Store` containing session information needed for creating the config.
/// - Returns a tuple containing the requested `config` and `auth`
func makeConfig(store: Store) -> (config: TransmissionConfig, auth: TransmissionAuth) {
    // Send the file to the server
    var config = TransmissionConfig()
    config.host = store.host?.server
    config.port = Int(store.host!.port)
    config.scheme = store.host!.isSSL ? "https" : "http"
    let keychain = Keychain(service: "crapshack.BitDream")
    var auth: TransmissionAuth
    
    if let password = keychain[store.host!.name!] {
        auth = TransmissionAuth(username: store.host!.username!, password: password)
    }
    else {
        auth = TransmissionAuth(username: store.host!.username!, password: "")
    }

    return (config: config, auth: auth)
}

/*--------------------------------------------------------------------------------------------
| Transmission Response Handling
| -------------------------------------------------------------------------------------------*/

/// Handles TransmissionResponse with proper error handling and user feedback
/// - Parameters:
///   - response: The TransmissionResponse from the API call
///   - onSuccess: Callback executed on successful response
///   - onError: Callback executed on error with user-friendly error message
func handleTransmissionResponse(
    _ response: TransmissionResponse,
    onSuccess: @escaping () -> Void,
    onError: @escaping (String) -> Void
) {
    DispatchQueue.main.async {
        switch response {
        case .success:
            onSuccess()
        case .failed:
            onError("Operation failed. Please try again.")
        case .unauthorized:
            onError("Authentication failed. Please check your server credentials.")
        case .configError:
            onError("Connection error. Please check your server settings.")
        @unknown default:
            onError("An unexpected error occurred. Please try again.")
        }
    }
}

/// SwiftUI View modifier for displaying transmission error alerts
struct TransmissionErrorAlert: ViewModifier {
    @Binding var isPresented: Bool
    let message: String
    
    func body(content: Content) -> some View {
        content
            .alert("Error", isPresented: $isPresented) {
                Button("OK") { }
            } message: {
                Text(message)
            }
    }
}

extension View {
    /// Adds a standardized error alert for transmission operations
    func transmissionErrorAlert(isPresented: Binding<Bool>, message: String) -> some View {
        modifier(TransmissionErrorAlert(isPresented: isPresented, message: message))
    }
}

/*--------------------------------------------------------------------------------------------
| Bencode Parser for Torrent Files
| -------------------------------------------------------------------------------------------*/

/// Torrent metadata structure
struct TorrentInfo {
    let name: String
    let totalSize: Int64
    let fileCount: Int
    
    var formattedSize: String {
        return byteCountFormatter.string(fromByteCount: totalSize)
    }
    
    var fileCountText: String {
        return fileCount == 1 ? "1 file" : "\(fileCount) files"
    }
}

/// Parse torrent metadata from .torrent file data
/// - Parameter data: The raw .torrent file data
/// - Returns: TorrentInfo with name, size, and file count, or nil if parsing fails
func parseTorrentInfo(from data: Data) -> TorrentInfo? {
    guard let name = parseBencodeString(data: data, key: "name") else { return nil }
    
    let bytes = [UInt8](data)
    
    // Try to find "files" key for multi-file torrents
    if let filesPattern = "5:files".data(using: .utf8),
       let _ = findPattern([UInt8](filesPattern), in: bytes) {
        // Multi-file torrent - sum up individual file sizes
        let (totalSize, fileCount) = parseMultiFileTorrent(bytes: bytes)
        return TorrentInfo(name: name, totalSize: totalSize, fileCount: fileCount)
    } else {
        // Single file torrent - get the "length" field
        if let length = parseBencodeInteger(data: data, key: "length") {
            return TorrentInfo(name: name, totalSize: length, fileCount: 1)
        }
    }
    
    return nil
}

/// Parse torrent name from .torrent file data (legacy function for compatibility)
/// - Parameter data: The raw .torrent file data
/// - Returns: The torrent name from the info dictionary, or nil if parsing fails
func parseTorrentName(from data: Data) -> String? {
    return parseBencodeString(data: data, key: "name")
}

/// Parse a string value from bencode data for a given key (optimized)
/// - Parameters:
///   - data: The bencode data
///   - key: The key to search for
/// - Returns: The string value, or nil if not found or parsing fails
private func parseBencodeString(data: Data, key: String) -> String? {
    // Use faster string search instead of byte-by-byte
    guard let dataString = String(data: data, encoding: .isoLatin1) else { return nil }
    let keyPattern = "\(key.count):\(key)"
    
    guard let range = dataString.range(of: keyPattern) else { return nil }
    
    let afterKey = String(dataString[range.upperBound...])
    guard let colonIndex = afterKey.firstIndex(of: ":") else { return nil }
    
    let lengthStr = String(afterKey[..<colonIndex])
    guard let length = Int(lengthStr) else { return nil }
    
    let valueStart = afterKey.index(after: colonIndex)
    guard afterKey.distance(from: valueStart, to: afterKey.endIndex) >= length else { return nil }
    
    let valueEnd = afterKey.index(valueStart, offsetBy: length)
    return String(afterKey[valueStart..<valueEnd])
}

/// Parse an integer value from bencode data for a given key (optimized)
/// - Parameters:
///   - data: The bencode data
///   - key: The key to search for
/// - Returns: The integer value, or nil if not found or parsing fails
private func parseBencodeInteger(data: Data, key: String) -> Int64? {
    guard let dataString = String(data: data, encoding: .isoLatin1) else { return nil }
    let keyPattern = "\(key.count):\(key)i"
    
    guard let range = dataString.range(of: keyPattern) else { return nil }
    
    let afterKey = String(dataString[range.upperBound...])
    guard let eIndex = afterKey.firstIndex(of: "e") else { return nil }
    
    let valueStr = String(afterKey[..<eIndex])
    return Int64(valueStr)
}

/// Parse multi-file torrent to get total size and file count
/// - Parameter bytes: The torrent file bytes
/// - Returns: Tuple of (totalSize, fileCount)
private func parseMultiFileTorrent(bytes: [UInt8]) -> (Int64, Int) {
    var totalSize: Int64 = 0
    var fileCount = 0
    
    // Look for length fields in the files list
    let lengthPattern = "6:lengthi".utf8.map { UInt8($0) }
    var searchIndex = 0
    
    while searchIndex < bytes.count {
        if let lengthIndex = findPattern(lengthPattern, in: Array(bytes[searchIndex...])) {
            let actualIndex = searchIndex + lengthIndex + lengthPattern.count
            
            // Find the end of this integer
            var endIndex = actualIndex
            while endIndex < bytes.count && bytes[endIndex] != UInt8(ascii: "e") {
                endIndex += 1
            }
            
            if endIndex < bytes.count,
               let lengthStr = String(bytes: bytes[actualIndex..<endIndex], encoding: .utf8),
               let length = Int64(lengthStr) {
                totalSize += length
                fileCount += 1
            }
            
            searchIndex = endIndex + 1
        } else {
            break
        }
    }
    
    return (totalSize, fileCount)
}

/// Find a byte pattern in a byte array
/// - Parameters:
///   - pattern: The pattern to search for
///   - data: The data to search in
/// - Returns: The index of the first occurrence, or nil if not found
private func findPattern(_ pattern: [UInt8], in data: [UInt8]) -> Int? {
    guard pattern.count <= data.count else { return nil }
    
    for i in 0...(data.count - pattern.count) {
        var found = true
        for j in 0..<pattern.count {
            if data[i + j] != pattern[j] {
                found = false
                break
            }
        }
        if found { return i }
    }
    return nil
}
