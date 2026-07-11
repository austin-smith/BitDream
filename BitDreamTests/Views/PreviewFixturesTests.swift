import SwiftData
import XCTest
@testable import BitDream

#if DEBUG
@MainActor
final class PreviewFixturesTests: XCTestCase {
    func testConnectedScenarioIsDeterministicAndInternallyConsistent() {
        let hosts = PreviewFixtures.makeHosts()
        let store = PreviewFixtures.makeStore(scenario: .connected, selectedHost: hosts[0])

        XCTAssertEqual(store.host?.serverID, "preview-home")
        XCTAssertEqual(store.connectionStatus, .connected)
        XCTAssertEqual(store.torrents, PreviewFixtures.torrents)
        XCTAssertEqual(store.sessionStats?.torrentCount, PreviewFixtures.torrents.count)
        XCTAssertEqual(Set(store.torrents.map(\.id)).count, store.torrents.count)
        XCTAssertEqual(store.availableLabels, store.availableLabels.sorted())
    }

    func testFileFixturesStayAligned() {
        XCTAssertFalse(PreviewFixtures.files.isEmpty)
        XCTAssertEqual(PreviewFixtures.files.count, PreviewFixtures.fileStats.count)

        for (file, stats) in zip(PreviewFixtures.files, PreviewFixtures.fileStats) {
            XCTAssertEqual(file.bytesCompleted, stats.bytesCompleted)
            XCTAssertLessThanOrEqual(file.bytesCompleted, file.length)
        }
    }

    func testPreviewContainerUsesEphemeralSeededPersistence() throws {
        let hosts = PreviewFixtures.makeHosts()
        let container = PreviewFixtures.makeModelContainer(hosts: hosts)
        let fetchedHosts = try container.mainContext.fetch(FetchDescriptor<BitDream.Host>())

        XCTAssertEqual(Set(fetchedHosts.map(\.serverID)), Set(hosts.map(\.serverID)))
        XCTAssertTrue(container.configurations.allSatisfy { $0.isStoredInMemoryOnly })
    }

    func testPreviewStoreDoesNotScheduleAutomaticRetries() {
        let store = PreviewFixtures.makeStore(scenario: .connected)

        store.handleConnectionError(.timeout)

        XCTAssertEqual(store.connectionStatus, .reconnecting)
        XCTAssertNil(store.nextRetryAt)
    }

    func testPreviewHostRepositoryPersistsOnlyInMemoryWithoutCredentials() async throws {
        let environment = PreviewEnvironment()
        let host = try await environment.hostRepository.create(
            draft: HostDraft(
                name: "Preview Lab",
                server: "preview.invalid",
                port: 9091,
                username: "preview",
                isSSL: true,
                isDefault: false,
                password: "must-not-reach-keychain"
            )
        )
        let fetchedHosts = try environment.container.mainContext.fetch(FetchDescriptor<BitDream.Host>())

        XCTAssertTrue(fetchedHosts.contains { $0.serverID == host.serverID })
        XCTAssertNil(host.credentialKey)
    }

    func testPreviewDependenciesPersistOnlyToTheirInjectedPreferences() throws {
        let firstSuiteName = "BitDreamTests.preview.first.\(UUID().uuidString)"
        let secondSuiteName = "BitDreamTests.preview.second.\(UUID().uuidString)"
        let firstDefaults = try XCTUnwrap(UserDefaults(suiteName: firstSuiteName))
        let secondDefaults = try XCTUnwrap(UserDefaults(suiteName: secondSuiteName))
        defer {
            firstDefaults.removePersistentDomain(forName: firstSuiteName)
            secondDefaults.removePersistentDomain(forName: secondSuiteName)
        }
        let secondPollIntervalBefore = secondDefaults.object(forKey: UserDefaultsKeys.pollInterval) as? Double
        let secondThemeModeBefore = secondDefaults.string(forKey: "themeModeKey")

        let store = PreviewFixtures.makeStore(userDefaults: firstDefaults)
        let themeManager = ThemeManager(userDefaults: firstDefaults)
        store.updatePollInterval(30)
        themeManager.setThemeMode(.dark)

        XCTAssertEqual(firstDefaults.double(forKey: UserDefaultsKeys.pollInterval), 30)
        XCTAssertEqual(firstDefaults.string(forKey: "themeModeKey"), ThemeMode.dark.rawValue)
        XCTAssertEqual(
            secondDefaults.object(forKey: UserDefaultsKeys.pollInterval) as? Double,
            secondPollIntervalBefore
        )
        XCTAssertEqual(secondDefaults.string(forKey: "themeModeKey"), secondThemeModeBefore)
    }

    #if os(macOS)
    func testDisabledUpdaterIsInert() {
        let updater = AppUpdater(updatesEnabled: false)

        XCTAssertFalse(updater.canCheckForUpdates)
        XCTAssertNil(updater.lastUpdateCheckDate)
        updater.automaticallyChecksForUpdates = false
        updater.checkForUpdates()

        XCTAssertFalse(updater.automaticallyChecksForUpdates)
        XCTAssertFalse(updater.canCheckForUpdates)
    }
    #endif

    #if os(iOS)
    func testInertAppIconManagerUpdatesOnlyItsLocalState() async {
        let manager = AppIconManager.inert()

        manager.selectIcon(name: "Blue")
        await Task.yield()

        XCTAssertEqual(manager.currentIconName, "Blue")
        XCTAssertNil(manager.lastError)
    }
    #endif
}
#endif
