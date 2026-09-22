#if BITDREAM_SAMPLE_SUPPORT
import Foundation
import SwiftData

@MainActor
final class SampleHostRepository: HostPersisting {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func bootstrap() async {}

    func create(draft: HostDraft) async throws -> Host {
        let host = Host(
            isDefault: draft.isDefault,
            isSSL: draft.isSSL,
            name: draft.name,
            port: draft.port,
            server: draft.server,
            username: draft.username,
            connectionRoute: draft.connectionRoute,
            tailscaleAccountID: draft.tailscaleAccountID
        )
        if draft.isDefault {
            try clearDefaults(except: nil)
        }
        modelContext.insert(host)
        try modelContext.save()
        return host
    }

    func update(serverID: String, draft: HostDraft) async throws -> Host {
        guard let host = try fetchHost(serverID: serverID) else {
            throw HostPersistenceError.notFound(serverID)
        }
        if draft.isDefault {
            try clearDefaults(except: serverID)
        }
        host.name = draft.name
        host.server = draft.server
        host.port = draft.port
        host.username = draft.username
        host.isSSL = draft.isSSL
        host.isDefault = draft.isDefault
        host.connectionRoute = draft.connectionRoute
        host.tailscaleAccountID = draft.tailscaleAccountID
        try modelContext.save()
        return host
    }

    func delete(serverID: String) async throws {
        guard let host = try fetchHost(serverID: serverID) else {
            throw HostPersistenceError.notFound(serverID)
        }
        modelContext.delete(host)
        try modelContext.save()
    }

    func setDefault(serverID: String) async throws {
        guard try fetchHost(serverID: serverID) != nil else {
            throw HostPersistenceError.notFound(serverID)
        }
        try clearDefaults(except: serverID)
        try modelContext.save()
    }

    func persistVersionIfNeeded(serverID: String, version: String) async {
        guard let host = try? fetchHost(serverID: serverID), host.version != version else { return }
        host.version = version
        try? modelContext.save()
    }

    func syncCatalog() async {}

    private func fetchHost(serverID: String) throws -> Host? {
        let descriptor = FetchDescriptor<Host>(
            predicate: #Predicate<Host> { $0.serverID == serverID }
        )
        return try modelContext.fetch(descriptor).first
    }

    private func clearDefaults(except serverID: String?) throws {
        let hosts = try modelContext.fetch(FetchDescriptor<Host>())
        for host in hosts {
            host.isDefault = host.serverID == serverID
        }
    }
}

#endif
