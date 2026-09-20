import Foundation
import XCTest
@testable import BitDream

@MainActor
final class TransmissionStoreRetrySchedulingTests: XCTestCase {
    func testManualRefreshFailureDuringReconnectPreservesPendingRetryAndRecovers() async throws {
        let sender = MethodQueueSender(stepsByMethod: [
            "session-stats": [
                .http(statusCode: 200, body: successStatsBody),
                .error(TestError.offline),
                .error(TestError.offline),
                .http(statusCode: 200, body: successStatsBody)
            ],
            "torrent-get": [
                .http(statusCode: 200, body: try loadTransmissionFixture(named: "torrent-get.response.json")),
                .error(TestError.offline),
                .error(TestError.offline),
                .http(statusCode: 200, body: try loadTransmissionFixture(named: "torrent-get.response.json"))
            ],
            "session-get": [
                .http(statusCode: 200, body: try sessionSettingsBody(downloadDir: "/downloads/initial", version: "4.0.0")),
                .error(TestError.offline),
                .http(statusCode: 200, body: try sessionSettingsBody(downloadDir: "/downloads/recovered", version: "4.0.1"))
            ]
        ])
        let sleepController = ScriptedSleep(steps: [.immediate, .blocked(id: "scheduled-retry"), .suspend])
        let store = makeStore(sender: sender, sleepController: sleepController)

        store.setHost(host: makeHost(serverID: "server-1", server: "example.com"))

        let enteredReconnectState = await waitUntil {
            store.connectionStatus == TransmissionStore.ConnectionStatus.reconnecting && store.nextRetryAt != nil
        }
        XCTAssertTrue(enteredReconnectState)

        let retryScheduled = await waitUntil {
            await sleepController.callCount() == 2
        }
        XCTAssertTrue(retryScheduled)

        guard let scheduledRetryAt = store.nextRetryAt else {
            XCTFail("Expected pending retry to be scheduled")
            return
        }

        await store.refreshNow()

        XCTAssertEqual(store.connectionStatus, TransmissionStore.ConnectionStatus.reconnecting)
        XCTAssertEqual(store.nextRetryAt, scheduledRetryAt)
        let sleepCountAfterManualFailure = await sleepController.callCount()
        XCTAssertEqual(sleepCountAfterManualFailure, 2)

        await sleepController.resume(id: "scheduled-retry")

        let recovered = await waitUntil {
            store.connectionStatus == TransmissionStore.ConnectionStatus.connected &&
                store.defaultDownloadDir == "/downloads/recovered"
        }
        XCTAssertTrue(recovered)
        XCTAssertNil(store.nextRetryAt)
        XCTAssertEqual(store.lastErrorMessage, "")
    }

    func testMissingRetryTaskIsRepairedWithoutConsumingBackoff() async throws {
        let sender = MethodQueueSender(stepsByMethod: [
            "session-stats": [
                .http(statusCode: 200, body: successStatsBody),
                .error(TestError.offline)
            ],
            "torrent-get": [
                .http(statusCode: 200, body: try loadTransmissionFixture(named: "torrent-get.response.json")),
                .error(TestError.offline)
            ],
            "session-get": [
                .http(statusCode: 200, body: try sessionSettingsBody(downloadDir: "/downloads/initial", version: "4.0.0")),
                .error(TestError.offline)
            ]
        ])
        let sleepController = ScriptedSleep(steps: [.suspend, .blocked(id: "repaired-retry"), .blocked(id: "next-backoff")])
        let store = makeStore(sender: sender, sleepController: sleepController)

        store.setHost(host: makeHost(serverID: "server-1", server: "example.com"))
        let connected = await waitUntil { store.connectionStatus == TransmissionStore.ConnectionStatus.connected }
        XCTAssertTrue(connected)

        store.connectionState = .failed(.timeout, retryAt: Date().addingTimeInterval(10))
        store.handleConnectionError(TransmissionError.transport(underlyingDescription: "Offline"))

        let repairedRetryScheduled = await waitUntil {
            await sleepController.callCount() == 2
        }
        XCTAssertTrue(repairedRetryScheduled)

        await sleepController.resume(id: "repaired-retry")

        let nextBackoffScheduled = await waitUntil {
            await sleepController.callCount() == 3
        }
        XCTAssertTrue(nextBackoffScheduled)

        let recordedSleeps = await sleepController.recordedSleeps()
        XCTAssertEqual(recordedSleeps.count, 3)
        XCTAssertGreaterThanOrEqual(recordedSleeps[2], 1)
        XCTAssertLessThan(recordedSleeps[2], 1.2)
        XCTAssertEqual(store.connectionStatus, TransmissionStore.ConnectionStatus.reconnecting)
        XCTAssertNotNil(store.nextRetryAt)
    }

    func testSuccessfulManualRefreshWhileReconnectingClearsPendingRetry() async throws {
        let sender = MethodQueueSender(stepsByMethod: [
            "session-stats": [
                .http(statusCode: 200, body: successStatsBody),
                .error(TestError.offline),
                .http(statusCode: 200, body: successStatsBody)
            ],
            "torrent-get": [
                .http(statusCode: 200, body: try loadTransmissionFixture(named: "torrent-get.response.json")),
                .error(TestError.offline),
                .http(statusCode: 200, body: try loadTransmissionFixture(named: "torrent-get.response.json"))
            ],
            "session-get": [
                .http(statusCode: 200, body: try sessionSettingsBody(downloadDir: "/downloads/initial", version: "4.0.0")),
                .http(statusCode: 200, body: try sessionSettingsBody(downloadDir: "/downloads/manual", version: "4.0.1"))
            ]
        ])
        let sleepController = ScriptedSleep(steps: [.immediate, .blocked(id: "scheduled-retry"), .suspend])
        let store = makeStore(sender: sender, sleepController: sleepController)

        store.setHost(host: makeHost(serverID: "server-1", server: "example.com"))

        let enteredReconnectState = await waitUntil {
            store.connectionStatus == TransmissionStore.ConnectionStatus.reconnecting && store.nextRetryAt != nil
        }
        XCTAssertTrue(enteredReconnectState)

        await store.refreshNow()

        let recovered = await waitUntil {
            store.connectionStatus == TransmissionStore.ConnectionStatus.connected &&
                store.defaultDownloadDir == "/downloads/manual"
        }
        XCTAssertTrue(recovered)
        XCTAssertNil(store.nextRetryAt)
        XCTAssertEqual(store.lastErrorMessage, "")
    }

    func testRepeatedSessionConflictAutomaticallyRecoversWithNewestToken() async throws {
        let sender = MethodQueueSender(stepsByMethod: [
            "session-stats": [
                .http(statusCode: 409, body: "", headers: [transmissionSessionTokenHeader: "first-token"]),
                .http(statusCode: 409, body: "", headers: [transmissionSessionTokenHeader: "newest-token"]),
                .http(statusCode: 200, body: successStatsBody)
            ],
            "torrent-get": Array(
                repeating: .http(statusCode: 200, body: try loadTransmissionFixture(named: "torrent-get.response.json")),
                count: 2
            ),
            "session-get": Array(repeating: .error(TestError.offline), count: 2)
        ])
        let sleepController = ScriptedSleep(steps: [.blocked(id: "conflict-retry"), .suspend])
        let store = makeStore(sender: sender, sleepController: sleepController)
        defer { store.clearSelectedHost() }
        store.setHost(host: makeHost(serverID: "server-1", server: "example.com"))

        let failed = await waitUntil { store.connectionState.failure != nil }
        XCTAssertTrue(failed)
        XCTAssertEqual(store.connectionState.failure?.diagnosticCode, "http.409")
        XCTAssertFalse(store.needsConnectionSettings)
        XCTAssertNotNil(store.nextRetryAt)
        let scheduled = await waitUntil { await sleepController.callCount() == 1 }
        XCTAssertTrue(scheduled)
        await sleepController.resume(id: "conflict-retry")

        let recovered = await waitUntil { store.connectionStatus == .connected }
        XCTAssertTrue(recovered)
        XCTAssertNil(store.nextRetryAt)
        let requests = await sender.capturedRequests()
        let statsRequests = try requests.filter { request in
            let body = try XCTUnwrap(request.body)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            return object["method"] as? String == "session-stats"
        }
        XCTAssertEqual(statsRequests.count, 3)
        XCTAssertEqual(statsRequests.last?.sessionToken, "newest-token")
    }

    func testActionableErrorCancelsThePendingRetryEvenIfItsSleepResumes() async throws {
        let sender = MethodQueueSender(stepsByMethod: [
            "session-stats": [.http(statusCode: 200, body: successStatsBody)],
            "torrent-get": [.http(statusCode: 200, body: try loadTransmissionFixture(named: "torrent-get.response.json"))],
            "session-get": [.error(TestError.offline)]
        ])
        let sleepController = ScriptedSleep(steps: [.suspend, .blocked(id: "cancelled-retry")])
        let store = makeStore(sender: sender, sleepController: sleepController)
        defer { store.clearSelectedHost() }
        store.setHost(host: makeHost(serverID: "server-1", server: "example.com"))
        let connected = await waitUntil {
            let count = await sleepController.callCount()
            return store.connectionStatus == .connected && count == 1
        }
        XCTAssertTrue(connected)
        store.handleConnectionError(.timeout)
        let scheduled = await waitUntil { await sleepController.callCount() == 2 }
        XCTAssertTrue(scheduled)

        store.handleConnectionError(.unauthorized)
        await sleepController.resume(id: "cancelled-retry")
        for _ in 0..<20 { await Task.yield() }
        XCTAssertTrue(store.needsConnectionSettings)
        XCTAssertNil(store.nextRetryAt)
        let requests = await sender.capturedRequests()
        XCTAssertEqual(requests.count, 3, "A cancelled retry must not start another request")
    }

    func testRetryNowResetsBackoffAndDoesNotInheritScheduledRetry() async throws {
        let sender = MethodQueueSender(stepsByMethod: [
            "session-stats": [
                .http(statusCode: 200, body: successStatsBody),
                .error(TestError.offline),
                .error(TestError.offline)
            ],
            "torrent-get": [
                .http(statusCode: 200, body: try loadTransmissionFixture(named: "torrent-get.response.json")),
                .error(TestError.offline),
                .error(TestError.offline)
            ],
            "session-get": [
                .http(statusCode: 200, body: try sessionSettingsBody(downloadDir: "/downloads/initial", version: "4.0.0")),
                .error(TestError.offline)
            ]
        ])
        let sleepController = ScriptedSleep(steps: [.immediate, .blocked(id: "scheduled-retry"), .blocked(id: "retry-now-backoff")])
        let store = makeStore(sender: sender, sleepController: sleepController)

        store.setHost(host: makeHost(serverID: "server-1", server: "example.com"))

        let enteredReconnectState = await waitUntil {
            store.connectionStatus == TransmissionStore.ConnectionStatus.reconnecting && store.nextRetryAt != nil
        }
        XCTAssertTrue(enteredReconnectState)

        store.retryNow()

        let replacementRetryScheduled = await waitUntil {
            await sleepController.callCount() == 3
        }
        XCTAssertTrue(replacementRetryScheduled)

        let recordedSleeps = await sleepController.recordedSleeps()
        XCTAssertEqual(recordedSleeps.count, 3)
        XCTAssertGreaterThanOrEqual(recordedSleeps[2], 1)
        XCTAssertLessThan(recordedSleeps[2], 1.2)
        XCTAssertEqual(store.connectionStatus, TransmissionStore.ConnectionStatus.reconnecting)
        XCTAssertNotNil(store.nextRetryAt)
    }
}

private extension TransmissionStoreRetrySchedulingTests {
    func makeStore(
        sender: some TransmissionRPCRequestSending,
        sleepController: ScriptedSleep
    ) -> TransmissionStore {
        let factory = TransmissionConnectionFactory(
            transport: TransmissionTransport(sender: sender),
            credentialResolver: TransmissionCredentialResolver(resolvePassword: { source in
                switch source {
                case .resolvedPassword(let password):
                    return password
                case .keychainCredential(let key):
                    return key == "test-key" ? "secret" : ""
                }
            })
        )

        return TransmissionStore(
            connectionFactory: factory,
            snapshotWriter: WidgetSnapshotWriter(
                writeServerIndex: { _ in },
                writeSessionSnapshot: { _, _, _, _, _ in },
                reloadTimelines: { }
            ),
            sleep: { seconds in
                try await sleepController.sleep(seconds: seconds)
            },
            persistVersion: { _, _ in }
        )
    }

    func makeHost(serverID: String, server: String) -> BitDream.Host {
        BitDream.Host(
            serverID: serverID,
            isDefault: false,
            isSSL: false,
            credentialKey: "test-key",
            name: serverID,
            port: 9091,
            server: server,
            username: "demo",
            version: nil
        )
    }

    func waitUntil(
        timeout: TimeInterval = 1,
        _ predicate: @escaping @MainActor () async -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await predicate() {
                return true
            }
            await Task.yield()
        }
        return false
    }
}

private actor ScriptedSleep {
    enum Step {
        case immediate
        case suspend
        case blocked(id: String)
    }

    private var steps: [Step]
    private var calls: [TimeInterval] = []
    private var continuations: [String: CheckedContinuation<Void, Never>] = [:]

    init(steps: [Step]) {
        self.steps = steps
    }

    func sleep(seconds: TimeInterval) async throws {
        calls.append(seconds)
        let step = steps.isEmpty ? .suspend : steps.removeFirst()

        switch step {
        case .immediate:
            return
        case .suspend:
            try await Task.sleep(nanoseconds: .max)
        case .blocked(let id):
            await withTaskCancellationHandler {
                await waitForResume(id: id)
            } onCancel: {
                Task {
                    await self.resume(id: id)
                }
            }
        }
    }

    func callCount() -> Int {
        calls.count
    }

    func recordedSleeps() -> [TimeInterval] {
        calls
    }

    func resume(id: String) {
        continuations.removeValue(forKey: id)?.resume()
    }

    private func waitForResume(id: String) async {
        await withCheckedContinuation { continuation in
            continuations[id] = continuation
        }
    }
}
