//  Shared helpers for App Group file access used by the app and widgets.

import Foundation
import CryptoKit

enum AppGroup {
    /// App Group identifier shared by the app and widget extension
    static let identifier: String = "group.crapshack.BitDream"

    /// Container URL for the shared App Group
    static func containerURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    enum Files {
        static let serversIndexFilename: String = "servers.json"

        static func serversIndexURL() -> URL? {
            AppGroup.containerURL()?.appendingPathComponent(serversIndexFilename, isDirectory: false)
        }

        /// Generates a safe filename for a per-server session snapshot
        static func sessionFilename(for serverId: String) -> String {
            let hash = serverId.sha256Hex
            return "session_\(hash).json"
        }

        static func sessionURL(for serverId: String) -> URL? {
            AppGroup.containerURL()?.appendingPathComponent(sessionFilename(for: serverId), isDirectory: false)
        }
    }
}

extension String {
    /// Stable hex-encoded SHA256 for safe filenames
    var sha256Hex: String {
        let digest = SHA256.hash(data: Data(self.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

enum AppGroupJSON {
    /// Reads and decodes JSON from a file URL
    static func read<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(T.self, from: data)
    }

    /// Encodes and writes JSON to a file URL (atomic)
    @discardableResult
    static func write<T: Encodable>(_ value: T, to url: URL) -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value) else { return false }

        do {
            let directory = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            let tmpURL = directory.appendingPathComponent(UUID().uuidString)
            try data.write(to: tmpURL, options: .atomic)
            try? FileManager.default.removeItem(at: url)
            try FileManager.default.moveItem(at: tmpURL, to: url)
            return true
        } catch {
            return false
        }
    }
}


