import XCTest
@testable import BitDream

@MainActor
final class ServerFormModelTests: XCTestCase {
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
        fatalError("Unused in tests")
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
