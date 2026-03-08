import Foundation
import XCTest
@testable import BitDream

@MainActor
final class TransmissionStoreSessionOperationTests: XCTestCase {
    private struct SupersededSaveScenario {
        let sender: HostMethodScriptedSender
        let store: TransmissionStore
        let args: TransmissionSessionSetRequestArgs
    }

    func testApplySessionSettingsRefreshesSessionConfiguration() async throws {
        let sender = MethodQueueSender(stepsByMethod: [
            "session-stats": [
                .http(statusCode: 200, body: successStatsBody)
            ],
            "torrent-get": [
                .http(statusCode: 200, body: try loadTransmissionFixture(named: "torrent-get.response.json"))
            ],
            "session-get": [
                .http(statusCode: 200, body: try sessionSettingsBody(downloadDir: "/downloads/initial", version: "4.0.0")),
                .http(statusCode: 200, body: try sessionSettingsBody(downloadDir: "/downloads/updated", version: "4.0.1"))
            ],
            "session-set": [
                .http(statusCode: 200, body: successEmptyBody)
            ]
        ])
        let sleepController = ScriptedSleep(steps: [.suspend])
        let store = makeStore(sender: sender, sleepController: sleepController)
        var args = TransmissionSessionSetRequestArgs()
        args.downloadDir = "/downloads/updated"

        store.setHost(host: makeHost(serverID: "server-1", server: "example.com"))
        let didLoadInitialConfiguration = await waitUntil {
            store.defaultDownloadDir == "/downloads/initial"
        }
        XCTAssertTrue(didLoadInitialConfiguration)

        let refreshed = try await store.applySessionSettings(args)

        XCTAssertEqual(refreshed.downloadDir, "/downloads/updated")
        XCTAssertEqual(store.sessionConfiguration?.downloadDir, "/downloads/updated")
        XCTAssertEqual(store.defaultDownloadDir, "/downloads/updated")
    }

    func testApplySessionSettingsIgnoresSupersededResultsAfterHostSwitch() async throws {
        let scenario = try makeSupersededSaveScenario()

        scenario.store.setHost(host: makeHost(serverID: "server-1", server: "old.example.com"))
        let didLoadOldConfiguration = await waitUntil {
            scenario.store.defaultDownloadDir == "/downloads/old"
        }
        XCTAssertTrue(didLoadOldConfiguration)

        let saveTask = Task {
            try? await scenario.store.applySessionSettings(scenario.args)
        }

        let startedOldSave = await didStartOldSave(scenario.sender)
        XCTAssertTrue(startedOldSave)

        scenario.store.setHost(host: makeHost(serverID: "server-2", server: "new.example.com"))
        let switchedHosts = await didSwitchHosts(scenario.store)
        XCTAssertTrue(switchedHosts)

        await scenario.sender.resume(id: "old-save")
        _ = await saveTask.result

        XCTAssertEqual(scenario.store.host?.serverID, "server-2")
        XCTAssertEqual(scenario.store.defaultDownloadDir, "/downloads/new")
        XCTAssertEqual(scenario.store.sessionConfiguration?.downloadDir, "/downloads/new")
    }

    func testUpdateBlocklistRefreshesCanonicalSessionConfiguration() async throws {
        let sender = MethodQueueSender(stepsByMethod: [
            "session-stats": [
                .http(statusCode: 200, body: successStatsBody)
            ],
            "torrent-get": [
                .http(statusCode: 200, body: try loadTransmissionFixture(named: "torrent-get.response.json"))
            ],
            "session-get": [
                .http(statusCode: 200, body: try sessionSettingsBody(downloadDir: "/downloads/initial", version: "4.0.0", blocklistSize: 0)),
                .http(statusCode: 200, body: try sessionSettingsBody(downloadDir: "/downloads/initial", version: "4.0.0", blocklistSize: 42))
            ],
            "blocklist-update": [
                .http(statusCode: 200, body: #"{"result":"success","arguments":{"blocklist-size":42}}"#)
            ]
        ])
        let sleepController = ScriptedSleep(steps: [.suspend])
        let store = makeStore(sender: sender, sleepController: sleepController)

        store.setHost(host: makeHost(serverID: "server-1", server: "example.com"))
        let didLoadInitialBlocklistSize = await waitUntil {
            store.sessionConfiguration?.blocklistSize == 0
        }
        XCTAssertTrue(didLoadInitialBlocklistSize)

        let response = try await store.updateBlocklist()

        XCTAssertEqual(response.blocklistSize, 42)
        XCTAssertEqual(store.sessionConfiguration?.blocklistSize, 42)
    }
}

private extension TransmissionStoreSessionOperationTests {
    private func makeSupersededSaveScenario() throws -> SupersededSaveScenario {
        let sender = HostMethodScriptedSender(stepsByHostAndMethod: [
            "old.example.com": [
                "session-stats": [
                    .http(statusCode: 200, body: successStatsBody)
                ],
                "torrent-get": [
                    .http(statusCode: 200, body: try loadTransmissionFixture(named: "torrent-get.response.json"))
                ],
                "session-get": [
                    .http(statusCode: 200, body: try sessionSettingsBody(downloadDir: "/downloads/old", version: "4.0.0")),
                    .http(statusCode: 200, body: try sessionSettingsBody(downloadDir: "/downloads/stale", version: "4.0.1"))
                ],
                "session-set": [
                    .blocked(id: "old-save", statusCode: 200, body: successEmptyBody)
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
                    .http(statusCode: 200, body: try sessionSettingsBody(downloadDir: "/downloads/new", version: "5.0.0"))
                ]
            ]
        ])
        let sleepController = ScriptedSleep(steps: [.suspend])
        let store = makeStore(sender: sender, sleepController: sleepController)
        var args = TransmissionSessionSetRequestArgs()
        args.downloadDir = "/downloads/stale"
        return SupersededSaveScenario(sender: sender, store: store, args: args)
    }

    func didStartOldSave(_ sender: HostMethodScriptedSender) async -> Bool {
        await waitUntil {
            let requests = await sender.capturedRequests()
            return requests.count == 4
        }
    }

    func didSwitchHosts(_ store: TransmissionStore) async -> Bool {
        await waitUntil {
            store.host?.serverID == "server-2" && store.defaultDownloadDir == "/downloads/new"
        }
    }

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

    func resume(id: String) {
        continuations.removeValue(forKey: id)?.resume()
    }

    private func waitForResume(id: String) async {
        await withCheckedContinuation { continuation in
            continuations[id] = continuation
        }
    }
}

private func sessionSettingsBody(downloadDir: String, version: String, blocklistSize: Int = 0) throws -> String {
    let data = Data(try loadTransmissionFixture(named: "session-get.response.json").utf8)
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    var arguments = try XCTUnwrap(object["arguments"] as? [String: Any])
    arguments["download-dir"] = downloadDir
    arguments["version"] = version
    arguments["blocklist-size"] = blocklistSize
    object["arguments"] = arguments
    let encoded = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    return try XCTUnwrap(String(bytes: encoded, encoding: .utf8))
}
