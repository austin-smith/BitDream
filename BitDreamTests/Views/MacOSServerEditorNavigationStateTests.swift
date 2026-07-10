import XCTest
@testable import BitDream

#if os(macOS)
final class MacOSServerEditorNavigationStateTests: XCTestCase {
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
}
#endif
