import Foundation
import OSLog

struct HostRefreshRecord: Codable, Equatable, Sendable, Identifiable {
    let serverID: String
    let name: String
    let server: String
    let port: Int
    let username: String
    let isSSL: Bool
    let credentialKey: String
    let isDefault: Bool
    let version: String?

    var id: String { serverID }
}

struct HostRefreshCatalog: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let generatedAt: Date
    let records: [HostRefreshRecord]
}

actor HostRefreshCatalogStore {
    static let shared = HostRefreshCatalogStore()

    private static let fileName = "host_refresh_catalog_v1.json"
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "crapshack.BitDream",
        category: "HostRefreshCatalogStore"
    )

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.outputFormatting = [.sortedKeys]
    }

    func loadRecords() -> [HostRefreshRecord] {
        guard let catalog = loadCatalog() else {
            return []
        }
        return catalog.records
    }

    func replace(records: [HostRefreshRecord]) throws {
        let sortedRecords = Self.sortedRecords(records)
        let catalog = HostRefreshCatalog(
            schemaVersion: HostRefreshCatalog.currentSchemaVersion,
            generatedAt: Date(),
            records: sortedRecords
        )
        try writeCatalog(catalog)
    }

    nonisolated static func loadRecordsSnapshot() -> [HostRefreshRecord] {
        let decoder = JSONDecoder()

        let url: URL
        do {
            url = try catalogURL()
        } catch {
            logger.error("Failed to resolve catalog URL for snapshot read: \(error.localizedDescription, privacy: .public)")
            return []
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileReadNoSuchFileError {
                return []
            }
            logger.error("Failed to read catalog snapshot at \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return []
        }

        do {
            let catalog = try decoder.decode(HostRefreshCatalog.self, from: data)
            guard catalog.schemaVersion == HostRefreshCatalog.currentSchemaVersion else {
                logger.error("Ignoring catalog snapshot with schema \(catalog.schemaVersion, privacy: .public)")
                return []
            }
            return catalog.records
        } catch {
            logger.error("Failed to decode catalog snapshot: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    private func loadCatalog() -> HostRefreshCatalog? {
        let url: URL
        do {
            url = try Self.catalogURL(fileManager: fileManager)
        } catch {
            Self.logger.error("Failed to resolve catalog URL: \(error.localizedDescription, privacy: .public)")
            return nil
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileReadNoSuchFileError {
                return nil
            }
            Self.logger.error("Failed to read catalog: \(error.localizedDescription, privacy: .public)")
            return nil
        }

        do {
            let catalog = try decoder.decode(HostRefreshCatalog.self, from: data)
            guard catalog.schemaVersion == HostRefreshCatalog.currentSchemaVersion else {
                Self.logger.error("Ignoring catalog with schema \(catalog.schemaVersion, privacy: .public)")
                return nil
            }
            return catalog
        } catch {
            Self.logger.error("Failed to decode catalog JSON: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func writeCatalog(_ catalog: HostRefreshCatalog) throws {
        let url = try Self.catalogURL(fileManager: fileManager)
        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        do {
            let data = try encoder.encode(catalog)
            try data.write(to: url, options: [.atomic])
        } catch {
            Self.logger.error("Failed to write catalog: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    private static func sortedRecords(_ records: [HostRefreshRecord]) -> [HostRefreshRecord] {
        records.sorted { lhs, rhs in
            let compare = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            if compare == .orderedSame {
                return lhs.serverID < rhs.serverID
            }
            return compare == .orderedAscending
        }
    }

    private static func catalogURL(fileManager: FileManager = .default) throws -> URL {
        let appSupportDirectory = try applicationSupportDirectory(fileManager: fileManager)
        return appSupportDirectory.appendingPathComponent(fileName, isDirectory: false)
    }

    private static func applicationSupportDirectory(fileManager: FileManager) throws -> URL {
        guard let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw CocoaError(.fileNoSuchFile)
        }

        let bundleID = Bundle.main.bundleIdentifier ?? "crapshack.BitDream"
        return base.appendingPathComponent(bundleID, isDirectory: true)
    }
}
