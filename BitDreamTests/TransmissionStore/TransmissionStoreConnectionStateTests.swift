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

    func testStartupDeadlineCancelsBlockedWorkAndSchedulesRecovery() async {
        let resolver = SuspendedStartupResolver()
        let store = TransmissionStore(
            resolveConnection: { try await resolver.resolve($0) }, snapshotWriter: .noop,
            sleep: { _ in try await Task.sleep(for: .seconds(60)) },
            connectionAttemptTimeout: .milliseconds(100), persistVersion: { _, _ in }
        )
        defer { store.clearSelectedHost() }
        store.setHost(host: makeHost())
        let failed = await waitUntil { store.nextRetryAt != nil }
        XCTAssertTrue(failed)
        XCTAssertEqual(store.connectionTitle, "Unable to connect")
        XCTAssertEqual(store.connectionState.failure?.diagnosticCode, "timeout")
        XCTAssertFalse(store.needsConnectionSettings)
        let cancelled = await resolver.cancelled
        XCTAssertTrue(cancelled, "The deadline must cancel work, not just change presentation")
    }

    func testEstablishedReadsTimeOutCancelRequestsAndRecoverOnBothRoutes() async throws {
        for route in ["system", "tailscale"] {
            let sender = StallingRefreshSender()
            let connection = TransmissionConnection(
                endpoint: try TransmissionEndpoint(scheme: "http", host: "example.com", port: 9091),
                auth: TransmissionAuth(username: "", password: ""),
                transport: TransmissionTransport(sender: sender)
            )
            let store = TransmissionStore(
                resolveConnection: { _ in connection }, snapshotWriter: .noop,
                sleep: { _ in try await sender.waitForPoll() }, automaticallyRetriesConnection: false,
                connectionAttemptTimeout: .milliseconds(100), persistVersion: { _, _ in }
            )
            let host = makeHost()
            host.connectionRoute = route
            store.setHost(host: host)
            let connected = await waitUntil { store.connectionStatus == .connected }
            XCTAssertTrue(connected)
            let lastSnapshot = store.lastRefreshAt

            await sender.stallAndStartPolling()
            let disconnected = await waitUntil { store.connectionState.failure != nil }
            XCTAssertTrue(disconnected, "A stalled established connection must surface a failure")
            XCTAssertEqual(store.connectionTitle, "Connection lost")
            XCTAssertEqual(store.connectionState.failure?.diagnosticCode, "timeout")
            XCTAssertEqual(store.lastRefreshAt, lastSnapshot)
            let cancelledPolls = await sender.cancelledRequests
            XCTAssertEqual(cancelledPolls, 2)

            let refreshOutcome = await store.refreshNow()
            XCTAssertEqual(refreshOutcome, .failed)
            let cancelledAfterRefresh = await sender.cancelledRequests
            XCTAssertEqual(cancelledAfterRefresh, 5, "Full refresh must also cancel its stalled RPC requests")
            await sender.restore()
            let recovered = await store.refreshNow()
            XCTAssertEqual(recovered, .succeeded)
            XCTAssertEqual(store.connectionStatus, .connected)
            store.clearSelectedHost()
        }
    }

    func testSwitchingServersCancelsStartupWithoutPublishingItsFailure() async throws {
        let resolver = SuspendedStartupResolver()
        let store = TransmissionStore(
            resolveConnection: { try await resolver.resolve($0) }, snapshotWriter: .noop,
            persistVersion: { _, _ in }
        )
        store.setHost(host: makeHost())
        let started = await waitUntil { await resolver.started }
        XCTAssertTrue(started)
        store.clearSelectedHost()
        let cancelled = await waitUntil { await resolver.cancelled }
        XCTAssertTrue(cancelled)
        XCTAssertNil(store.connectionState.failure)
        XCTAssertNil(store.nextRetryAt)
        XCTAssertFalse(store.hasLoadedSnapshot)
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

private actor SuspendedStartupResolver {
    private(set) var started = false
    private(set) var cancelled = false
    func resolve(_ descriptor: TransmissionConnectionDescriptor) async throws -> TransmissionConnection {
        started = true
        do { try await Task.sleep(for: .seconds(60)) } catch {
            cancelled = true
            throw error
        }
        throw TransmissionError.timeout
    }
}

private actor StallingRefreshSender: TransmissionRPCRequestSending {
    private var stalled = false
    private var pollStarted = false
    private(set) var cancelledRequests = 0

    func stallAndStartPolling() { stalled = true }
    func restore() { stalled = false }

    func waitForPoll() async throws {
        if pollStarted { try await Task.sleep(for: .seconds(60)); return }
        while !stalled { try await Task.sleep(for: .milliseconds(1)) }
        pollStarted = true
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        if stalled {
            do { try await Task.sleep(for: .seconds(60)) } catch {
                cancelledRequests += 1
                throw error
            }
        }
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any]
        let method = body?["method"] as? String
        let response = method == "session-stats" ? successStatsBody
            : method == "torrent-get" ? "{\"result\":\"success\",\"arguments\":{\"torrents\":[]}}"
            : try loadTransmissionFixture(named: "session-get.response.json")
        return (Data(response.utf8), makeHTTPResponse(for: request.url!, statusCode: 200))
    }
}
