import Foundation
import XCTest
@testable import BitDream

@MainActor
final class SettingsViewModelTests: XCTestCase {
    func testSaveFailurePreservesDirtyEdits() async throws {
        let store = FakeSessionSettingsStore(
            host: makeHost(serverID: "server-1"),
            sessionConfiguration: try makeSessionConfiguration(downloadDir: "/downloads/original")
        )
        store.applySessionSettingsHandler = { _ in
            throw TestError.offline
        }
        let model = SettingsViewModel(debounceInterval: 60)

        model.bind(to: store)
        model.setValue(\.downloadDir, "/downloads/edited", original: "/downloads/original")

        do {
            try await model.flushPendingChanges()
            XCTFail("Expected save failure")
        } catch {}

        XCTAssertEqual(model.value(for: \.downloadDir, fallback: "/downloads/original"), "/downloads/edited")
        if case .failed(let presentation) = model.saveState {
            XCTAssertFalse(presentation.message.isEmpty)
        } else {
            XCTFail("Expected failed save state")
        }
    }

    func testFreeSpaceUsesDraftDownloadDirectoryWithoutSaving() async throws {
        let store = FakeSessionSettingsStore(
            host: makeHost(serverID: "server-1"),
            sessionConfiguration: try makeSessionConfiguration(downloadDir: "/downloads/original")
        )
        store.checkFreeSpaceHandler = { path in
            XCTAssertEqual(path, "/downloads/draft")
            return FreeSpaceResponse(path: path, sizeBytes: 1024, totalSize: 2048)
        }
        let model = SettingsViewModel(debounceInterval: 60)

        model.bind(to: store)
        model.setValue(\.downloadDir, "/downloads/draft", original: "/downloads/original")
        await model.checkFreeSpace()

        XCTAssertEqual(store.appliedSettings.count, 0)
        if case .result = model.freeSpaceState {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected free-space result")
        }
    }

    func testPortTestFlushesPendingChangesBeforeRunning() async throws {
        let store = FakeSessionSettingsStore(
            host: makeHost(serverID: "server-1"),
            sessionConfiguration: try makeSessionConfiguration(peerPort: 51413)
        )
        store.applySessionSettingsHandler = { args in
            store.callOrder.append("save")
            XCTAssertEqual(args.peerPort, 6000)
            return try self.makeSessionConfiguration(peerPort: 6000)
        }
        store.testPortHandler = { _ in
            store.callOrder.append("port")
            return PortTestResponse(portIsOpen: true, ipProtocol: "ipv4")
        }
        let model = SettingsViewModel(debounceInterval: 60)

        model.bind(to: store)
        model.setValue(\.peerPort, 6000, original: 51413)
        await model.testPort()

        XCTAssertEqual(store.callOrder, ["save", "port"])
        XCTAssertEqual(model.saveState, .idle)
        if case .result(let outcome) = model.portTestState {
            XCTAssertEqual(outcome, .open(protocolName: "IPV4"))
        } else {
            XCTFail("Expected port-test result")
        }
    }

    func testBlocklistUpdateFlushesPendingChangesFirst() async throws {
        let store = FakeSessionSettingsStore(
            host: makeHost(serverID: "server-1"),
            sessionConfiguration: try makeSessionConfiguration(blocklistSize: 0)
        )
        store.applySessionSettingsHandler = { args in
            store.callOrder.append("save")
            XCTAssertEqual(args.blocklistEnabled, true)
            return try self.makeSessionConfiguration(blocklistSize: 0)
        }
        store.updateBlocklistHandler = {
            store.callOrder.append("blocklist")
            store.sessionConfiguration = try self.makeSessionConfiguration(blocklistSize: 42)
            return BlocklistUpdateResponse(blocklistSize: 42)
        }
        let model = SettingsViewModel(debounceInterval: 60)

        model.bind(to: store)
        model.setValue(\.blocklistEnabled, true, original: false)
        await model.updateBlocklist()

        XCTAssertEqual(store.callOrder, ["save", "blocklist"])
        XCTAssertEqual(model.blocklistUpdateState, .success(ruleCount: 42))
    }

    func testHostSwitchClearsDraftAndTransientState() async throws {
        let store = FakeSessionSettingsStore(
            host: makeHost(serverID: "server-1"),
            sessionConfiguration: try makeSessionConfiguration(downloadDir: "/downloads/original")
        )
        store.checkFreeSpaceHandler = { path in
            FreeSpaceResponse(path: path, sizeBytes: 1024, totalSize: 2048)
        }
        let model = SettingsViewModel(debounceInterval: 60)

        model.bind(to: store)
        model.setValue(\.downloadDir, "/downloads/dirty", original: "/downloads/original")
        await model.checkFreeSpace()

        store.host = makeHost(serverID: "server-2")
        store.settingsConnectionGeneration = UUID()
        store.sessionConfiguration = try makeSessionConfiguration(downloadDir: "/downloads/new")
        model.bind(to: store)

        XCTAssertEqual(model.value(for: \.downloadDir, fallback: "/downloads/new"), "/downloads/new")
        XCTAssertEqual(model.saveState, .idle)
        XCTAssertEqual(model.freeSpaceState, .idle)
        XCTAssertEqual(model.portTestState, .idle)
        XCTAssertEqual(model.blocklistUpdateState, .idle)
    }

    func testSameServerRefreshRebasesBaselineWithoutDroppingOtherDirtyFields() async throws {
        let store = FakeSessionSettingsStore(
            host: makeHost(serverID: "server-1"),
            sessionConfiguration: try makeSessionConfiguration(downloadDir: "/downloads/original", peerPort: 51413)
        )
        let model = SettingsViewModel(debounceInterval: 60)

        model.bind(to: store)
        model.setValue(\.downloadDir, "/downloads/rebased", original: "/downloads/original")
        model.setValue(\.peerPort, 6000, original: 51413)

        store.sessionConfiguration = try makeSessionConfiguration(downloadDir: "/downloads/rebased", peerPort: 51413, version: "4.0.1")
        model.bind(to: store)

        XCTAssertEqual(model.saveState, .pending)

        store.applySessionSettingsHandler = { args in
            XCTAssertNil(args.downloadDir)
            XCTAssertEqual(args.peerPort, 6000)
            return try self.makeSessionConfiguration(downloadDir: "/downloads/rebased", peerPort: 6000, version: "4.0.2")
        }

        try await model.flushPendingChanges()

        XCTAssertEqual(model.saveState, .idle)
    }

    func testNewerEditsSurviveOlderSaveCompletion() async throws {
        let controller = BlockingSaveController()
        let store = FakeSessionSettingsStore(
            host: makeHost(serverID: "server-1"),
            sessionConfiguration: try makeSessionConfiguration(downloadDir: "/downloads/original")
        )
        store.applySessionSettingsHandler = { args in
            let response = try await controller.handleSave(args)
            store.sessionConfiguration = response
            return response
        }
        let model = SettingsViewModel(debounceInterval: 0, sleep: { _ in })

        model.bind(to: store)
        model.setValue(\.downloadDir, "/downloads/first", original: "/downloads/original")

        let startedFirstSave = await waitUntil { await controller.totalSaveCount() == 1 }
        XCTAssertTrue(startedFirstSave)

        model.setValue(\.downloadDir, "/downloads/second", original: "/downloads/original")
        await controller.releaseNextSave(returning: try makeSessionConfiguration(downloadDir: "/downloads/first", version: "4.0.1"))

        let startedSecondSave = await waitUntil { await controller.totalSaveCount() == 2 }
        XCTAssertTrue(startedSecondSave)
        await controller.releaseNextSave(returning: try makeSessionConfiguration(downloadDir: "/downloads/second", version: "4.0.2"))

        let becameIdle = await waitUntil { model.saveState == .idle }
        XCTAssertTrue(becameIdle)
        XCTAssertEqual(model.value(for: \.downloadDir, fallback: "/downloads/second"), "/downloads/second")
        let savedDirectories = await controller.savedDownloadDirectories()
        XCTAssertEqual(savedDirectories, ["/downloads/first", "/downloads/second"])
    }
}

private extension SettingsViewModelTests {
    func makeHost(serverID: String) -> BitDream.Host {
        BitDream.Host(
            serverID: serverID,
            isDefault: false,
            isSSL: false,
            credentialKey: "test-key",
            name: serverID,
            port: 9091,
            server: "example.com",
            username: "demo",
            version: nil
        )
    }

    func makeSessionConfiguration(
        downloadDir: String = "/downloads",
        peerPort: Int = 51413,
        blocklistSize: Int = 0,
        version: String = "4.0.0"
    ) throws -> TransmissionSessionResponseArguments {
        let data = Data(try loadTransmissionFixture(named: "session-get.response.json").utf8)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var arguments = try XCTUnwrap(object["arguments"] as? [String: Any])
        arguments["download-dir"] = downloadDir
        arguments["peer-port"] = peerPort
        arguments["blocklist-size"] = blocklistSize
        arguments["version"] = version
        object["arguments"] = arguments

        let output = try JSONSerialization.data(withJSONObject: object)
        let envelope = try JSONDecoder().decode(
            TransmissionRPCEnvelope<TransmissionSessionResponseArguments>.self,
            from: output
        )
        return try envelope.requireArguments()
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

@MainActor
private final class FakeSessionSettingsStore: SessionSettingsServing {
    var host: BitDream.Host?
    var settingsConnectionGeneration: UUID = UUID()
    var sessionConfiguration: TransmissionSessionResponseArguments?

    var appliedSettings: [TransmissionSessionSetRequestArgs] = []
    var callOrder: [String] = []

    var applySessionSettingsHandler: ((TransmissionSessionSetRequestArgs) async throws -> TransmissionSessionResponseArguments)?
    var checkFreeSpaceHandler: ((String) async throws -> FreeSpaceResponse)?
    var testPortHandler: ((String?) async throws -> PortTestResponse)?
    var updateBlocklistHandler: (() async throws -> BlocklistUpdateResponse)?

    init(host: BitDream.Host?, sessionConfiguration: TransmissionSessionResponseArguments?) {
        self.host = host
        self.sessionConfiguration = sessionConfiguration
    }

    func applySessionSettings(_ args: TransmissionSessionSetRequestArgs) async throws -> TransmissionSessionResponseArguments {
        appliedSettings.append(args)
        if let applySessionSettingsHandler {
            let updated = try await applySessionSettingsHandler(args)
            sessionConfiguration = updated
            return updated
        }

        guard let sessionConfiguration else {
            throw CancellationError()
        }

        return sessionConfiguration
    }

    func checkFreeSpace(path: String) async throws -> FreeSpaceResponse {
        guard let checkFreeSpaceHandler else {
            throw CancellationError()
        }
        return try await checkFreeSpaceHandler(path)
    }

    func testPort(ipProtocol: String?) async throws -> PortTestResponse {
        guard let testPortHandler else {
            throw CancellationError()
        }
        return try await testPortHandler(ipProtocol)
    }

    func updateBlocklist() async throws -> BlocklistUpdateResponse {
        guard let updateBlocklistHandler else {
            throw CancellationError()
        }
        return try await updateBlocklistHandler()
    }
}

private actor BlockingSaveController {
    private var pending: [CheckedContinuation<TransmissionSessionResponseArguments, Error>] = []
    private var recordedDownloadDirectories: [String] = []
    private var saveCount = 0

    func handleSave(_ args: TransmissionSessionSetRequestArgs) async throws -> TransmissionSessionResponseArguments {
        saveCount += 1
        if let downloadDir = args.downloadDir {
            recordedDownloadDirectories.append(downloadDir)
        }

        return try await withCheckedThrowingContinuation { continuation in
            pending.append(continuation)
        }
    }

    func totalSaveCount() -> Int {
        saveCount
    }

    func savedDownloadDirectories() -> [String] {
        recordedDownloadDirectories
    }

    func releaseNextSave(returning configuration: TransmissionSessionResponseArguments) {
        guard !pending.isEmpty else { return }
        let continuation = pending.removeFirst()
        continuation.resume(returning: configuration)
    }
}
