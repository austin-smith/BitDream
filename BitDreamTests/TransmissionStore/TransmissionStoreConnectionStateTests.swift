import XCTest
@testable import BitDream

@MainActor
final class TransmissionStoreConnectionStateTests: XCTestCase {
    func testStartupIsLoadingUntilAValidEmptySnapshotArrives() async throws {
        let sender = HostMethodScriptedSender(stepsByHostAndMethod: [
            "example.com": [
                "session-stats": [.blocked(id: "stats", statusCode: 200, body: successStatsBody)],
                "torrent-get": [.http(statusCode: 200, body: "{\"result\":\"success\",\"arguments\":{\"torrents\":[]}}")],
                "session-get": [.error(TestError.offline)]
            ]
        ])
        let store = makeStore(sender: sender)
        defer { store.clearSelectedHost() }
        store.setHost(host: makeHost())
        let requested = await waitUntil { await sender.capturedRequests().count == 3 }
        XCTAssertTrue(requested)
        XCTAssertEqual(store.connectionTitle, "Connecting…")
        XCTAssertFalse(store.hasLoadedSnapshot)
        XCTAssertTrue(store.torrents.isEmpty)
        XCTAssertNil(store.connectionState.failure)
        XCTAssertFalse(store.canAttemptReconnect)

        let explicitRefresh = Task { await store.refreshNow() }
        for _ in 0..<20 { await Task.yield() }
        let countWhileStarting = await sender.capturedRequests().count
        XCTAssertEqual(countWhileStarting, 3, "Refreshing during initial activation must join the same attempt")
        await sender.resume(id: "stats")
        let refreshOutcome = await explicitRefresh.value
        XCTAssertEqual(refreshOutcome, .succeeded)
        let connected = await waitUntil { store.connectionStatus == .connected }
        XCTAssertTrue(connected)
        XCTAssertTrue(store.hasLoadedSnapshot, "An empty successful response differs from not loaded")
        XCTAssertTrue(store.torrents.isEmpty)
    }

    func testRetryRetainsLoadedDataAndCoalescesRepeatedClicks() async throws {
        let torrents = try loadTransmissionFixture(named: "torrent-get.response.json")
        let sender = HostMethodScriptedSender(stepsByHostAndMethod: [
            "example.com": [
                "session-stats": [
                    .http(statusCode: 200, body: successStatsBody),
                    .blocked(id: "retry", statusCode: 200, body: successStatsBody)
                ],
                "torrent-get": Array(repeating: .http(statusCode: 200, body: torrents), count: 2),
                "session-get": Array(repeating: .error(TestError.offline), count: 2)
            ]
        ])
        let store = makeStore(sender: sender)
        defer { store.clearSelectedHost() }
        store.setHost(host: makeHost())
        let connected = await waitUntil { store.connectionStatus == .connected }
        XCTAssertTrue(connected)
        let previousRefresh = store.lastRefreshAt
        let previousIDs = store.torrents.map(\.id)
        store.handleConnectionError(.tailscale(.connectionFailed))
        XCTAssertEqual(store.connectionTitle, "Connection lost")

        store.retryNow()
        store.retryNow()
        let startedRetry = await waitUntil { await sender.capturedRequests().count == 6 }
        XCTAssertTrue(startedRetry)
        XCTAssertEqual(store.connectionTitle, "Reconnecting…")
        XCTAssertEqual(store.torrents.map(\.id), previousIDs)
        XCTAssertEqual(store.lastRefreshAt, previousRefresh)
        XCTAssertNil(store.nextRetryAt)
        XCTAssertFalse(store.canAttemptReconnect)
        await sender.resume(id: "retry")
        let recovered = await waitUntil { store.connectionStatus == .connected }
        XCTAssertTrue(recovered)
        let count = await sender.capturedRequests().count
        XCTAssertEqual(count, 6)

        store.setHost(host: makeHost(id: "other", address: "other.example.com"))
        XCTAssertFalse(store.hasLoadedSnapshot)
        XCTAssertTrue(store.torrents.isEmpty)
        XCTAssertNil(store.sessionStats)
        XCTAssertEqual(store.connectionTitle, "Connecting…")
    }

    func testAuthenticationAndConfigurationFailuresStopAutomaticRetries() async {
        let cases: [TransmissionError] = [
            .invalidEndpointConfiguration, .unauthorized, .tailscale(.signInRequired),
            .tailscale(.approvalRequired), .tailscale(.accountMismatch), .tailscale(.ambiguousPeer),
            .network(.serverCertificateUntrusted)
        ]
        for error in cases {
            let store = TransmissionStore(
                resolveConnection: { _ in throw error },
                snapshotWriter: .noop,
                persistVersion: { _, _ in }
            )
            store.setHost(host: makeHost())
            let failed = await waitUntil { store.connectionState.failure != nil }
            XCTAssertTrue(failed)
            XCTAssertTrue(store.needsConnectionSettings, error.diagnosticCode)
            XCTAssertNil(store.nextRetryAt)
            XCTAssertFalse(store.hasLoadedSnapshot)
            XCTAssertEqual(store.connectionState.failure?.diagnosticCode, error.diagnosticCode)
            store.clearSelectedHost()
        }
    }

    func testTransientStartupFailureIsNotReportedAsLostConnectionOrBadSettings() async {
        for error in [TailscaleError.peerUnavailable, .connectionFailed] {
            let store = TransmissionStore(
                resolveConnection: { _ in throw error }, snapshotWriter: .noop,
                sleep: { _ in try await Task.sleep(for: .seconds(60)) },
                persistVersion: { _, _ in }
            )
            store.setHost(host: makeHost())
            let failed = await waitUntil { store.nextRetryAt != nil }
            XCTAssertTrue(failed)
            XCTAssertEqual(store.connectionTitle, "Unable to connect")
            XCTAssertFalse(store.needsConnectionSettings)
            XCTAssertFalse(store.hasLoadedSnapshot)
            XCTAssertEqual(store.connectionState.failure?.diagnosticCode, "tailscale.\(error)")
            XCTAssertFalse(store.lastErrorMessage.contains("bad URL"))
            store.clearSelectedHost()
        }
    }

    func testExplicitRefreshRestartsActivationAfterSignInIsRestored() async throws {
        let sender = MethodQueueSender(stepsByMethod: [
            "session-stats": [.http(statusCode: 200, body: successStatsBody)],
            "torrent-get": [.http(statusCode: 200, body: "{\"result\":\"success\",\"arguments\":{\"torrents\":[]}}")],
            "session-get": [.error(TestError.offline)]
        ])
        let resolver = RestoredLoginResolver(factory: TransmissionConnectionFactory(
            transport: TransmissionTransport(sender: sender),
            credentialResolver: TransmissionCredentialResolver(resolvePassword: { _ in "" })
        ))
        let store = TransmissionStore(
            resolveConnection: { try await resolver.resolve($0) }, snapshotWriter: .noop,
            sleep: { _ in try await Task.sleep(for: .seconds(60)) }, persistVersion: { _, _ in }
        )
        defer { store.clearSelectedHost() }
        store.setHost(host: makeHost())
        let needsLogin = await waitUntil { store.needsConnectionSettings }
        XCTAssertTrue(needsLogin)
        await resolver.restoreLogin()
        let outcome = await store.refreshNow()
        XCTAssertEqual(outcome, .succeeded)
        XCTAssertEqual(store.connectionStatus, .connected)
        XCTAssertTrue(store.hasLoadedSnapshot)
        let attempts = await resolver.attempts
        XCTAssertEqual(attempts, 2)
    }

    func testCancellationDoesNotReplaceConnectionStateWithAnError() {
        let store = makeStore(sender: QueueSender(steps: []))
        store.markConnecting()
        store.handleConnectionError(.cancelled)
        XCTAssertEqual(store.connectionTitle, "Connecting…")
        XCTAssertNil(store.connectionState.failure)
        XCTAssertNil(store.nextRetryAt)
    }

    private func makeStore(sender: some TransmissionRPCRequestSending) -> TransmissionStore {
        TransmissionStore(
            connectionFactory: TransmissionConnectionFactory(
                transport: TransmissionTransport(sender: sender),
                credentialResolver: TransmissionCredentialResolver(resolvePassword: { _ in "" })
            ),
            snapshotWriter: .noop,
            sleep: { _ in try await Task.sleep(for: .seconds(60)) },
            automaticallyRetriesConnection: false,
            persistVersion: { _, _ in }
        )
    }

    private func makeHost(id: String = "server", address: String = "example.com") -> BitDream.Host {
        BitDream.Host(serverID: id, isDefault: false, isSSL: false, credentialKey: "",
                      name: id, port: 9091, server: address, username: "", version: nil)
    }

    private func waitUntil(_ predicate: @escaping @MainActor () async -> Bool) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while ContinuousClock.now < deadline {
            if await predicate() { return true }
            await Task.yield()
        }
        return false
    }
}

private extension WidgetSnapshotWriter {
    static var noop: Self {
        Self(writeServerIndex: { _ in }, writeSessionSnapshot: { _, _, _, _, _ in }, reloadTimelines: {})
    }
}

private actor RestoredLoginResolver {
    let factory: TransmissionConnectionFactory
    private var signedIn = false
    private(set) var attempts = 0

    init(factory: TransmissionConnectionFactory) { self.factory = factory }
    func restoreLogin() { signedIn = true }
    func resolve(_ descriptor: TransmissionConnectionDescriptor) async throws -> TransmissionConnection {
        attempts += 1
        guard signedIn else { throw TailscaleError.signInRequired }
        return try await factory.connection(for: descriptor)
    }
}
