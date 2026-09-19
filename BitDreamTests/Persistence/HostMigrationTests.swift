import SwiftData
import XCTest
@testable import BitDream

/// The original, unversioned entity shape. The nested type intentionally retains
/// the persisted entity name "Host" so this exercises a real on-disk upgrade.
private enum LegacyHostSchema {
    @Model
    final class Host {
        @Attribute(.unique) var serverID: String
        var isDefault: Bool
        var isSSL: Bool
        var credentialKey: String?
        var name: String?
        var port: Int16
        var server: String?
        var username: String?
        var version: String?

        init() {
            serverID = "legacy-server"
            isDefault = true
            isSSL = false
            credentialKey = "existing-key"
            name = "NAS"
            port = 9091
            server = "nas.local"
            username = "user"
            version = "4.0.6"
        }
    }
}

@MainActor
final class HostMigrationTests: XCTestCase {
    func testExistingStoreMigratesWithoutLosingIdentityOrCredentialsAndSupportsHighPorts() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "hosts.store")
        try autoreleasepool {
            let schema = Schema([LegacyHostSchema.Host.self])
            let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            container.mainContext.insert(LegacyHostSchema.Host())
            try container.mainContext.save()
        }
        try autoreleasepool {
            let schema = Schema([BitDream.Host.self])
            let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let host = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<BitDream.Host>()).first)
            XCTAssertEqual(host.serverID, "legacy-server")
            XCTAssertEqual(host.credentialKey, "existing-key")
            XCTAssertEqual(host.port, 9091)
            XCTAssertEqual(TransmissionConnectionDescriptor(host: host).connectionRoute, "system")
            host.port = 65535
            host.connectionRoute = "tailscale"
            host.tailscaleAccountID = "account-a"
            try container.mainContext.save()
        }
        let schema = Schema([BitDream.Host.self])
        let container = try ModelContainer(
            for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)]
        )
        let host = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<BitDream.Host>()).first)
        XCTAssertEqual(host.port, 65535)
        XCTAssertEqual(host.tailscaleAccountID, "account-a")
        XCTAssertEqual(host.serverID, "legacy-server")
    }
}
