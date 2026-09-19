import XCTest
@testable import BitDream

#if os(macOS)
final class MacOSServerEditorNavigationStateTests: XCTestCase {
    @MainActor
    func testEditingCoordinatorConsumesOnlyTheHandledRequest() throws {
        let coordinator = MacOSServerEditingCoordinator()
        let hosts = PreviewFixtures.makeHosts()

        coordinator.requestEditing(hosts[0])
        let staleRequest = try XCTUnwrap(coordinator.request)
        coordinator.requestEditing(hosts[1])
        let currentRequest = try XCTUnwrap(coordinator.request)

        coordinator.consume(staleRequest)
        XCTAssertEqual(coordinator.request, currentRequest)

        coordinator.consume(currentRequest)
        XCTAssertNil(coordinator.request)
    }

    func testDirtyTransitionRequiresConfirmationBeforeChangingSelection() {
        var state = MacOSServerEditorNavigationState()
        state.apply(.server("server-a"))
        state.setHasUnsavedChanges(true)

        let result = state.requestTransition(to: .server("server-b"), whileSaving: false)

        XCTAssertEqual(result, .confirmationRequired)
        XCTAssertEqual(state.selectedServerID, "server-a")
        XCTAssertEqual(state.pendingDestination, .server("server-b"))
        XCTAssertTrue(state.hasUnsavedChanges)

        state.confirmDiscardAndTransition()

        XCTAssertEqual(state.selectedServerID, "server-b")
        XCTAssertNil(state.pendingDestination)
        XCTAssertFalse(state.hasUnsavedChanges)
    }

    func testCancellingDirtyTransitionPreservesEditorState() {
        var state = MacOSServerEditorNavigationState()
        state.apply(.server("server-a"))
        state.setHasUnsavedChanges(true)
        _ = state.requestTransition(to: .newServer, whileSaving: false)

        state.cancelPendingTransition()

        XCTAssertEqual(state.selectedServerID, "server-a")
        XCTAssertFalse(state.isCreatingNew)
        XCTAssertTrue(state.hasUnsavedChanges)
        XCTAssertNil(state.pendingDestination)
    }

    func testTransitionIsIgnoredWhileSaveIsInFlight() {
        var state = MacOSServerEditorNavigationState()
        state.apply(.server("server-a"))
        state.setHasUnsavedChanges(true)

        let result = state.requestTransition(to: .server("server-b"), whileSaving: true)

        XCTAssertEqual(result, .ignored)
        XCTAssertEqual(state.selectedServerID, "server-a")
        XCTAssertNil(state.pendingDestination)
        XCTAssertTrue(state.hasUnsavedChanges)
    }

    func testDirtySelectedServerCannotConnectUntilChangesAreSaved() {
        var state = MacOSServerEditorNavigationState()
        state.apply(.server("server-a"))
        state.setHasUnsavedChanges(true)

        XCTAssertFalse(state.canConnect(to: "server-a", connectedServerID: nil))
        XCTAssertTrue(state.canConnect(to: "server-b", connectedServerID: nil))

        state.setHasUnsavedChanges(false)

        XCTAssertTrue(state.canConnect(to: "server-a", connectedServerID: nil))
        XCTAssertFalse(state.canConnect(to: "server-a", connectedServerID: "server-a"))
    }

    func testDeletingUnselectedServerPreservesSelectionAndDirtyState() {
        var state = MacOSServerEditorNavigationState()
        state.apply(.server("server-b"))
        state.setHasUnsavedChanges(true)

        state.didDelete(
            serverID: "server-a",
            remainingServerIDs: ["server-b", "server-c"]
        )

        XCTAssertEqual(state.selectedServerID, "server-b")
        XCTAssertTrue(state.hasUnsavedChanges)
    }

    func testDeletingSelectedServerChoosesFirstRemainingServer() {
        var state = MacOSServerEditorNavigationState()
        state.apply(.server("server-b"))
        state.setHasUnsavedChanges(true)

        state.didDelete(
            serverID: "server-b",
            remainingServerIDs: ["server-a", "server-c"]
        )

        XCTAssertEqual(state.selectedServerID, "server-a")
        XCTAssertFalse(state.isCreatingNew)
        XCTAssertFalse(state.hasUnsavedChanges)
    }

    func testDeletingLastServerStartsNewServerEditor() {
        var state = MacOSServerEditorNavigationState()
        state.apply(.server("server-a"))

        state.didDelete(serverID: "server-a", remainingServerIDs: [])

        XCTAssertNil(state.selectedServerID)
        XCTAssertTrue(state.isCreatingNew)
    }

    func testDeletingOnlyPersistedServerPreservesDirtyNewServerDraft() {
        var state = MacOSServerEditorNavigationState()
        state.apply(.newServer)
        state.setHasUnsavedChanges(true)

        state.didDelete(serverID: "server-a", remainingServerIDs: [])
        state.reconcileSelection(availableServerIDs: [], preferredServerID: nil)

        XCTAssertNil(state.selectedServerID)
        XCTAssertTrue(state.isCreatingNew)
        XCTAssertTrue(state.hasUnsavedChanges)
    }

    func testReconcileSelectionPrefersConnectedServerWhenSelectionIsMissing() {
        var state = MacOSServerEditorNavigationState()

        state.reconcileSelection(
            availableServerIDs: ["server-a", "server-b"],
            preferredServerID: "server-b"
        )

        XCTAssertEqual(state.selectedServerID, "server-b")
        XCTAssertFalse(state.isCreatingNew)
    }

    func testSuccessfulCreationSelectsTheConfirmedServer() {
        var state = MacOSServerEditorNavigationState()
        state.apply(.newServer)
        state.setHasUnsavedChanges(true)

        state.didSave(serverID: "created-server")

        XCTAssertEqual(state.selectedServerID, "created-server")
        XCTAssertFalse(state.isCreatingNew)
        XCTAssertFalse(state.hasUnsavedChanges)
    }

    func testDraftRemainsSelectedUntilDiscardIsConfirmed() {
        var state = MacOSServerEditorNavigationState()
        state.apply(.server("server-a"))
        XCTAssertEqual(state.requestTransition(to: .newServer, whileSaving: false), .applied)
        XCTAssertEqual(state.currentDestination, .newServer)
        state.setHasUnsavedChanges(true)

        XCTAssertEqual(state.requestTransition(to: .newServer, whileSaving: false), .ignored)
        XCTAssertEqual(state.requestTransition(to: .server("server-b"), whileSaving: false), .confirmationRequired)
        XCTAssertEqual(state.currentDestination, .newServer)

        state.cancelPendingTransition()
        XCTAssertEqual(state.currentDestination, .newServer)
        XCTAssertTrue(state.hasUnsavedChanges)

        _ = state.requestTransition(to: .server("server-b"), whileSaving: false)
        state.confirmDiscardAndTransition()
        XCTAssertEqual(state.currentDestination, .server("server-b"))
        XCTAssertFalse(state.hasUnsavedChanges)
    }

    func testCancelDraftRestoresPreviousSelectionInsteadOfConnectedServer() {
        var state = MacOSServerEditorNavigationState()
        state.apply(.server("server-b"))
        state.apply(.newServer)
        state.setHasUnsavedChanges(true)

        state.cancelCreating(
            availableServerIDs: ["server-a", "server-b"],
            preferredServerID: "server-a"
        )

        XCTAssertEqual(state.currentDestination, .server("server-b"))
        XCTAssertFalse(state.hasUnsavedChanges)
        XCTAssertNil(state.pendingDestination)
    }

    func testCancelDraftFallsBackWhenPreviousServerWasRemoved() {
        var state = MacOSServerEditorNavigationState()
        state.apply(.server("removed-server"))
        state.apply(.newServer)

        state.cancelCreating(
            availableServerIDs: ["server-a", "server-b"],
            preferredServerID: "server-b"
        )

        XCTAssertEqual(state.currentDestination, .server("server-b"))
    }

    func testCancelFirstServerDraftClearsSelectionAndAllowsStartingAgain() {
        var state = MacOSServerEditorNavigationState()
        state.reconcileSelection(availableServerIDs: [], preferredServerID: nil)
        XCTAssertEqual(state.currentDestination, .newServer)
        state.setHasUnsavedChanges(true)

        state.cancelCreating(availableServerIDs: [], preferredServerID: nil)

        XCTAssertNil(state.currentDestination)
        XCTAssertFalse(state.isCreatingNew)
        XCTAssertFalse(state.hasUnsavedChanges)
        XCTAssertEqual(state.requestTransition(to: .newServer, whileSaving: false), .applied)
        XCTAssertEqual(state.currentDestination, .newServer)
    }
}
#endif
