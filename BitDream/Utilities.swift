import Foundation
import SwiftUI
import CoreData
import KeychainAccess
import WidgetKit
import UniformTypeIdentifiers

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
        return sortedList.sorted { a, b in
            let keyA = makeEtaSortKey(for: a)
            let keyB = makeEtaSortKey(for: b)
            if order == .ascending {
                return keyA < keyB
            }
            return keyA > keyB
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

/// Shared speed formatting helper (Bytes per second -> human-readable short string)
func formatSpeed(_ bytesPerSecond: Int64) -> String {
    if bytesPerSecond <= 0 { return "0 B/s" }
    let base = byteCountFormatter.string(fromByteCount: bytesPerSecond)
    return "\(base)/s"
}

/*--------------------------------------------------------------------------------------------
 Refresh transmission data functions
 -------------------------------------------------------------------------------------------*/

/// Updates the list of torrents when called
func updateList(store: Store, update: @escaping ([Torrent]) -> Void, retry: Int = 0) {
    let info = makeConfig(store: store)
    getTorrents(config: info.config, auth: info.auth, onReceived: { torrents, err in
        if let err = err {
            print("Connection error…")
            store.handleConnectionError(message: err)
            return
        }

        guard let torrents = torrents else {
            store.handleConnectionError(message: "No data returned from server.")
            return
        }

        update(torrents)
    })
}

/// Updates the list of torrents when called
func updateSessionStats(store: Store, update: @escaping (SessionStats) -> Void, retry: Int = 0) {
    let info = makeConfig(store: store)
    getSessionStats(config: info.config, auth: info.auth, onReceived: { sessions, err in
        if let err = err {
            print("Connection error…")
            store.handleConnectionError(message: err)
            return
        }

        guard let stats = sessions else {
            store.handleConnectionError(message: "No data returned from server.")
            return
        }

        update(stats)
        // Write widget snapshot; non-blocking and non-fatal on failure
        writeSessionSnapshot(store: store, stats: stats)
    })
}

/// Updates the session configuration (download directory, version, settings) with retry logic
func updateSessionInfo(store: Store, update: @escaping (TransmissionSessionResponseArguments) -> Void, retry: Int = 0) {
    let info = makeConfig(store: store)
    getSession(config: info.config, auth: info.auth, onResponse: { sessionInfo in
        update(sessionInfo)
    }, onError: { err in
        print("Session info error: \(err)")
        store.handleConnectionError(message: err)
    })
}

func pollTransmissionData(store: Store) {
    let info = makeConfig(store: store)
    getSessionStats(config: info.config, auth: info.auth, onReceived: { sessions, err in
        if let err = err {
            print("Connection error…")
            store.handleConnectionError(message: err)
            return
        }

        guard let stats = sessions else {
            store.handleConnectionError(message: "No data returned from server.")
            return
        }

        store.markConnected()
        DispatchQueue.main.async {
            store.sessionStats = stats
        }
        writeSessionSnapshot(store: store, stats: stats)

        updateList(store: store, update: { vals in
            DispatchQueue.main.async {
                store.torrents = vals
            }
        })

        updateSessionInfo(store: store, update: { sessionInfo in
            DispatchQueue.main.async {
                store.sessionConfiguration = sessionInfo
                store.defaultDownloadDir = sessionInfo.downloadDir

                // Update version in CoreData if host is available
                if let host = store.host {
                    host.version = sessionInfo.version
                    try? PersistenceController.shared.container.viewContext.save()
                }
            }
        })
    })
}

// updates all Transmission data based on current host
func refreshTransmissionData(store: Store) {
    pollTransmissionData(store: store)

    // Also refresh servers index for widgets
    writeServersIndex(store: store)
}

/*--------------------------------------------------------------------------------------------
 More functions
 -------------------------------------------------------------------------------------------*/

/// Function for generating config and auth for API calls
/// - Parameter store: The current `Store` containing session information needed for creating the config.
/// - Returns a tuple containing the requested `config` and `auth`
func makeConfig(store: Store) -> (config: TransmissionConfig, auth: TransmissionAuth) {
    // Build config and auth safely without force unwraps
    var config = TransmissionConfig()
    guard let host = store.host else {
        return (config: config, auth: TransmissionAuth(username: "", password: ""))
    }
    config.host = host.server
    config.port = Int(host.port)
    config.scheme = host.isSSL ? "https" : "http"

    let keychain = Keychain(service: "crapshack.BitDream")
    let username = host.username ?? ""
    let password: String = {
        if let hostName = host.name, let stored = keychain[hostName] {
            return stored
        }
        return ""
    }()
    let auth = TransmissionAuth(username: username, password: password)

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
    // Fast path: scan bytes without converting the whole payload to String
    return data.withUnsafeBytes { rawBuffer -> TorrentInfo? in
        let bytes = rawBuffer.bindMemory(to: UInt8.self)
        let count = bytes.count
        guard count > 2, bytes[0] == UInt8(ascii: "d") else { return nil }

        // Locate top-level key "info" and capture its value bounds [infoStart, infoEnd)
        var index = 1 // skip initial 'd'
        var infoStart: Int? = nil
        var infoEnd: Int? = nil

        while index < count {
            if bytes[index] == UInt8(ascii: "e") { break }
            // Parse key (bencode string: <len>:<key>)
            guard let (keyLen, afterLenIdx) = fastReadDecimalNumber(bytes, startIndex: index, upperBound: count) else { return nil }
            guard afterLenIdx < count, bytes[afterLenIdx] == UInt8(ascii: ":") else { return nil }
            let keyStart = afterLenIdx + 1
            let keyEnd = keyStart + keyLen
            guard keyEnd <= count else { return nil }
            let isInfoKey = fastKeyEquals(bytes, start: keyStart, length: keyLen, ascii: "info")
            index = keyEnd

            // Parse value start at current index; skip or capture if it's info
            if isInfoKey {
                guard let endIdx = fastSkipBencodeValue(bytes, startIndex: index, upperBound: count) else { return nil }
                infoStart = index
                infoEnd = endIdx
                break
            } else {
                guard let endIdx = fastSkipBencodeValue(bytes, startIndex: index, upperBound: count) else { return nil }
                index = endIdx
            }
        }

        guard let infoStartIdx = infoStart, let infoEndIdx = infoEnd else { return nil }
        return fastParseInfoDictionary(bytes, startIndex: infoStartIdx, endIndex: infoEndIdx)
    }
}

// MARK: - Fast Bencode Helpers (byte-scanning, minimal allocations)

/// Read a decimal number used by bencode string length prefixes. Returns (value, indexAfterNumber)
private func fastReadDecimalNumber(_ bytes: UnsafeBufferPointer<UInt8>, startIndex: Int, upperBound: Int) -> (Int, Int)? {
    var idx = startIndex
    guard idx < upperBound else { return nil }
    var value = 0
    var sawDigit = false
    // Cap extremely large declared lengths to avoid pathological allocations
    let maxAllowed = 100_000_000 // 100 MB
    while idx < upperBound {
        let b = bytes[idx]
        if b >= UInt8(ascii: "0") && b <= UInt8(ascii: "9") {
            sawDigit = true
            let digit = Int(b &- UInt8(ascii: "0"))
            let (mul, mulOverflow) = value.multipliedReportingOverflow(by: 10)
            if mulOverflow { return nil }
            let (add, addOverflow) = mul.addingReportingOverflow(digit)
            if addOverflow { return nil }
            if add > maxAllowed { return nil }
            value = add
            idx &+= 1
        } else {
            break
        }
    }
    guard sawDigit else { return nil }
    return (value, idx)
}

/// Skip a single bencode value and return the index just AFTER the value
private func fastSkipBencodeValue(_ bytes: UnsafeBufferPointer<UInt8>, startIndex: Int, upperBound: Int) -> Int? {
    var idx = startIndex
    guard idx < upperBound else { return nil }
    let tag = bytes[idx]

    // Integer: i<digits>e
    if tag == UInt8(ascii: "i") {
        idx &+= 1
        if idx < upperBound, bytes[idx] == UInt8(ascii: "-") { idx &+= 1 }
        while idx < upperBound {
            let b = bytes[idx]
            if b == UInt8(ascii: "e") { return idx + 1 }
            if b < UInt8(ascii: "0") || b > UInt8(ascii: "9") { return nil }
            idx &+= 1
        }
        return nil
    }

    // List: l<value>...e
    if tag == UInt8(ascii: "l") {
        idx &+= 1
        while idx < upperBound, bytes[idx] != UInt8(ascii: "e") {
            guard let next = fastSkipBencodeValue(bytes, startIndex: idx, upperBound: upperBound) else { return nil }
            idx = next
        }
        return (idx < upperBound) ? idx + 1 : nil
    }

    // Dict: d<key><value>...e
    if tag == UInt8(ascii: "d") {
        idx &+= 1
        while idx < upperBound, bytes[idx] != UInt8(ascii: "e") {
            // key (string)
            guard let (kLen, afterLen) = fastReadDecimalNumber(bytes, startIndex: idx, upperBound: upperBound) else { return nil }
            guard afterLen < upperBound, bytes[afterLen] == UInt8(ascii: ":") else { return nil }
            let keyEnd = afterLen + 1 + kLen
            guard keyEnd <= upperBound else { return nil }
            idx = keyEnd
            // value
            guard let next = fastSkipBencodeValue(bytes, startIndex: idx, upperBound: upperBound) else { return nil }
            idx = next
        }
        return (idx < upperBound) ? idx + 1 : nil
    }

    // String: <len>:<bytes>
    if tag >= UInt8(ascii: "0") && tag <= UInt8(ascii: "9") {
        guard let (len, afterLen) = fastReadDecimalNumber(bytes, startIndex: idx, upperBound: upperBound) else { return nil }
        let valueStart = afterLen + 1 // skip ':'
        let valueEnd = valueStart + len
        guard afterLen < upperBound, bytes[afterLen] == UInt8(ascii: ":"), valueEnd <= upperBound else { return nil }
        return valueEnd
    }

    return nil
}

/// Compare a bencode key without allocating strings
private func fastKeyEquals(_ bytes: UnsafeBufferPointer<UInt8>, start: Int, length: Int, ascii key: StaticString) -> Bool {
    // Compare raw bytes to ASCII StaticString without optional binding
    let keyLen = key.utf8CodeUnitCount
    // Ensure the slice [start, start + keyLen) is within bounds and matches expected length
    guard length == keyLen,
          start >= 0,
          keyLen <= bytes.count - start else { return false }
    // Access the raw pointer to the StaticString's UTF8 storage
    return key.withUTF8Buffer { keyBuf -> Bool in
        var i = 0
        while i < keyLen {
            if bytes[start + i] != keyBuf[i] { return false }
            i &+= 1
        }
        return true
    }
}

/// Parse the `info` dictionary for name, files/length quickly
private func fastParseInfoDictionary(_ bytes: UnsafeBufferPointer<UInt8>, startIndex: Int, endIndex: Int) -> TorrentInfo? {
    var idx = startIndex
    guard idx < endIndex, bytes[idx] == UInt8(ascii: "d") else { return nil }
    idx &+= 1

    var torrentName: String?
    var totalSize: Int64 = 0
    var fileCount: Int = 0
    var sawFilesList = false
    var sawNameUTF8 = false

    while idx < endIndex, bytes[idx] != UInt8(ascii: "e") {
        // Key
        guard let (kLen, afterLen) = fastReadDecimalNumber(bytes, startIndex: idx, upperBound: endIndex) else { return nil }
        guard afterLen < endIndex, bytes[afterLen] == UInt8(ascii: ":") else { return nil }
        let keyStart = afterLen + 1
        let keyEnd = keyStart + kLen
        guard keyEnd <= endIndex else { return nil }

        let isNameUTF8Key = fastKeyEquals(bytes, start: keyStart, length: kLen, ascii: "name.utf-8")
        let isNameKey = !isNameUTF8Key && fastKeyEquals(bytes, start: keyStart, length: kLen, ascii: "name")
        let isFilesKey = !isNameKey && fastKeyEquals(bytes, start: keyStart, length: kLen, ascii: "files")
        let isLengthKey = (!isNameKey && !isFilesKey) && fastKeyEquals(bytes, start: keyStart, length: kLen, ascii: "length")

        idx = keyEnd

        if isNameUTF8Key || isNameKey {
            // Value must be a string: <len>:<bytes>
            guard let (vLen, afterVLen) = fastReadDecimalNumber(bytes, startIndex: idx, upperBound: endIndex) else { return nil }
            guard afterVLen < endIndex, bytes[afterVLen] == UInt8(ascii: ":") else { return nil }
            let valueStart = afterVLen + 1
            let valueEnd = valueStart + vLen
            guard valueEnd <= endIndex else { return nil }
            // Small copy only for the name
            guard let base = bytes.baseAddress else { return nil }
            let namePtr = base.advanced(by: valueStart)
            let nameBuffer = UnsafeBufferPointer(start: namePtr, count: vLen)
            let nameString = String(decoding: nameBuffer, as: UTF8.self)
            if isNameUTF8Key {
                torrentName = nameString
                sawNameUTF8 = true
            } else if !sawNameUTF8 && torrentName == nil {
                torrentName = nameString
            }
            idx = valueEnd
        } else if isFilesKey {
            // files: list of dicts
            sawFilesList = true
            guard idx < endIndex, bytes[idx] == UInt8(ascii: "l") else {
                // Not a list; skip defensively
                guard let next = fastSkipBencodeValue(bytes, startIndex: idx, upperBound: endIndex) else { return nil }
                idx = next
                continue
            }
            idx &+= 1 // skip 'l'

            while idx < endIndex, bytes[idx] != UInt8(ascii: "e") {
                guard idx < endIndex, bytes[idx] == UInt8(ascii: "d") else {
                    // Unexpected item, skip
                    guard let next = fastSkipBencodeValue(bytes, startIndex: idx, upperBound: endIndex) else { return nil }
                    idx = next
                    continue
                }
                idx &+= 1 // into dict

                var fileLength: Int64 = 0
                var countedThisFile = false

                while idx < endIndex, bytes[idx] != UInt8(ascii: "e") {
                    guard let (fkLen, fAfterLen) = fastReadDecimalNumber(bytes, startIndex: idx, upperBound: endIndex) else { return nil }
                    guard fAfterLen < endIndex, bytes[fAfterLen] == UInt8(ascii: ":") else { return nil }
                    let fkStart = fAfterLen + 1
                    let fkEnd = fkStart + fkLen
                    guard fkEnd <= endIndex else { return nil }
                    let isLength = fastKeyEquals(bytes, start: fkStart, length: fkLen, ascii: "length")
                    idx = fkEnd

                    if isLength {
                        // Expect integer value i<digits>e
                        guard idx < endIndex, bytes[idx] == UInt8(ascii: "i") else {
                            guard let next = fastSkipBencodeValue(bytes, startIndex: idx, upperBound: endIndex) else { return nil }
                            idx = next
                            continue
                        }
                        idx &+= 1
                        var negative = false
                        if idx < endIndex, bytes[idx] == UInt8(ascii: "-") { negative = true; idx &+= 1 }
                        var v: Int64 = 0
                        while idx < endIndex {
                            let b = bytes[idx]
                            if b == UInt8(ascii: "e") { idx &+= 1; break }
                            let d = Int64(b) - Int64(UInt8(ascii: "0"))
                            if d < 0 || d > 9 { return nil }
                            v = v &* 10 &+ d
                            idx &+= 1
                        }
                        fileLength = negative ? -v : v
                    } else {
                        // Skip non-length values
                        guard let next = fastSkipBencodeValue(bytes, startIndex: idx, upperBound: endIndex) else { return nil }
                        idx = next
                    }
                }

                // Close file dict
                guard idx < endIndex, bytes[idx] == UInt8(ascii: "e") else { return nil }
                idx &+= 1
                totalSize &+= fileLength
                if !countedThisFile { fileCount &+= 1; countedThisFile = true }
            }

            // Close files list
            guard idx < endIndex, bytes[idx] == UInt8(ascii: "e") else { return nil }
            idx &+= 1
        } else if isLengthKey {
            // Single-file torrent size: integer
            guard idx < endIndex, bytes[idx] == UInt8(ascii: "i") else {
                guard let next = fastSkipBencodeValue(bytes, startIndex: idx, upperBound: endIndex) else { return nil }
                idx = next
                continue
            }
            idx &+= 1
            var negative = false
            if idx < endIndex, bytes[idx] == UInt8(ascii: "-") { negative = true; idx &+= 1 }
            var v: Int64 = 0
            while idx < endIndex {
                let b = bytes[idx]
                if b == UInt8(ascii: "e") { idx &+= 1; break }
                let d = Int64(b) - Int64(UInt8(ascii: "0"))
                if d < 0 || d > 9 { return nil }
                v = v &* 10 &+ d
                idx &+= 1
            }
            totalSize = negative ? -v : v
            fileCount = 1
        } else {
            // Skip uninteresting value
            guard let next = fastSkipBencodeValue(bytes, startIndex: idx, upperBound: endIndex) else { return nil }
            idx = next
        }

        // Early exit if we have all we need
        if let name = torrentName {
            if sawFilesList {
                if fileCount > 0 { return TorrentInfo(name: name, totalSize: totalSize, fileCount: fileCount) }
            } else if fileCount == 1 {
                return TorrentInfo(name: name, totalSize: totalSize, fileCount: 1)
            }
        }
    }

    guard let name = torrentName else { return nil }
    let resolvedCount = fileCount > 0 ? fileCount : (totalSize > 0 ? 1 : 0)
    return TorrentInfo(name: name, totalSize: totalSize, fileCount: max(resolvedCount, 1))
}
