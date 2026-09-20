import XCTest
@testable import BitDream

@MainActor
final class ServerFormModelTests: XCTestCase {
    func testSavingSystemRouteClearsTheFormsTailscaleAccount() async throws {
        let store = TransmissionStore()
        let original = Host(serverID: "saved", port: 9091, server: "server.tail.ts.net",
                            connectionRoute: "tailscale", tailscaleAccountID: "tailscale-user/123")
        let saved = Host(serverID: "saved", port: 9091, server: "server.tail.ts.net", connectionRoute: "system")
        let repository = RecordingHostRepository(createdHost: saved)
        let model = ServerFormModel()
        model.configure(host: original, store: store)
        model.values.connectionRoute = "system"

        guard case .saved = try await model.save(store: store, hostRepository: repository) else {
            return XCTFail("Expected save to succeed")
        }
        XCTAssertNil(model.values.tailscaleAccountID)
        XCTAssertFalse(model.hasUnsavedChanges)

        // The persistent editor can now configure Tailscale with the current account.
        model.values.connectionRoute = "tailscale"
        let current = TailscaleSnapshot(
            generation: 1, state: "Running", authURL: nil, accountID: "tailscale-user/456",
            accountName: "Other", peers: [], proxyPort: 1234, proxyPassword: "test", error: nil
        )
        model.updateTailscaleAccount(from: current)
        XCTAssertEqual(model.values.tailscaleAccountID, current.accountID)
        XCTAssertFalse(model.hasTailscaleAccountMismatch(with: current))
    }

    func testSavedTailscaleServerKeepsItsAccountAcrossSignOutAndSignIn() {
        let model = ServerFormModel()
        let host = Host(serverID: "saved", port: 9091, server: "server.tail.ts.net",
                        connectionRoute: "tailscale", tailscaleAccountID: "tail.ts.net/123/old-node")
        model.configure(host: host, store: TransmissionStore())
        XCTAssertEqual(model.values.tailscaleAccountID, "tailscale-user/123")
        XCTAssertFalse(model.hasUnsavedChanges, "Reading the old format must not require a save")

        model.updateTailscaleAccount(from: nil)
        XCTAssertEqual(model.values.tailscaleAccountID, "tailscale-user/123", "Sign-out must preserve the binding")
        XCTAssertFalse(model.hasTailscaleAccountMismatch(with: nil))

        for account in ["tailscale-user/123", "tailscale-user/456"] {
            let snapshot = TailscaleSnapshot(
                generation: 1, state: "Running", authURL: nil, accountID: account,
                accountName: "Test", peers: [], proxyPort: 1234, proxyPassword: "test", error: nil
            )
            model.updateTailscaleAccount(from: snapshot)
            XCTAssertEqual(model.values.tailscaleAccountID, "tailscale-user/123")
            XCTAssertEqual(model.hasTailscaleAccountMismatch(with: snapshot), account != "tailscale-user/123")
            XCTAssertFalse(model.hasUnsavedChanges)
        }
        XCTAssertEqual(host.tailscaleAccountID, "tail.ts.net/123/old-node", "The saved record is not silently rebound")
    }

    func testNewServerUsesTheCurrentAccountWithoutConfirmation() {
        let model = ServerFormModel()
        model.values.connectionRoute = "tailscale"
        for account in ["tailscale-user/123", "tailscale-user/456"] {
            let snapshot = TailscaleSnapshot(
                generation: 1, state: "Running", authURL: nil, accountID: account,
                accountName: "Test", peers: [], proxyPort: 1234, proxyPassword: "test", error: nil
            )
            model.updateTailscaleAccount(from: snapshot)
            XCTAssertEqual(model.values.tailscaleAccountID, account)
            XCTAssertFalse(model.hasTailscaleAccountMismatch(with: snapshot))
        }
    }

    func testManualAddressEntryRemainsExplicitAcrossMachineRefreshes() {
        let peer = TailscalePeer(id: "server", name: "Server", address: "server.tail.ts.net", online: true)
        let model = ServerFormModel()
        model.values.connectionRoute = "tailscale"
        model.selectTailscaleDestination(.machine(peer.id), from: [peer])
        XCTAssertFalse(model.isEnteringTailscaleAddress)
        XCTAssertEqual(model.tailscaleDestination(in: [peer]), .machine(peer.id))

        model.selectTailscaleDestination(.manual, from: [peer])
        XCTAssertTrue(model.isEnteringTailscaleAddress)
        XCTAssertEqual(model.values.address, peer.address)
        model.resolveTailscaleAddressEntry(in: [])
        model.resolveTailscaleAddressEntry(in: [peer])
        XCTAssertEqual(model.tailscaleDestination(in: [peer]), .manual,
                       "A matching address must not switch an explicit manual entry back to machine selection")

        model.values.address = "custom.tail.ts.net"
        model.selectTailscaleDestination(.machine(peer.id), from: [peer])
        XCTAssertFalse(model.isEnteringTailscaleAddress)
        XCTAssertEqual(model.values.address, peer.address)
        model.resolveTailscaleAddressEntry(in: [])
        XCTAssertFalse(model.isEnteringTailscaleAddress, "An empty list must not reveal the manual address field")
        XCTAssertEqual(model.values.address, peer.address)
        XCTAssertEqual(model.tailscaleDestination(in: [peer]), .machine(peer.id))
    }

    func testSavedDestinationInfersEntryMethodWithoutChangingTheServer() {
        let peer = TailscalePeer(id: "server", name: "Server", address: "server.tail.ts.net", online: true)
        let model = ServerFormModel()
        let store = TransmissionStore()
        let host = Host(serverID: "saved", port: 9091, server: peer.address,
                        connectionRoute: "tailscale", tailscaleAccountID: "account")
        model.configure(host: host, store: store)
        model.resolveTailscaleAddressEntry(in: [])
        XCTAssertFalse(model.isEnteringTailscaleAddress)
        model.resolveTailscaleAddressEntry(in: [peer])
        XCTAssertEqual(model.tailscaleDestination(in: [peer]), .machine(peer.id))
        XCTAssertFalse(model.hasUnsavedChanges)

        host.server = "custom.tail.ts.net"
        model.configure(host: host, store: store)
        model.resolveTailscaleAddressEntry(in: [peer])
        XCTAssertTrue(model.isEnteringTailscaleAddress)
        XCTAssertEqual(model.values.address, "custom.tail.ts.net")
        XCTAssertFalse(model.hasUnsavedChanges)
    }

    func testDeviceSelectionTracksAddressAcrossRefreshAndManualEdits() {
        let first = TailscalePeer(id: "first", name: "First", address: "first.tail.ts.net", online: true,
                                  ips: ["100.64.0.1"])
        let second = TailscalePeer(id: "second", name: "Second", address: "second.tail.ts.net", online: true)
        let peers = [first, second]
        let model = ServerFormModel()
        model.values.connectionRoute = "tailscale"
        model.values.tailscaleAccountID = "account"

        model.selectTailscalePeer(id: first.id, from: peers)
        XCTAssertEqual(model.values.address, first.address)
        XCTAssertEqual(model.values.name, first.name)
        XCTAssertEqual(model.selectedTailscalePeerID(in: peers), first.id)

        XCTAssertNil(model.selectedTailscalePeerID(in: []))
        model.selectTailscalePeer(id: nil, from: [])
        XCTAssertEqual(model.values.address, first.address, "An empty refresh must preserve the selected destination")
        XCTAssertEqual(model.selectedTailscalePeerID(in: peers), first.id)

        let refreshed = TailscalePeer(id: first.id, name: "Updated name", address: first.address, online: false)
        XCTAssertEqual(model.selectedTailscalePeerID(in: [second, refreshed]), first.id)
        XCTAssertNil(model.selectedTailscalePeerID(in: [second]))
        XCTAssertEqual(model.values.address, first.address, "A missing peer must not clear the destination")

        model.values.name = "My server"
        model.selectTailscalePeer(id: second.id, from: peers)
        XCTAssertEqual(model.selectedTailscalePeerID(in: peers), second.id)
        XCTAssertEqual(model.values.name, "My server")
        XCTAssertEqual(model.values.tailscaleAccountID, "account")

        model.values.address = "100.64.0.1"
        XCTAssertEqual(model.selectedTailscalePeerID(in: peers), first.id)
        model.values.address = "custom.example.com"
        XCTAssertNil(model.selectedTailscalePeerID(in: peers))
        model.selectTailscalePeer(id: nil, from: peers)
        XCTAssertEqual(model.values.address, "custom.example.com")
    }

    func testReopenedServerRestoresDeviceSelectionFromSavedAddress() {
        let peer = TailscalePeer(id: "server", name: "Server", address: "server.tail.ts.net", online: true)
        let host = Host(serverID: "saved", name: "My server", port: 9091, server: peer.address,
                        connectionRoute: "tailscale", tailscaleAccountID: "account")
        let model = ServerFormModel()
        model.configure(host: host, store: TransmissionStore())

        XCTAssertEqual(model.selectedTailscalePeerID(in: [peer]), peer.id)
        XCTAssertFalse(model.hasUnsavedChanges)
    }

    func testConfigureNewServerUsesExpectedDefaultAndToggleRules() {
        let store = TransmissionStore()
        let model = ServerFormModel()

        model.configure(host: nil, store: store)

        XCTAssertTrue(model.isAddNew)
        XCTAssertTrue(model.values.isDefault)
        XCTAssertFalse(model.hasUnsavedChanges)
        XCTAssertFalse(model.canEditDefaultToggle(hostCount: 0))
        XCTAssertTrue(model.canEditDefaultToggle(hostCount: 1))
    }

    func testConfigureExistingServerTracksChangesAndToggleRules() {
        let store = TransmissionStore()
        let host = Host(
            serverID: "server-1",
            isDefault: true,
            isSSL: true,
            name: "Office",
            port: 9092,
            server: "office.example.com",
            username: "admin"
        )
        let model = ServerFormModel()

        model.configure(host: host, store: store)

        XCTAssertFalse(model.isAddNew)
        XCTAssertEqual(model.values.name, "Office")
        XCTAssertEqual(model.values.address, "office.example.com")
        XCTAssertEqual(model.values.port, 9092)
        XCTAssertEqual(model.values.username, "admin")
        XCTAssertTrue(model.values.isDefault)
        XCTAssertTrue(model.values.isSSL)
        XCTAssertFalse(model.hasUnsavedChanges)
        XCTAssertFalse(model.canEditDefaultToggle(hostCount: 1))
        XCTAssertTrue(model.canEditDefaultToggle(hostCount: 2))

        model.values.address = "new.example.com"

        XCTAssertTrue(model.hasUnsavedChanges)
    }

    func testSaveReportsFirstValidationFailureWithoutCallingRepository() async throws {
        let store = TransmissionStore()
        let model = ServerFormModel()
        let repository = RecordingHostRepository()
        model.configure(host: nil, store: store)
        model.values.port = 0

        let result = try await model.save(store: store, hostRepository: repository)

        guard case .validationFailed(let field) = result else {
            return XCTFail("Expected validation to fail")
        }
        XCTAssertEqual(field, ServerFormModel.Field.address)
        XCTAssertEqual(model.validationMessage, "Address is required.")
        XCTAssertNil(repository.createdDraft)
        XCTAssertFalse(model.isSaving)
    }

    func testSuccessfulSavePersistsDraftAndClearsDirtyState() async throws {
        let store = TransmissionStore()
        store.host = Host(serverID: "existing-server", server: "existing.example.com")
        let savedHost = Host(serverID: "new-server", server: "new.example.com")
        let repository = RecordingHostRepository(createdHost: savedHost)
        let model = ServerFormModel()
        model.configure(host: nil, store: store)
        model.values = ServerFormModel.Values(
            name: "New Server",
            address: "new.example.com",
            port: 9095,
            username: "user",
            password: "secret",
            isDefault: true,
            isSSL: true
        )

        let result = try await model.save(store: store, hostRepository: repository)

        guard case .saved(let resultHost) = result else {
            return XCTFail("Expected save to succeed")
        }
        XCTAssertEqual(resultHost.serverID, "new-server")
        XCTAssertEqual(repository.createdDraft?.name, "New Server")
        XCTAssertEqual(repository.createdDraft?.server, "new.example.com")
        XCTAssertEqual(repository.createdDraft?.port, 9095)
        XCTAssertEqual(repository.createdDraft?.username, "user")
        XCTAssertEqual(repository.createdDraft?.password, "secret")
        XCTAssertEqual(repository.createdDraft?.isDefault, true)
        XCTAssertEqual(repository.createdDraft?.isSSL, true)
        XCTAssertFalse(model.hasUnsavedChanges)
        XCTAssertFalse(model.isSaving)
    }
}

@MainActor
private final class RecordingHostRepository: HostPersisting {
    private let createdHost: BitDream.Host
    private(set) var createdDraft: HostDraft?

    init(
        createdHost: BitDream.Host = BitDream.Host(
            serverID: "created-server",
            server: "created.example.com"
        )
    ) {
        self.createdHost = createdHost
    }

    func bootstrap() async {}

    func create(draft: HostDraft) async throws -> BitDream.Host {
        createdDraft = draft
        return createdHost
    }

    func update(serverID: String, draft: HostDraft) async throws -> BitDream.Host {
        return createdHost
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
