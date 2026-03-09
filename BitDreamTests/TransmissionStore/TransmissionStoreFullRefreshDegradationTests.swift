import Foundation
import XCTest
@testable import BitDream

@MainActor
final class TransmissionStoreFullRefreshTests: XCTestCase {
    func testInitialFullRefreshConnectsWhenSessionSettingsFail() async throws {
        let sender = MethodQueueSender(stepsByMethod: [
            "session-stats": [
                .http(statusCode: 200, body: successStatsBody)
            ],
            "torrent-get": [
                .http(statusCode: 200, body: try loadTransmissionFixture(named: "torrent-get.response.json"))
            ],
            "session-get": [
                .error(TestError.offline)
            ]
        ])
        let store = makeStore(sender: sender)

        store.setHost(host: makeHost(serverID: "server-1", server: "example.com"))

        let didConnect = await waitUntil {
            store.connectionStatus == .connected && store.sessionStats?.torrentCount == 4
        }
        XCTAssertTrue(didConnect)
        XCTAssertFalse(store.torrents.isEmpty)
        XCTAssertNil(store.sessionConfiguration)
        XCTAssertEqual(store.defaultDownloadDir, "")
        XCTAssertEqual(store.lastErrorMessage, "")
        XCTAssertNil(store.nextRetryAt)
    }

    func testManualRefreshPreservesPreviousSessionSettingsWhenSessionGetFails() async throws {
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
                .error(TestError.offline)
            ]
        ])
        let store = makeStore(sender: sender)

        store.setHost(host: makeHost(serverID: "server-1", server: "example.com"))
        let didConnectInitially = await waitUntil { store.defaultDownloadDir == "/downloads/initial" }
        XCTAssertTrue(didConnectInitially)

        await store.refreshNow()

        let didRefresh = await waitUntil {
            store.connectionStatus == .connected
        }
        XCTAssertTrue(didRefresh)
        let requests = await sender.capturedRequests()
        XCTAssertEqual(requests.count, 6)
        XCTAssertEqual(store.defaultDownloadDir, "/downloads/initial")
        XCTAssertNotNil(store.sessionConfiguration)
        XCTAssertEqual(store.lastErrorMessage, "")
        XCTAssertNil(store.nextRetryAt)
    }

    func testHostSwitchClearsStaleSessionSettingsWhenNewHostSessionGetFails() async throws {
        let sender = HostMethodScriptedSender(stepsByHostAndMethod: [
            "old.example.com": [
                "session-stats": [
                    .http(statusCode: 200, body: successStatsBody)
                ],
                "torrent-get": [
                    .http(statusCode: 200, body: try loadTransmissionFixture(named: "torrent-get.response.json"))
                ],
                "session-get": [
                    .http(statusCode: 200, body: try sessionSettingsBody(downloadDir: "/downloads/old", version: "4.0.0"))
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
                    .error(TestError.offline)
                ]
            ]
        ])
        let store = makeStore(sender: sender)

        store.setHost(host: makeHost(serverID: "old-server", server: "old.example.com"))
        let didConnectInitially = await waitUntil { store.defaultDownloadDir == "/downloads/old" }
        XCTAssertTrue(didConnectInitially)

        store.setHost(host: makeHost(serverID: "new-server", server: "new.example.com"))

        let didSwitch = await waitUntil {
            store.host?.serverID == "new-server" &&
                store.connectionStatus == .connected &&
                store.sessionStats?.torrentCount == 4
        }
        XCTAssertTrue(didSwitch)
        XCTAssertFalse(store.torrents.isEmpty)
        XCTAssertNil(store.sessionConfiguration)
        XCTAssertEqual(store.defaultDownloadDir, "")
        XCTAssertEqual(store.lastErrorMessage, "")
        XCTAssertNil(store.nextRetryAt)
    }
}

private extension TransmissionStoreFullRefreshTests {
    func makeStore(sender: some TransmissionRPCRequestSending) -> TransmissionStore {
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
            sleep: { _ in
                try await Task.sleep(nanoseconds: .max)
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
