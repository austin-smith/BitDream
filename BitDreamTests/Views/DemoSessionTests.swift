#if BITDREAM_SAMPLE_SUPPORT
import SwiftData
import XCTest
@testable import BitDream

@MainActor
final class DemoSessionTests: XCTestCase {
    func testDemoSessionIsIsolatedAndUsesRealStoreOperations() async throws {
        let preferencesBefore = UserDefaults.standard.persistentDomain(forName: AppIdentity.bundleIdentifier) as NSDictionary?
        let defaults = try isolatedDefaults()
        let environment = AppEnvironment(processEnvironment: ["BITDREAM_DEMO": "1"], demoUserDefaults: defaults)
        let session = try XCTUnwrap(environment.demoSession)
        XCTAssertTrue(environment.isDemo)
        XCTAssertNil(environment.screenshotConfiguration)
        XCTAssertNil(environment.screenshotWindowSize)
        XCTAssertNil(environment.screenshotDynamicTypeSize)
        XCTAssertNil(environment.presentationDate)
        XCTAssertEqual(environment.mainWindowID, "demo-main")
        XCTAssertEqual(environment.themeManager.themeMode, .system)
        XCTAssertTrue(defaults.inspectorVisibility)
        XCTAssertTrue(session.container.configurations.allSatisfy(\.isStoredInMemoryOnly))
        XCTAssertFalse(session.serverServices.allowsTailscale)
        let startedAt = Date()
        await environment.start()
        for _ in 0..<200 where session.store.torrents.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(session.store.connectionStatus, .connected)
        XCTAssertEqual(session.store.torrents.count, 7)
        let sorted = sortTorrents(session.store.torrents, by: defaults.sortProperty, order: defaults.sortOrder)
        XCTAssertEqual(sorted.first?.id, 4)
        XCTAssertEqual(Set(sorted.map(\.addedDate)).count, sorted.count)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(session.store.lastRefreshAt), startedAt)
        let detail = try await session.store.loadTorrentDetail(id: 1)
        XCTAssertEqual(detail.files.count, 3)
        let host = try await session.repository.create(draft: HostDraft(
            name: "Another sample", server: "real-address.example.invalid", port: 9091,
            username: "someone", isSSL: true, isDefault: false, password: "never-written"
        ))
        XCTAssertNil(host.credentialKey)
        XCTAssertEqual(session.serverServices.readPassword(host), "")
        let response = try await session.serverServices.testConnection(TransmissionConnectionDescriptor(host: host))
        XCTAssertEqual(response.version, SampleFixtures.sessionConfiguration.version)
        session.store.updatePollInterval(30)
        XCTAssertEqual(UserDefaults.standard.persistentDomain(forName: AppIdentity.bundleIdentifier) as NSDictionary?, preferencesBefore)
        session.store.clearSelectedHost()
    }

    func testRelaunchResetsHostsButPreservesDemoPreferences() async throws {
        let defaults = try isolatedDefaults()
        let first = DemoSession(userDefaults: defaults)
        first.userDefaults.set("Dark", forKey: "themeModeKey")
        first.userDefaults.sortProperty = .name
        first.userDefaults.sortOrder = .ascending
        _ = try await first.repository.create(draft: HostDraft(
            name: "Temporary", server: "temporary.invalid", port: 9091, username: "", isSSL: false, isDefault: false, password: ""
        ))
        let second = DemoSession(userDefaults: defaults)
        XCTAssertEqual(ThemeManager(userDefaults: second.userDefaults).themeMode, .dark)
        XCTAssertEqual(second.userDefaults.sortProperty, .name)
        XCTAssertEqual(second.userDefaults.sortOrder, .ascending)
        XCTAssertEqual(try second.container.mainContext.fetch(FetchDescriptor<BitDream.Host>()).count, 2)
    }

    func testServerSelectionShowsFailuresAndPreservesDemoLibrary() async throws {
        let session = DemoSession(userDefaults: try isolatedDefaults())
        let hosts = try session.container.mainContext.fetch(FetchDescriptor<BitDream.Host>(sortBy: [SortDescriptor(\.name)]))
        XCTAssertEqual(hosts.map(\.name), ["Demo Server", "Remote Server"])
        session.start()
        defer { session.store.clearSelectedHost() }
        for _ in 0..<200 where session.store.connectionStatus != .connected { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(session.store.host?.serverID, SampleLibrary.serverID)
        try await session.store.pauseTorrents(ids: [1])

        let remote = hosts[1]
        remote.name = "Renamed server"
        session.store.setHost(host: remote)
        for _ in 0..<200 where session.store.connectionState.failure == nil { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(session.store.connectionState.failure?.diagnosticCode, "unauthorized")
        XCTAssertTrue(session.store.torrents.isEmpty)
        XCTAssertNil(session.store.nextRetryAt)
        do {
            _ = try await session.serverServices.testConnection(TransmissionConnectionDescriptor(host: remote))
            XCTFail("Test Connection must match the selected server's failure")
        } catch let error as TransmissionError {
            XCTAssertEqual(error.diagnosticCode, "unauthorized")
        }

        session.store.setHost(host: hosts[0])
        for _ in 0..<200 where session.store.connectionStatus != .connected { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(session.store.connectionStatus, .connected)
        XCTAssertEqual(session.store.torrents.count, 7)
        XCTAssertEqual(session.store.torrents.first { $0.id == 1 }?.status, 0)
    }

    private func isolatedDefaults() throws -> UserDefaults {
        let name = "BitDreamTests.demo.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { @MainActor in defaults.removePersistentDomain(forName: name) }
        return defaults
    }
}
#endif
