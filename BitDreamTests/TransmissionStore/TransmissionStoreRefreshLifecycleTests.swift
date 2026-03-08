import Foundation
import XCTest
@testable import BitDream

@MainActor
final class TransmissionStoreRefreshLifecycleTests: XCTestCase {
    func testInitialHostSelectionPerformsFullRefreshAndStartsPolling() async throws {
        let sender = MethodQueueSender(stepsByMethod: [
            "session-stats": [
                .http(statusCode: 200, body: successStatsBody)
            ],
            "torrent-get": [
                .http(statusCode: 200, body: try loadTransmissionFixture(named: "torrent-get.response.json"))
            ],
            "session-get": [
                .http(statusCode: 200, body: try sessionSettingsBody(downloadDir: "/downloads/primary", version: "4.0.0"))
            ]
        ])
        let sleepController = ScriptedSleep(steps: [.suspend])
        let recorder = TestWidgetSnapshotRecorder()
        let store = makeStore(
            sender: sender,
            sleepController: sleepController,
            recorder: recorder
        )
        let host = makeHost(serverID: "server-1", server: "example.com")

        store.setHost(host: host)

        let didConnect = await waitUntil {
            store.connectionStatus == .connected && store.sessionConfiguration != nil
        }
        XCTAssertTrue(didConnect)
        XCTAssertEqual(store.sessionStats?.torrentCount, 4)
        XCTAssertFalse(store.torrents.isEmpty)
        XCTAssertEqual(store.defaultDownloadDir, "/downloads/primary")
        let didStartPolling = await waitUntil {
            await sleepController.callCount() == 1
        }
        XCTAssertTrue(didStartPolling)
        let sleepCallCount = await sleepController.callCount()
        XCTAssertEqual(sleepCallCount, 1)
        XCTAssertEqual(recorder.sessionSnapshotCount, 1)
    }

    func testReconnectOnSameHostIsNotANoOp() async throws {
        let sender = MethodQueueSender(stepsByMethod: [
            "session-stats": [
                .http(statusCode: 200, body: successStatsBody),
                .http(statusCode: 200, body: successStatsBody)
            ],
            "torrent-get": [
                .http(statusCode: 200, body: try loadTransmissionFixture(named: "torrent-get.response.json")),
                .http(statusCode: 200, body: try loadTransmissionFixture(named: "torrent-get.response.json"))
            ],
            "session-get": [
                .http(statusCode: 200, body: try sessionSettingsBody(downloadDir: "/downloads/initial", version: "4.0.0")),
                .http(statusCode: 200, body: try sessionSettingsBody(downloadDir: "/downloads/reconnect", version: "4.0.1"))
            ]
        ])
        let sleepController = ScriptedSleep(steps: [.suspend, .suspend])
        let store = makeStore(sender: sender, sleepController: sleepController)
        let host = makeHost(serverID: "server-1", server: "example.com")

        store.setHost(host: host)
        let initialConnect = await waitUntil { store.connectionStatus == .connected }
        XCTAssertTrue(initialConnect)
        let initialRequestCount = (await sender.capturedRequests()).count
        XCTAssertEqual(initialRequestCount, 3)

        store.reconnect()

        let reconnected = await waitUntil {
            (await sender.capturedRequests()).count == 6 &&
                store.defaultDownloadDir == "/downloads/reconnect"
        }
        XCTAssertTrue(reconnected)
        XCTAssertEqual(store.defaultDownloadDir, "/downloads/reconnect")
    }

    func testSupersededHostResultsAreIgnoredAfterHostSwitch() async throws {
        let sender = HostMethodScriptedSender(stepsByHostAndMethod: [
            "old.example.com": [
                "session-stats": [
                    .blocked(id: "old-stats", statusCode: 200, body: successStatsBody)
                ],
                "torrent-get": [
                    .http(statusCode: 200, body: try loadTransmissionFixture(named: "torrent-get.response.json"))
                ],
                "session-get": [
                    .http(statusCode: 200, body: try sessionSettingsBody(downloadDir: "/downloads/old", version: "1.0.0"))
                ]
            ],
            "new.example.com": [
                "session-stats": [
                    .http(statusCode: 200, body: successStatsBody)
                ],
                "torrent-get": [
                    .http(statusCode: 200, body: try loadTransmissionFixture(named: "torrent-get.response.json"))
                ],
                "session-get": [
                    .http(statusCode: 200, body: try sessionSettingsBody(downloadDir: "/downloads/new", version: "2.0.0"))
                ]
            ]
        ])
        let sleepController = ScriptedSleep(steps: [.suspend])
        let store = makeStore(sender: sender, sleepController: sleepController)

        store.setHost(host: makeHost(serverID: "old-server", server: "old.example.com"))
        store.setHost(host: makeHost(serverID: "new-server", server: "new.example.com"))

        let didSwitch = await waitUntil {
            store.host?.serverID == "new-server" && store.defaultDownloadDir == "/downloads/new"
        }
        XCTAssertTrue(didSwitch)

        await sender.resume(id: "old-stats")
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(store.host?.serverID, "new-server")
        XCTAssertEqual(store.defaultDownloadDir, "/downloads/new")
    }

    func testPollFailureSchedulesRetryAndRecoversToConnected() async throws {
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
                .http(statusCode: 200, body: try sessionSettingsBody(downloadDir: "/downloads/retried", version: "4.0.1"))
            ]
        ])
        let sleepController = ScriptedSleep(steps: [.immediate, .immediate, .suspend])
        let store = makeStore(sender: sender, sleepController: sleepController)

        store.setHost(host: makeHost(serverID: "server-1", server: "example.com"))

        let recovered = await waitUntil {
            store.connectionStatus == .connected && store.defaultDownloadDir == "/downloads/retried"
        }
        XCTAssertTrue(recovered)
        let didResumePolling = await waitUntil {
            await sleepController.callCount() == 3
        }
        XCTAssertTrue(didResumePolling)
        let sleepCallCount = await sleepController.callCount()
        XCTAssertEqual(sleepCallCount, 3)
        XCTAssertEqual(store.lastErrorMessage, "")
        XCTAssertNil(store.nextRetryAt)
    }

    func testSessionOnlyRefreshUpdatesSessionConfiguration() async throws {
        let sender = MethodQueueSender(stepsByMethod: [
            "session-stats": [
                .http(statusCode: 200, body: successStatsBody)
            ],
            "torrent-get": [
                .http(statusCode: 200, body: try loadTransmissionFixture(named: "torrent-get.response.json"))
            ],
            "session-get": [
                .http(statusCode: 200, body: try sessionSettingsBody(downloadDir: "/downloads/initial", version: "4.0.0")),
                .http(statusCode: 200, body: try sessionSettingsBody(downloadDir: "/downloads/updated", version: "4.0.2"))
            ]
        ])
        let sleepController = ScriptedSleep(steps: [.suspend])
        let store = makeStore(sender: sender, sleepController: sleepController)

        store.setHost(host: makeHost(serverID: "server-1", server: "example.com"))
        let initialRefresh = await waitUntil { store.defaultDownloadDir == "/downloads/initial" }
        XCTAssertTrue(initialRefresh)

        store.refreshSessionConfiguration()

        let updatedRefresh = await waitUntil { store.defaultDownloadDir == "/downloads/updated" }
        XCTAssertTrue(updatedRefresh)
    }

    func testInitialActivationFailuresPreserveBackoffAcrossAutomaticRetries() async {
        let sender = MethodQueueSender(stepsByMethod: [:])
        let sleepController = ScriptedSleep(steps: [.immediate, .immediate, .suspend])
        let store = makeStore(sender: sender, sleepController: sleepController)

        store.setHost(host: makeHost(serverID: "server-1", server: ""))

        let didScheduleThreeRetries = await waitUntil {
            await sleepController.callCount() == 3
        }
        XCTAssertTrue(didScheduleThreeRetries)

        let recordedSleeps = await sleepController.recordedSleeps()
        XCTAssertEqual(recordedSleeps.count, 3)
        XCTAssertLessThan(recordedSleeps[0], recordedSleeps[1])
        XCTAssertLessThan(recordedSleeps[1], recordedSleeps[2])
        XCTAssertEqual(store.connectionStatus, .reconnecting)
        XCTAssertNil(store.sessionStats)
        XCTAssertNil(store.sessionConfiguration)
    }
}

private extension TransmissionStoreRefreshLifecycleTests {
    func makeStore(
        sender: some TransmissionRPCRequestSending,
        sleepController: ScriptedSleep,
        recorder: TestWidgetSnapshotRecorder = TestWidgetSnapshotRecorder()
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
            snapshotWriter: recorder.writer,
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

private final class TestWidgetSnapshotRecorder: @unchecked Sendable {
    struct SessionWrite: Equatable {
        let serverID: String
        let serverName: String
        let stats: SessionStats
        let torrents: [Torrent]
        let reloadTimelines: Bool
    }

    private let lock = NSLock()
    private(set) var serverIndexes: [[ServerSummary]] = []
    private(set) var sessionWrites: [SessionWrite] = []
    private(set) var reloadCount = 0

    var writer: WidgetSnapshotWriter {
        WidgetSnapshotWriter(
            writeServerIndex: { [weak self] summaries in
                self?.recordServerIndex(summaries)
            },
            writeSessionSnapshot: { [weak self] serverID, serverName, stats, torrents, reloadTimelines in
                self?.recordSessionSnapshot(
                    SessionWrite(
                        serverID: serverID,
                        serverName: serverName,
                        stats: stats,
                        torrents: torrents,
                        reloadTimelines: reloadTimelines
                    )
                )
            },
            reloadTimelines: { [weak self] in
                self?.recordReload()
            }
        )
    }

    var sessionSnapshotCount: Int {
        lock.withLock {
            sessionWrites.count
        }
    }

    var serverIndexCount: Int {
        lock.withLock {
            serverIndexes.count
        }
    }

    private func recordServerIndex(_ summaries: [ServerSummary]) {
        lock.withLock {
            serverIndexes.append(summaries)
        }
    }

    private func recordSessionSnapshot(_ write: SessionWrite) {
        lock.withLock {
            sessionWrites.append(write)
        }
    }

    private func recordReload() {
        lock.withLock {
            reloadCount += 1
        }
    }
}

private actor ScriptedSleep {
    enum Step {
        case immediate
        case suspend
    }

    private var steps: [Step]
    private var calls: [TimeInterval] = []

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
        }
    }

    func callCount() -> Int {
        calls.count
    }

    func recordedSleeps() -> [TimeInterval] {
        calls
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}

private func sessionSettingsBody(downloadDir: String, version: String) throws -> String {
    let data = Data(try loadTransmissionFixture(named: "session-get.response.json").utf8)
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    var arguments = try XCTUnwrap(object["arguments"] as? [String: Any])
    arguments["download-dir"] = downloadDir
    arguments["version"] = version
    object["arguments"] = arguments
    let encoded = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    return try XCTUnwrap(String(bytes: encoded, encoding: .utf8))
}
