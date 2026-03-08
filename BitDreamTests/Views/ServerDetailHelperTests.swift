import Foundation
import XCTest
@testable import BitDream

@MainActor
final class ServerDetailHelperTests: XCTestCase {
    func testUpdateExistingServerReconnectsSelectedHostAfterSuccessfulSave() async throws {
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
                    .http(statusCode: 200, body: try sessionSettingsBody(downloadDir: "/downloads/new", version: "4.0.1"))
                ]
            ]
        ])
        let store = makeStore(sender: sender)
        let selectedHost = makeHost(serverID: "server-1", server: "old.example.com")
        let updatedHost = makeHost(serverID: "server-1", server: "new.example.com")
        let repository = TestHostRepository { _, _ in updatedHost }
        var didComplete = false
        var errorMessage: String?

        store.setHost(host: selectedHost)
        let didConnectInitially = await waitUntil { store.defaultDownloadDir == "/downloads/old" }
        XCTAssertTrue(didConnectInitially)

        updateExistingServer(
            host: selectedHost,
            draft: makeDraft(server: "new.example.com"),
            store: store,
            hostRepository: repository
        ) {
            didComplete = true
        } onError: { message in
            errorMessage = message
        }

        let didReconnectSelectedHost = await waitUntil {
            didComplete && store.defaultDownloadDir == "/downloads/new"
        }
        XCTAssertTrue(didReconnectSelectedHost)
        XCTAssertNil(errorMessage)
        XCTAssertEqual(store.host?.server, "new.example.com")
    }

    func testUpdateExistingServerDoesNotReconnectWhenUpdatedHostIsNotSelected() async throws {
        let sender = HostMethodScriptedSender(stepsByHostAndMethod: [
            "selected.example.com": [
                "session-stats": [
                    .http(statusCode: 200, body: successStatsBody)
                ],
                "torrent-get": [
                    .http(statusCode: 200, body: try loadTransmissionFixture(named: "torrent-get.response.json"))
                ],
                "session-get": [
                    .http(statusCode: 200, body: try sessionSettingsBody(downloadDir: "/downloads/selected", version: "4.0.0"))
                ]
            ]
        ])
        let store = makeStore(sender: sender)
        let selectedHost = makeHost(serverID: "selected-server", server: "selected.example.com")
        let otherHost = makeHost(serverID: "other-server", server: "other.example.com")
        let updatedOtherHost = makeHost(serverID: "other-server", server: "other-new.example.com")
        let repository = TestHostRepository { _, _ in
            updatedOtherHost
        }
        var didComplete = false

        store.setHost(host: selectedHost)
        let didConnectInitially = await waitUntil { store.defaultDownloadDir == "/downloads/selected" }
        XCTAssertTrue(didConnectInitially)
        let initialRequestCount = (await sender.capturedRequests()).count

        updateExistingServer(
            host: otherHost,
            draft: makeDraft(server: "other-new.example.com"),
            store: store,
            hostRepository: repository
        ) {
            didComplete = true
        }

        let didFinishUpdate = await waitUntil { didComplete }
        XCTAssertTrue(didFinishUpdate)
        await Task.yield()
        await Task.yield()

        let finalRequestCount = (await sender.capturedRequests()).count
        XCTAssertEqual(store.host?.serverID, "selected-server")
        XCTAssertEqual(store.defaultDownloadDir, "/downloads/selected")
        XCTAssertEqual(finalRequestCount, initialRequestCount)
    }

    func testUpdateExistingServerReconnectsSelectedHostAfterCatalogSyncFailure() async throws {
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
                    .http(statusCode: 200, body: try sessionSettingsBody(downloadDir: "/downloads/new", version: "4.0.2"))
                ]
            ]
        ])
        let store = makeStore(sender: sender)
        let selectedHost = makeHost(serverID: "server-1", server: "old.example.com")
        let repository = TestHostRepository { _, _ in selectedHost.server = "new.example.com"; throw HostPersistenceError.catalogSyncFailure("catalog sync failed") }
        var didComplete = false
        var errorMessage: String?

        store.setHost(host: selectedHost)
        let didConnectInitially = await waitUntil { store.defaultDownloadDir == "/downloads/old" }
        XCTAssertTrue(didConnectInitially)

        updateExistingServer(
            host: selectedHost,
            draft: makeDraft(server: "new.example.com"),
            store: store,
            hostRepository: repository
        ) {
            didComplete = true
        } onError: { message in
            errorMessage = message
        }

        let didReconnectAfterCatalogFailure = await waitUntil {
            didComplete && store.defaultDownloadDir == "/downloads/new"
        }
        XCTAssertTrue(didReconnectAfterCatalogFailure)
        XCTAssertNil(errorMessage)
        XCTAssertEqual(store.host?.server, "new.example.com")
    }

    func testUpdateExistingServerReportsFailureWithoutTouchingStore() async throws {
        let sender = HostMethodScriptedSender(stepsByHostAndMethod: [
            "selected.example.com": [
                "session-stats": [
                    .http(statusCode: 200, body: successStatsBody)
                ],
                "torrent-get": [
                    .http(statusCode: 200, body: try loadTransmissionFixture(named: "torrent-get.response.json"))
                ],
                "session-get": [
                    .http(statusCode: 200, body: try sessionSettingsBody(downloadDir: "/downloads/selected", version: "4.0.0"))
                ]
            ]
        ])
        let store = makeStore(sender: sender)
        let selectedHost = makeHost(serverID: "selected-server", server: "selected.example.com")
        let repository = TestHostRepository { _, _ in throw HostPersistenceError.saveFailure("save failed") }
        var didComplete = false
        var errorMessage: String?

        store.setHost(host: selectedHost)
        let didConnectInitially = await waitUntil { store.defaultDownloadDir == "/downloads/selected" }
        XCTAssertTrue(didConnectInitially)
        let initialRequestCount = (await sender.capturedRequests()).count

        updateExistingServer(
            host: selectedHost,
            draft: makeDraft(server: "selected-new.example.com"),
            store: store,
            hostRepository: repository
        ) {
            didComplete = true
        } onError: { message in
            errorMessage = message
        }

        let didReportError = await waitUntil { errorMessage != nil }
        XCTAssertTrue(didReportError)
        let finalRequestCount = (await sender.capturedRequests()).count
        XCTAssertFalse(didComplete)
        XCTAssertEqual(errorMessage, "Could not save server changes.")
        XCTAssertEqual(store.host?.server, "selected.example.com")
        XCTAssertEqual(store.defaultDownloadDir, "/downloads/selected")
        XCTAssertEqual(finalRequestCount, initialRequestCount)
    }
}

private extension ServerDetailHelperTests {
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
                reloadTimelines: {}
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

    func makeDraft(server: String) -> HostDraft {
        HostDraft(
            name: server,
            server: server,
            port: 9091,
            username: "demo",
            isSSL: false,
            isDefault: false,
            password: "secret"
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

    func sessionSettingsBody(downloadDir: String, version: String) throws -> String {
        let data = Data(try loadTransmissionFixture(named: "session-get.response.json").utf8)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var arguments = try XCTUnwrap(object["arguments"] as? [String: Any])
        arguments["download-dir"] = downloadDir
        arguments["version"] = version
        object["arguments"] = arguments
        let encoded = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return try XCTUnwrap(String(bytes: encoded, encoding: .utf8))
    }
}

@MainActor
private final class TestHostRepository: HostPersisting {
    private let updateHandler: @MainActor @Sendable (String, HostDraft) async throws -> BitDream.Host

    init(updateHandler: @escaping @MainActor @Sendable (String, HostDraft) async throws -> BitDream.Host) {
        self.updateHandler = updateHandler
    }

    func bootstrap() async {}

    func create(draft: HostDraft) async throws -> BitDream.Host {
        fatalError("Unused in tests")
    }

    func update(serverID: String, draft: HostDraft) async throws -> BitDream.Host {
        try await updateHandler(serverID, draft)
    }

    func delete(serverID: String) async throws {
        fatalError("Unused in tests")
    }

    func setDefault(serverID: String) async throws {
        fatalError("Unused in tests")
    }

    func persistVersionIfNeeded(serverID: String, version: String) async {}

    func syncCatalog() async {}
}
