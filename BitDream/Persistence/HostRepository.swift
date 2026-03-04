import Foundation
import OSLog
import SwiftData

struct HostDraft {
    var name: String
    var server: String
    var port: Int
    var username: String
    var isSSL: Bool
    var isDefault: Bool
    var password: String
}

enum HostPersistenceError: Error, LocalizedError {
    case validation(String)
    case notFound(String)
    case keychainFailure(String)
    case saveFailure(String)
    case catalogSyncFailure(String)

    var userMessage: String {
        switch self {
        case .validation(let message):
            return message
        case .notFound:
            return "The selected server no longer exists."
        case .keychainFailure:
            return "Could not update credentials in Keychain."
        case .saveFailure:
            return "Could not save server changes."
        case .catalogSyncFailure:
            return "Server saved, but widget refresh sync failed."
        }
    }

    var errorDescription: String? { userMessage }
}

@MainActor
protocol HostPersisting: AnyObject {
    func bootstrap() async
    func create(draft: HostDraft) async throws -> Host
    func update(serverID: String, draft: HostDraft) async throws -> Host
    func delete(serverID: String) async throws
    func setDefault(serverID: String) async throws
    func persistVersionIfNeeded(serverID: String, version: String) async
    func syncCatalog() async
}

@MainActor
final class HostRepository: HostPersisting {
    static let shared = HostRepository(
        modelContext: PersistenceController.shared.container.mainContext
    )

    private enum BootstrapState {
        case idle
        case inProgress
        case complete
    }

    private let modelContext: ModelContext
    private let catalogStore: HostRefreshCatalogStore
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "crapshack.BitDream",
        category: "HostRepository"
    )

    private var bootstrapState: BootstrapState = .idle

    init(modelContext: ModelContext, catalogStore: HostRefreshCatalogStore = .shared) {
        self.modelContext = modelContext
        self.catalogStore = catalogStore
    }

    func bootstrap() async {
        guard bootstrapState == .idle else { return }
        bootstrapState = .inProgress

        do {
            let hosts = try fetchHosts()
            _ = try ensureCredentialKeysAndSaveIfNeeded(hosts: hosts)
            try await syncCatalogInternal()
            bootstrapState = .complete
        } catch {
            rollbackChangesIfNeeded()
            bootstrapState = .idle
            logger.error("Bootstrap failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func create(draft: HostDraft) async throws -> Host {
        let normalizedDraft = try validatedDraft(draft)
        if normalizedDraft.isDefault {
            do {
                try clearDefault(except: nil)
            } catch {
                rollbackChangesIfNeeded()
                throw HostPersistenceError.saveFailure(error.localizedDescription)
            }
        }

        let host = Host(
            isDefault: normalizedDraft.isDefault,
            isSSL: normalizedDraft.isSSL,
            name: normalizedDraft.name,
            port: Int16(normalizedDraft.port),
            server: normalizedDraft.server,
            username: normalizedDraft.username
        )

        let credentialKey = host.ensureCredentialKey()
        guard KeychainPasswordStore.savePassword(normalizedDraft.password, credentialKey: credentialKey) else {
            rollbackChangesIfNeeded()
            throw HostPersistenceError.keychainFailure("Failed to write credentials")
        }

        modelContext.insert(host)
        do {
            try saveIfNeeded()
        } catch {
            rollbackChangesIfNeeded()
            _ = KeychainPasswordStore.deletePassword(credentialKey: credentialKey)
            throw HostPersistenceError.saveFailure(error.localizedDescription)
        }

        try await syncCatalogAfterUserMutation()
        return host
    }

    func update(serverID: String, draft: HostDraft) async throws -> Host {
        let normalizedDraft = try validatedDraft(draft)
        guard let host = try fetchHost(serverID: serverID) else {
            throw HostPersistenceError.notFound(serverID)
        }

        let previousCredentialKey = KeychainPasswordStore.credentialKeyIfPresent(for: host)
        let previousPassword = previousCredentialKey.map { KeychainPasswordStore.readPassword(credentialKey: $0) }

        if normalizedDraft.isDefault {
            do {
                try clearDefault(except: host.serverID)
            } catch {
                rollbackChangesIfNeeded()
                throw HostPersistenceError.saveFailure(error.localizedDescription)
            }
        }

        host.name = normalizedDraft.name
        host.server = normalizedDraft.server
        host.port = Int16(normalizedDraft.port)
        host.username = normalizedDraft.username
        host.isSSL = normalizedDraft.isSSL
        host.isDefault = normalizedDraft.isDefault

        let credentialKey = host.ensureCredentialKey()
        guard KeychainPasswordStore.savePassword(normalizedDraft.password, credentialKey: credentialKey) else {
            rollbackChangesIfNeeded()
            throw HostPersistenceError.keychainFailure("Failed to write credentials")
        }

        do {
            try saveIfNeeded()
        } catch {
            rollbackChangesIfNeeded()
            restoreKeychainAfterFailedSave(
                previousCredentialKey: previousCredentialKey,
                previousPassword: previousPassword,
                attemptedCredentialKey: credentialKey
            )
            throw HostPersistenceError.saveFailure(error.localizedDescription)
        }

        try await syncCatalogAfterUserMutation()
        return host
    }

    func delete(serverID: String) async throws {
        guard let host = try fetchHost(serverID: serverID) else {
            throw HostPersistenceError.notFound(serverID)
        }

        let credentialKey = KeychainPasswordStore.credentialKeyIfPresent(for: host)
        modelContext.delete(host)

        do {
            try saveIfNeeded()
        } catch {
            rollbackChangesIfNeeded()
            throw HostPersistenceError.saveFailure(error.localizedDescription)
        }

        if let credentialKey, !KeychainPasswordStore.deletePassword(credentialKey: credentialKey) {
            logger.error("Failed to remove credentials for deleted serverID=\(serverID, privacy: .public)")
        }

        try await syncCatalogAfterUserMutation()
    }

    func setDefault(serverID: String) async throws {
        let hosts: [Host]
        do {
            hosts = try fetchHosts()
        } catch {
            rollbackChangesIfNeeded()
            throw HostPersistenceError.saveFailure(error.localizedDescription)
        }
        guard hosts.contains(where: { $0.serverID == serverID }) else {
            throw HostPersistenceError.notFound(serverID)
        }

        var changed = false
        for host in hosts {
            let isDefault = (host.serverID == serverID)
            if host.isDefault != isDefault {
                host.isDefault = isDefault
                changed = true
            }
        }

        guard changed else { return }

        do {
            try saveIfNeeded()
        } catch {
            rollbackChangesIfNeeded()
            throw HostPersistenceError.saveFailure(error.localizedDescription)
        }

        try await syncCatalogAfterUserMutation()
    }

    func persistVersionIfNeeded(serverID: String, version: String) async {
        let trimmedVersion = version.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedVersion.isEmpty else { return }

        do {
            guard let host = try fetchHost(serverID: serverID) else { return }
            guard host.version != trimmedVersion else { return }
            host.version = trimmedVersion
            try saveIfNeeded()
            await syncCatalog()
        } catch {
            rollbackChangesIfNeeded()
            logger.error("Failed to persist host version for serverID=\(serverID, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    func syncCatalog() async {
        do {
            try await syncCatalogInternal()
        } catch {
            logger.error("Catalog sync failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func syncCatalogInternal() async throws {
        let hosts = try ensureCredentialKeysAndSaveIfNeeded(hosts: fetchHosts())

        let records = hosts.map { host in
            let name = (host.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return HostRefreshRecord(
                serverID: host.serverID,
                name: name,
                server: host.server ?? "",
                port: Int(host.port),
                username: host.username ?? "",
                isSSL: host.isSSL,
                credentialKey: host.credentialKey ?? "",
                isDefault: host.isDefault,
                version: host.version
            )
        }

        do {
            try await catalogStore.replace(records: records)
        } catch {
            throw HostPersistenceError.catalogSyncFailure(error.localizedDescription)
        }

        let summaries = records.map { ServerSummary(id: $0.serverID, name: $0.name) }
        writeServersIndex(servers: summaries)
    }

    private func syncCatalogAfterUserMutation() async throws {
        do {
            try await syncCatalogInternal()
        } catch {
            logger.error("Catalog sync failed after user mutation: \(error.localizedDescription, privacy: .public)")
            throw catalogSyncFailure(from: error)
        }
    }

    private func fetchHosts() throws -> [Host] {
        let descriptor = FetchDescriptor<Host>(
            sortBy: [Foundation.SortDescriptor(\Host.name)]
        )

        return try modelContext.fetch(descriptor)
    }

    private func fetchHost(serverID: String) throws -> Host? {
        let targetServerID = serverID
        let descriptor = FetchDescriptor<Host>(
            predicate: #Predicate<Host> { host in
                host.serverID == targetServerID
            }
        )
        return try modelContext.fetch(descriptor).first
    }

    private func validatedDraft(_ draft: HostDraft) throws -> HostDraft {
        let trimmedServer = draft.server.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedServer.isEmpty else {
            throw HostPersistenceError.validation("Hostname is required.")
        }

        guard (1...65535).contains(draft.port) else {
            throw HostPersistenceError.validation("Port must be between 1 and 65535.")
        }

        let trimmedName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmedName.isEmpty ? trimmedServer : trimmedName

        return HostDraft(
            name: finalName,
            server: trimmedServer,
            port: draft.port,
            username: draft.username.trimmingCharacters(in: .whitespacesAndNewlines),
            isSSL: draft.isSSL,
            isDefault: draft.isDefault,
            password: draft.password
        )
    }

    private func clearDefault(except serverID: String?) throws {
        for host in try fetchHosts() where host.isDefault && host.serverID != serverID {
            host.isDefault = false
        }
    }

    private func ensureCredentialKeysAndSaveIfNeeded(hosts: [Host]) throws -> [Host] {
        var changed = false

        for host in hosts {
            let previous = host.credentialKey
            _ = host.ensureCredentialKey()
            if previous != host.credentialKey {
                changed = true
            }
        }

        if changed {
            try saveIfNeeded()
        }

        return hosts
    }

    private func saveIfNeeded() throws {
        if modelContext.hasChanges {
            try modelContext.save()
        }
    }

    private func rollbackChangesIfNeeded() {
        if modelContext.hasChanges {
            modelContext.rollback()
        }
    }

    private func catalogSyncFailure(from error: Error) -> HostPersistenceError {
        if let persistenceError = error as? HostPersistenceError,
           case .catalogSyncFailure = persistenceError {
            return persistenceError
        }

        return HostPersistenceError.catalogSyncFailure(error.localizedDescription)
    }

    private func restoreKeychainAfterFailedSave(
        previousCredentialKey: String?,
        previousPassword: String?,
        attemptedCredentialKey: String
    ) {
        if let previousCredentialKey {
            if let previousPassword {
                _ = KeychainPasswordStore.savePassword(previousPassword, credentialKey: previousCredentialKey)
            }
            if previousCredentialKey != attemptedCredentialKey {
                _ = KeychainPasswordStore.deletePassword(credentialKey: attemptedCredentialKey)
            }
            return
        }

        _ = KeychainPasswordStore.deletePassword(credentialKey: attemptedCredentialKey)
    }
}
