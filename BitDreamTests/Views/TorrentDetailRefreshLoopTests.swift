import XCTest
@testable import BitDream

@MainActor
final class TorrentDetailRefreshLoopTests: XCTestCase {
    func testActiveLoadFinishesAndPollingRevisionsCoalesce() async throws {
        let scenario = try makeScenario()
        var errors: [String] = []

        scenario.transmissionStore.setHost(
            host: makeHost(serverID: "server-1", server: "example.com")
        )
        let didConnect = await waitUntil {
            scenario.transmissionStore.connectionStatus == .connected
        }
        XCTAssertTrue(didConnect)
        let identity = makeIdentity(for: scenario.transmissionStore)

        let observationTask = makeObservationTask(
            for: scenario,
            identity: identity
        ) { errors.append($0) }
        let didStartInitialDetail = await waitUntil {
            await self.torrentGetRequestCount(sender: scenario.sender) == 2
        }
        XCTAssertTrue(didStartInitialDetail)

        let explicitLoadTask = makeExplicitLoadTask(
            for: scenario,
            identity: identity
        ) { errors.append($0) }
        await Task.yield()
        let requestCountWithExplicitLoadQueued = await torrentGetRequestCount(sender: scenario.sender)
        XCTAssertEqual(requestCountWithExplicitLoadQueued, 2)

        await scenario.transmissionStore.refreshNow()
        await scenario.transmissionStore.refreshNow()

        let requestCountWhileBlocked = await torrentGetRequestCount(sender: scenario.sender)
        XCTAssertEqual(requestCountWhileBlocked, 4)
        XCTAssertEqual(scenario.supplementalStore.status, .loading)
        XCTAssertFalse(scenario.supplementalStore.shouldDisplayPayload(for: identity))

        await scenario.sender.resume(id: "initial-detail")
        await explicitLoadTask.value
        let didFinishCatchUpRefresh = await waitUntil {
            scenario.supplementalStore.status == .failed
        }
        XCTAssertTrue(didFinishCatchUpRefresh)
        let finalRequestCount = await torrentGetRequestCount(sender: scenario.sender)
        XCTAssertEqual(finalRequestCount, 6)
        XCTAssertEqual(
            scenario.supplementalStore.payload(for: identity).files.first?.bytesCompleted,
            2
        )
        XCTAssertTrue(scenario.supplementalStore.shouldDisplayPayload(for: identity))
        XCTAssertEqual(errors, [])

        observationTask.cancel()
        await observationTask.value
    }

    func testQueuedRefreshRechecksInitialErrorStateWhenItFails() async throws {
        let scenario = try makeQueuedFailureScenario()
        var errors: [String] = []

        scenario.transmissionStore.setHost(
            host: makeHost(serverID: "server-1", server: "example.com")
        )
        let didConnect = await waitUntil {
            scenario.transmissionStore.connectionStatus == .connected
        }
        XCTAssertTrue(didConnect)
        let identity = makeIdentity(for: scenario.transmissionStore)

        let initialRefresh = makeRefreshTask(
            for: scenario,
            identity: identity
        ) { errors.append($0) }
        let didStartInitialDetail = await waitUntil {
            await self.torrentGetRequestCount(sender: scenario.sender) == 2
        }
        XCTAssertTrue(didStartInitialDetail)

        let queuedRefresh = makeRefreshTask(
            for: scenario,
            identity: identity
        ) { errors.append($0) }
        await Task.yield()
        await scenario.sender.resume(id: "initial-detail")
        await initialRefresh.value
        await queuedRefresh.value

        XCTAssertEqual(scenario.supplementalStore.status, .failed)
        XCTAssertEqual(
            scenario.supplementalStore.payload(for: identity).files.first?.bytesCompleted,
            1
        )
        XCTAssertTrue(scenario.supplementalStore.shouldDisplayPayload(for: identity))
        XCTAssertEqual(errors, [])
    }
}

@MainActor
private extension TorrentDetailRefreshLoopTests {
    struct Scenario {
        let sender: HostMethodScriptedSender
        let transmissionStore: TransmissionStore
        let supplementalStore: TorrentDetailSupplementalStore
    }

    func makeScenario() throws -> Scenario {
        let sender = HostMethodScriptedSender(stepsByHostAndMethod: [
            "example.com": [
                "session-stats": threeSuccessfulSessionStatsSteps(),
                "torrent-get": try torrentGetSteps(),
                "session-get": try threeSuccessfulSessionSettingsSteps()
            ]
        ])
        return Scenario(
            sender: sender,
            transmissionStore: makeStore(sender: sender),
            supplementalStore: TorrentDetailSupplementalStore()
        )
    }

    func makeQueuedFailureScenario() throws -> Scenario {
        let summary = try loadTransmissionFixture(named: "torrent-get.response.json")
        let sender = HostMethodScriptedSender(stepsByHostAndMethod: [
            "example.com": [
                "session-stats": [.http(statusCode: 200, body: successStatsBody)],
                "torrent-get": [
                    .http(statusCode: 200, body: summary),
                    .blocked(
                        id: "initial-detail",
                        statusCode: 200,
                        body: makeTorrentDetailSuccessBody(bytesCompleted: 1)
                    ),
                    .http(statusCode: 200, body: detailFailureBody())
                ],
                "session-get": [
                    .http(
                        statusCode: 200,
                        body: try sessionSettingsBody(downloadDir: "/downloads", version: "4.0.0")
                    )
                ]
            ]
        ])
        return Scenario(
            sender: sender,
            transmissionStore: makeStore(sender: sender),
            supplementalStore: TorrentDetailSupplementalStore()
        )
    }

    func makeIdentity(for store: TransmissionStore) -> TorrentDetailIdentity {
        TorrentDetailIdentity(
            torrentID: 42,
            connectionGeneration: store.torrentDetailRefreshTrigger.connectionGeneration
        )
    }

    func makeObservationTask(
        for scenario: Scenario,
        identity: TorrentDetailIdentity,
        onError: @escaping @MainActor @Sendable (String) -> Void
    ) -> Task<Void, Never> {
        return Task { @MainActor in
            await scenario.supplementalStore.observeRefreshes(
                for: identity,
                using: scenario.transmissionStore,
                onInitialLoadError: onError
            )
        }
    }

    func makeExplicitLoadTask(
        for scenario: Scenario,
        identity: TorrentDetailIdentity,
        onError: @escaping @MainActor @Sendable (String) -> Void
    ) -> Task<Void, Never> {
        Task { @MainActor in
            await scenario.supplementalStore.load(
                for: identity,
                using: scenario.transmissionStore,
                onError: onError
            )
        }
    }

    func makeRefreshTask(
        for scenario: Scenario,
        identity: TorrentDetailIdentity,
        onError: @escaping @MainActor @Sendable (String) -> Void
    ) -> Task<Void, Never> {
        Task { @MainActor in
            await scenario.supplementalStore.refresh(
                for: identity,
                using: scenario.transmissionStore,
                onInitialLoadError: onError
            )
        }
    }

    func threeSuccessfulSessionStatsSteps() -> [HostMethodScriptedSender.Step] {
        Array(repeating: .http(statusCode: 200, body: successStatsBody), count: 3)
    }

    func threeSuccessfulSessionSettingsSteps() throws -> [HostMethodScriptedSender.Step] {
        let body = try sessionSettingsBody(downloadDir: "/downloads", version: "4.0.0")
        return Array(repeating: .http(statusCode: 200, body: body), count: 3)
    }

    func torrentGetSteps() throws -> [HostMethodScriptedSender.Step] {
        let summary = try loadTransmissionFixture(named: "torrent-get.response.json")
        return [
            .http(statusCode: 200, body: summary),
            .blocked(
                id: "initial-detail",
                statusCode: 200,
                body: makeTorrentDetailSuccessBody(bytesCompleted: 1)
            ),
            .http(statusCode: 200, body: summary),
            .http(statusCode: 200, body: summary),
            .http(statusCode: 200, body: makeTorrentDetailSuccessBody(bytesCompleted: 2)),
            .http(statusCode: 200, body: detailFailureBody())
        ]
    }

    func detailFailureBody() -> String {
        """
        {
          "arguments": {},
          "result": "background refresh failed"
        }
        """
    }

    func torrentGetRequestCount(sender: HostMethodScriptedSender) async -> Int {
        await sender.capturedRequests().count { request in
            let urlRequest = request.asURLRequest()
            return (try? requestMethod(from: urlRequest)) == "torrent-get"
        }
    }
}
