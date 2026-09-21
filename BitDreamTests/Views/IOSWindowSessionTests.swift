import XCTest
@testable import BitDream

@MainActor
final class IOSWindowSessionTests: XCTestCase {
    func testWindowsKeepServerSelectionAndPresentationsIndependent() {
        let first = makeSession()
        let second = makeSession()
        let original = Host(serverID: "original", server: "original.example.com")
        first.store.setHost(host: original)
        second.store.setHost(host: original)

        first.store.setHost(host: Host(serverID: "other", server: "other.example.com"))
        first.store.setup = true
        first.store.editServers = true
        first.store.showSettings = true
        first.store.isShowingAddAlert = true
        first.store.isError = true

        XCTAssertEqual(second.store.host?.serverID, "original")
        XCTAssertFalse(second.store.setup)
        XCTAssertFalse(second.store.editServers)
        XCTAssertFalse(second.store.showSettings)
        XCTAssertFalse(second.store.isShowingAddAlert)
        XCTAssertFalse(second.store.isError)
    }

    func testSavedServerEditsReachOtherWindowsUsingThatServerOnly() async throws {
        let first = makeSession()
        let second = makeSession()
        let unrelated = makeSession()
        let host = Host(serverID: "edited", server: "before.example.com")
        first.store.setHost(host: host)
        second.store.setHost(host: host)
        unrelated.store.setHost(host: Host(serverID: "unrelated", server: "other.example.com"))
        let secondGeneration = second.store.settingsConnectionGeneration
        let unrelatedGeneration = unrelated.store.settingsConnectionGeneration
        let updated = Host(serverID: "edited", server: "after.example.com")

        _ = try await updateExistingServer(
            host: host,
            draft: HostDraft(name: "Edited", server: "after.example.com", port: 9091,
                             username: "", isSSL: false, isDefault: false, password: ""),
            store: first.store,
            hostRepository: WindowTestHostRepository(updatedHost: updated)
        )

        XCTAssertEqual(second.store.host?.server, "after.example.com")
        XCTAssertNotEqual(second.store.settingsConnectionGeneration, secondGeneration)
        XCTAssertEqual(unrelated.store.settingsConnectionGeneration, unrelatedGeneration)
        XCTAssertFalse(second.store.editServers)
    }

    func testDeletingSharedServerUpdatesAffectedWindowsWithoutOpeningSheets() async throws {
        let first = makeSession()
        let second = makeSession()
        let host = Host(serverID: "deleted", server: "deleted.example.com")
        let remaining = Host(serverID: "remaining", server: "remaining.example.com")
        first.store.setHost(host: host)
        second.store.setHost(host: host)
        let repository = WindowTestHostRepository(updatedHost: remaining)

        try await deleteServer(host: host, store: first.store, hosts: [host, remaining], hostRepository: repository)
        XCTAssertEqual(first.store.host?.serverID, "remaining")
        XCTAssertEqual(second.store.host?.serverID, "remaining")

        try await deleteServer(host: remaining, store: first.store, hosts: [remaining], hostRepository: repository)
        XCTAssertNil(first.store.host)
        XCTAssertNil(second.store.host)
        XCTAssertFalse(second.store.setup)
    }

    func testFailedSaveDoesNotInvalidateOtherWindowsConnections() async {
        let first = makeSession()
        let second = makeSession()
        let host = Host(serverID: "unchanged", server: "unchanged.example.com")
        second.store.setHost(host: host)
        let generation = second.store.settingsConnectionGeneration
        let repository = WindowTestHostRepository(updatedHost: host)
        repository.shouldFail = true

        do {
            _ = try await updateExistingServer(
                host: host,
                draft: HostDraft(name: "Test", server: "unchanged.example.com", port: 9091,
                                 username: "", isSSL: false, isDefault: false, password: ""),
                store: first.store, hostRepository: repository
            )
            XCTFail("Expected save failure")
        } catch {
            XCTAssertEqual(second.store.settingsConnectionGeneration, generation)
        }
    }

    func testClosingWindowClearsOnlyItsConnectionLifecycle() async {
        var first: iOSWindowSession? = makeSession()
        let firstStore = first!.store
        let second = makeSession()
        let host = Host(serverID: "shared", server: "shared.example.com")
        firstStore.setHost(host: host)
        second.store.setHost(host: host)
        first = nil
        // An isolated deinit may hop to the main actor before cleanup completes.
        for _ in 0..<100 where firstStore.host != nil { await Task.yield() }

        XCTAssertNil(firstStore.host)
        XCTAssertEqual(second.store.host?.serverID, "shared")
    }

    private func makeSession() -> iOSWindowSession {
        let suiteName = "IOSWindowSessionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        return iOSWindowSession(store: TransmissionStore(
            resolveConnection: { _ in throw TransmissionError.invalidEndpointConfiguration },
            snapshotWriter: WidgetSnapshotWriter(
                writeServerIndex: { _ in },
                writeSessionSnapshot: { _, _, _, _, _ in },
                reloadTimelines: {}
            ),
            userDefaults: defaults,
            automaticallyRetriesConnection: false,
            persistVersion: { _, _ in }
        ))
    }
}

@MainActor
private final class WindowTestHostRepository: HostPersisting {
    let updatedHost: BitDream.Host
    var shouldFail = false

    init(updatedHost: BitDream.Host) { self.updatedHost = updatedHost }
    func bootstrap() async {}
    func create(draft: HostDraft) async throws -> BitDream.Host { updatedHost }
    func update(serverID: String, draft: HostDraft) async throws -> BitDream.Host {
        if shouldFail { throw HostPersistenceError.saveFailure("test failure") }
        return updatedHost
    }
    func delete(serverID: String) async throws {}
    func setDefault(serverID: String) async throws {}
    func persistVersionIfNeeded(serverID: String, version: String) async {}
    func syncCatalog() async {}
}
