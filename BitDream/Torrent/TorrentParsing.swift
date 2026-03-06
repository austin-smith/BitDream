import Foundation

// MARK: - Torrent Parsing

struct TorrentMagnetLink: RawRepresentable, Sendable, Hashable {
    let rawValue: String

    init?(rawValue: String) {
        guard rawValue.count <= 4096 else { return nil }
        guard let url = URL(string: rawValue), url.scheme?.lowercased() == "magnet" else { return nil }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems else { return nil }

        let exactTopic = items.first { $0.name.lowercased() == "xt" }?.value?.lowercased()
        guard let exactTopic, exactTopic.hasPrefix("urn:btih:") else { return nil }

        self.rawValue = rawValue
    }
}

/// Torrent metadata structure
struct TorrentInfo: Sendable {
    let name: String
    let totalSize: Int64
    let fileCount: Int

    var formattedSize: String {
        return formatByteCount(totalSize)
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
        var infoStart: Int?
        var infoEnd: Int?

        while index < count {
            if bytes[index] == UInt8(ascii: "e") { break }
            // Parse key (bencode string: <len>:<key>)
            guard let (keyLen, afterLenIdx) = readBencodeDecimalNumber(bytes, startIndex: index, upperBound: count) else { return nil }
            guard afterLenIdx < count, bytes[afterLenIdx] == UInt8(ascii: ":") else { return nil }
            let keyStart = afterLenIdx + 1
            let keyEnd = keyStart + keyLen
            guard keyEnd <= count else { return nil }
            let isInfoKey = bencodeKeyEquals(bytes, start: keyStart, length: keyLen, ascii: "info")
            index = keyEnd

            // Parse value start at current index; skip or capture if it's info
            if isInfoKey {
                guard let endIdx = skipBencodeValue(bytes, startIndex: index, upperBound: count) else { return nil }
                infoStart = index
                infoEnd = endIdx
                break
            } else {
                guard let endIdx = skipBencodeValue(bytes, startIndex: index, upperBound: count) else { return nil }
                index = endIdx
            }
        }

        guard let infoStartIdx = infoStart, let infoEndIdx = infoEnd else { return nil }
        return parseInfoDictionary(bytes, startIndex: infoStartIdx, endIndex: infoEndIdx)
    }
}

// MARK: - Bencode Helpers (byte-scanning, minimal allocations)

/// Read a decimal number used by bencode string length prefixes. Returns (value, indexAfterNumber)
private func readBencodeDecimalNumber(_ bytes: UnsafeBufferPointer<UInt8>, startIndex: Int, upperBound: Int) -> (Int, Int)? {
    var idx = startIndex
    guard idx < upperBound else { return nil }
    var value = 0
    var sawDigit = false
    // Cap extremely large declared lengths to avoid pathological allocations
    let maxAllowed = 100_000_000 // 100 MB
    while idx < upperBound {
        let byte = bytes[idx]
        if byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9") {
            sawDigit = true
            let digit = Int(byte &- UInt8(ascii: "0"))
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
private func skipBencodeValue(_ bytes: UnsafeBufferPointer<UInt8>, startIndex: Int, upperBound: Int) -> Int? {
    guard startIndex < upperBound else { return nil }

    switch classifyBencodeValue(bytes[startIndex]) {
    case .integer:
        return skipBencodeInteger(bytes, startIndex: startIndex, upperBound: upperBound)
    case .list:
        return skipBencodeList(bytes, startIndex: startIndex, upperBound: upperBound)
    case .dictionary:
        return skipBencodeDictionary(bytes, startIndex: startIndex, upperBound: upperBound)
    case .string:
        return skipBencodeString(bytes, startIndex: startIndex, upperBound: upperBound)
    case .invalid:
        return nil
    }
}

private enum BencodeValueKind {
    case integer
    case list
    case dictionary
    case string
    case invalid
}

private func classifyBencodeValue(_ tag: UInt8) -> BencodeValueKind {
    switch tag {
    case UInt8(ascii: "i"):
        return .integer
    case UInt8(ascii: "l"):
        return .list
    case UInt8(ascii: "d"):
        return .dictionary
    case UInt8(ascii: "0")...UInt8(ascii: "9"):
        return .string
    default:
        return .invalid
    }
}

private func skipBencodeInteger(
    _ bytes: UnsafeBufferPointer<UInt8>,
    startIndex: Int,
    upperBound: Int
) -> Int? {
    var idx = startIndex + 1
    if idx < upperBound, bytes[idx] == UInt8(ascii: "-") {
        idx &+= 1
    }

    while idx < upperBound {
        let byte = bytes[idx]
        if byte == UInt8(ascii: "e") { return idx + 1 }
        if byte < UInt8(ascii: "0") || byte > UInt8(ascii: "9") { return nil }
        idx &+= 1
    }

    return nil
}

private func skipBencodeList(
    _ bytes: UnsafeBufferPointer<UInt8>,
    startIndex: Int,
    upperBound: Int
) -> Int? {
    var idx = startIndex + 1
    while idx < upperBound, bytes[idx] != UInt8(ascii: "e") {
        guard let next = skipBencodeValue(bytes, startIndex: idx, upperBound: upperBound) else { return nil }
        idx = next
    }
    return (idx < upperBound) ? idx + 1 : nil
}

private func skipBencodeDictionary(
    _ bytes: UnsafeBufferPointer<UInt8>,
    startIndex: Int,
    upperBound: Int
) -> Int? {
    var idx = startIndex + 1
    while idx < upperBound, bytes[idx] != UInt8(ascii: "e") {
        guard let keyEnd = skipBencodeString(bytes, startIndex: idx, upperBound: upperBound) else { return nil }
        idx = keyEnd
        guard let next = skipBencodeValue(bytes, startIndex: idx, upperBound: upperBound) else { return nil }
        idx = next
    }
    return (idx < upperBound) ? idx + 1 : nil
}

private func skipBencodeString(
    _ bytes: UnsafeBufferPointer<UInt8>,
    startIndex: Int,
    upperBound: Int
) -> Int? {
    guard let (length, afterLength) = readBencodeDecimalNumber(
        bytes,
        startIndex: startIndex,
        upperBound: upperBound
    ) else {
        return nil
    }

    let valueStart = afterLength + 1
    let valueEnd = valueStart + length
    guard afterLength < upperBound, bytes[afterLength] == UInt8(ascii: ":"), valueEnd <= upperBound else { return nil }
    return valueEnd
}

/// Compare a bencode key without allocating strings
private func bencodeKeyEquals(_ bytes: UnsafeBufferPointer<UInt8>, start: Int, length: Int, ascii key: StaticString) -> Bool {
    // Compare raw bytes to ASCII StaticString without optional binding
    let keyLen = key.utf8CodeUnitCount
    // Ensure the slice [start, start + keyLen) is within bounds and matches expected length
    guard length == keyLen,
          start >= 0,
          keyLen <= bytes.count - start else { return false }
    // Access the raw pointer to the StaticString's UTF8 storage
    return key.withUTF8Buffer { keyBuf -> Bool in
        var offset = 0
        while offset < keyLen {
            if bytes[start + offset] != keyBuf[offset] { return false }
            offset &+= 1
        }
        return true
    }
}

private enum InfoDictionaryKey {
    case nameUTF8
    case name
    case files
    case length
    case other
}

private struct InfoDictionaryState {
    var torrentName: String?
    var totalSize: Int64 = 0
    var fileCount: Int = 0
    var sawFilesList = false
    var sawNameUTF8 = false

    mutating func applyName(_ name: String, isUTF8: Bool) {
        if isUTF8 {
            torrentName = name
            sawNameUTF8 = true
        } else if !sawNameUTF8 && torrentName == nil {
            torrentName = name
        }
    }

    mutating func applyFiles(totalSize: Int64, fileCount: Int) {
        sawFilesList = true
        self.totalSize &+= totalSize
        self.fileCount = fileCount
    }

    mutating func applySingleFileLength(_ length: Int64) {
        totalSize = length
        fileCount = 1
    }

    var earlyResolvedInfo: TorrentInfo? {
        guard let name = torrentName else { return nil }
        if sawFilesList, fileCount > 0 {
            return TorrentInfo(name: name, totalSize: totalSize, fileCount: fileCount)
        }
        if !sawFilesList, fileCount == 1 {
            return TorrentInfo(name: name, totalSize: totalSize, fileCount: 1)
        }
        return nil
    }

    var finalInfo: TorrentInfo? {
        guard let name = torrentName else { return nil }
        let resolvedCount = fileCount > 0 ? fileCount : (totalSize > 0 ? 1 : 0)
        return TorrentInfo(name: name, totalSize: totalSize, fileCount: max(resolvedCount, 1))
    }
}

private func readBencodeKey(
    _ bytes: UnsafeBufferPointer<UInt8>,
    startIndex: Int,
    upperBound: Int
) -> (key: InfoDictionaryKey, nextIndex: Int)? {
    guard let (keyLength, afterLength) = readBencodeDecimalNumber(
        bytes,
        startIndex: startIndex,
        upperBound: upperBound
    ) else {
        return nil
    }
    guard afterLength < upperBound, bytes[afterLength] == UInt8(ascii: ":") else { return nil }

    let keyStart = afterLength + 1
    let keyEnd = keyStart + keyLength
    guard keyEnd <= upperBound else { return nil }

    let key: InfoDictionaryKey
    if bencodeKeyEquals(bytes, start: keyStart, length: keyLength, ascii: "name.utf-8") {
        key = .nameUTF8
    } else if bencodeKeyEquals(bytes, start: keyStart, length: keyLength, ascii: "name") {
        key = .name
    } else if bencodeKeyEquals(bytes, start: keyStart, length: keyLength, ascii: "files") {
        key = .files
    } else if bencodeKeyEquals(bytes, start: keyStart, length: keyLength, ascii: "length") {
        key = .length
    } else {
        key = .other
    }

    return (key, keyEnd)
}

private func readBencodeStringRange(
    _ bytes: UnsafeBufferPointer<UInt8>,
    startIndex: Int,
    upperBound: Int
) -> (range: Range<Int>, nextIndex: Int)? {
    guard let (length, afterLength) = readBencodeDecimalNumber(
        bytes,
        startIndex: startIndex,
        upperBound: upperBound
    ) else {
        return nil
    }
    guard afterLength < upperBound, bytes[afterLength] == UInt8(ascii: ":") else { return nil }

    let valueStart = afterLength + 1
    let valueEnd = valueStart + length
    guard valueEnd <= upperBound else { return nil }
    return (valueStart..<valueEnd, valueEnd)
}

private func decodeBencodeString(
    _ bytes: UnsafeBufferPointer<UInt8>,
    range: Range<Int>,
    allowLossyUTF8: Bool
) -> String? {
    guard let base = bytes.baseAddress else { return nil }

    let valuePointer = base.advanced(by: range.lowerBound)
    let valueBuffer = UnsafeBufferPointer(start: valuePointer, count: range.count)

    if allowLossyUTF8 {
        return decodeLossyUTF8(valueBuffer)
    }

    return String(bytes: valueBuffer, encoding: .utf8)
}

private func decodeLossyUTF8(_ bytes: UnsafeBufferPointer<UInt8>) -> String {
    var iterator = bytes.makeIterator()
    var decoder = UTF8()
    var result = String()
    var isDecoding = true

    while isDecoding {
        switch decoder.decode(&iterator) {
        case .scalarValue(let scalar):
            result.unicodeScalars.append(scalar)
        case .emptyInput:
            isDecoding = false
        case .error:
            result.unicodeScalars.append("\u{FFFD}")
        }
    }

    return result
}

private func readBencodeInteger(
    _ bytes: UnsafeBufferPointer<UInt8>,
    startIndex: Int,
    upperBound: Int
) -> (value: Int64, nextIndex: Int)? {
    guard startIndex < upperBound, bytes[startIndex] == UInt8(ascii: "i") else { return nil }

    var idx = startIndex + 1
    var negative = false
    if idx < upperBound, bytes[idx] == UInt8(ascii: "-") {
        negative = true
        idx &+= 1
    }

    var value: Int64 = 0
    while idx < upperBound {
        let byte = bytes[idx]
        if byte == UInt8(ascii: "e") {
            return (negative ? -value : value, idx + 1)
        }

        let digit = Int64(byte) - Int64(UInt8(ascii: "0"))
        if digit < 0 || digit > 9 { return nil }
        value = value &* 10 &+ digit
        idx &+= 1
    }

    return nil
}

private func readBencodeIntegerOrSkip(
    _ bytes: UnsafeBufferPointer<UInt8>,
    startIndex: Int,
    upperBound: Int
) -> (value: Int64?, nextIndex: Int)? {
    guard startIndex < upperBound else { return nil }
    guard bytes[startIndex] == UInt8(ascii: "i") else {
        guard let nextIndex = skipBencodeValue(
            bytes,
            startIndex: startIndex,
            upperBound: upperBound
        ) else {
            return nil
        }
        return (nil, nextIndex)
    }

    guard let parsed = readBencodeInteger(bytes, startIndex: startIndex, upperBound: upperBound) else {
        return nil
    }
    return (parsed.value, parsed.nextIndex)
}

private func parseFileDictionary(
    _ bytes: UnsafeBufferPointer<UInt8>,
    startIndex: Int,
    endIndex: Int
) -> (fileLength: Int64, nextIndex: Int)? {
    var idx = startIndex
    guard idx < endIndex, bytes[idx] == UInt8(ascii: "d") else { return nil }
    idx &+= 1

    var fileLength: Int64 = 0

    while idx < endIndex, bytes[idx] != UInt8(ascii: "e") {
        guard let (key, nextIndex) = readBencodeKey(bytes, startIndex: idx, upperBound: endIndex) else {
            return nil
        }
        idx = nextIndex

        guard key == .length else {
            guard let skippedIndex = skipBencodeValue(bytes, startIndex: idx, upperBound: endIndex) else {
                return nil
            }
            idx = skippedIndex
            continue
        }

        guard let (value, valueEnd) = readBencodeIntegerOrSkip(
            bytes,
            startIndex: idx,
            upperBound: endIndex
        ) else {
            return nil
        }
        if let value {
            fileLength = value
        }
        idx = valueEnd
    }

    guard idx < endIndex, bytes[idx] == UInt8(ascii: "e") else { return nil }
    return (fileLength, idx + 1)
}

private struct FilesListParseResult {
    let totalSize: Int64
    let fileCount: Int
    let nextIndex: Int
}

private func parseFilesList(
    _ bytes: UnsafeBufferPointer<UInt8>,
    startIndex: Int,
    endIndex: Int
) -> FilesListParseResult? {
    guard startIndex < endIndex else { return nil }
    guard bytes[startIndex] == UInt8(ascii: "l") else {
        guard let nextIndex = skipBencodeValue(bytes, startIndex: startIndex, upperBound: endIndex) else {
            return nil
        }
        return FilesListParseResult(totalSize: 0, fileCount: 0, nextIndex: nextIndex)
    }

    var idx = startIndex + 1
    var totalSize: Int64 = 0
    var fileCount = 0

    while idx < endIndex, bytes[idx] != UInt8(ascii: "e") {
        guard bytes[idx] == UInt8(ascii: "d") else {
            guard let skippedIndex = skipBencodeValue(bytes, startIndex: idx, upperBound: endIndex) else {
                return nil
            }
            idx = skippedIndex
            continue
        }

        guard let parsedFile = parseFileDictionary(bytes, startIndex: idx, endIndex: endIndex) else {
            return nil
        }
        totalSize &+= parsedFile.fileLength
        fileCount &+= 1
        idx = parsedFile.nextIndex
    }

    guard idx < endIndex, bytes[idx] == UInt8(ascii: "e") else { return nil }
    return FilesListParseResult(totalSize: totalSize, fileCount: fileCount, nextIndex: idx + 1)
}

private func applyInfoDictionaryEntry(
    _ bytes: UnsafeBufferPointer<UInt8>,
    key: InfoDictionaryKey,
    valueStartIndex: Int,
    endIndex: Int,
    state: inout InfoDictionaryState
) -> Int? {
    switch key {
    case .nameUTF8, .name:
        guard let parsedName = readBencodeStringRange(bytes, startIndex: valueStartIndex, upperBound: endIndex) else {
            return nil
        }
        // `name.utf-8` should only win when it decodes cleanly. Legacy `name` bytes
        // are more forgiving so drag/drop previews still work for older torrents.
        let decodedName = decodeBencodeString(
            bytes,
            range: parsedName.range,
            allowLossyUTF8: key == .name
        )
        if let decodedName {
            state.applyName(decodedName, isUTF8: key == .nameUTF8)
        }
        return parsedName.nextIndex

    case .files:
        guard let parsedFiles = parseFilesList(bytes, startIndex: valueStartIndex, endIndex: endIndex) else {
            return nil
        }
        state.applyFiles(totalSize: parsedFiles.totalSize, fileCount: parsedFiles.fileCount)
        return parsedFiles.nextIndex

    case .length:
        guard let parsedLength = readBencodeIntegerOrSkip(
            bytes,
            startIndex: valueStartIndex,
            upperBound: endIndex
        ) else {
            return nil
        }
        if let value = parsedLength.value {
            state.applySingleFileLength(value)
        }
        return parsedLength.nextIndex

    case .other:
        return skipBencodeValue(bytes, startIndex: valueStartIndex, upperBound: endIndex)
    }
}

/// Parse the `info` dictionary for name, files/length quickly
private func parseInfoDictionary(_ bytes: UnsafeBufferPointer<UInt8>, startIndex: Int, endIndex: Int) -> TorrentInfo? {
    var idx = startIndex
    guard idx < endIndex, bytes[idx] == UInt8(ascii: "d") else { return nil }
    idx &+= 1

    var state = InfoDictionaryState()

    while idx < endIndex, bytes[idx] != UInt8(ascii: "e") {
        guard let (key, valueStartIndex) = readBencodeKey(bytes, startIndex: idx, upperBound: endIndex) else {
            return nil
        }
        guard let nextIndex = applyInfoDictionaryEntry(
            bytes,
            key: key,
            valueStartIndex: valueStartIndex,
            endIndex: endIndex,
            state: &state
        ) else {
            return nil
        }

        idx = nextIndex

        if let info = state.earlyResolvedInfo {
            return info
        }
    }

    return state.finalInfo
}
