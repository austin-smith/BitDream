import XCTest
@testable import BitDream

final class IOSNavigationStateTests: XCTestCase {
    func testInspectorStartsHiddenSoTheListOwnsTheWorkspace() {
        let state = iOSNavigationState()
        XCTAssertFalse(state.isDetailPresented)
        XCTAssertNil(state.selectedTorrentID)
    }

    func testHidingAndReopeningInspectorPreservesSelectionAndFileNavigation() {
        var state = iOSNavigationState()
        state.selectTorrent(42)
        state.detailPath = [.files]

        state.hideDetails()
        state.reconcileTorrentSelection(availableIDs: [42, 43])

        XCTAssertFalse(state.isDetailPresented)
        XCTAssertEqual(state.selectedTorrentID, 42)
        XCTAssertEqual(state.detailPath, [.files])

        state.selectTorrent(42)

        XCTAssertTrue(state.isDetailPresented)
        XCTAssertEqual(state.detailPath, [.files])
    }

    func testSelectingAnotherTorrentClearsThePreviousTorrentDestination() {
        var state = iOSNavigationState()
        state.selectTorrent(42)
        state.detailPath = [.peers]

        state.selectTorrent(43)

        XCTAssertEqual(state.selectedTorrentID, 43)
        XCTAssertTrue(state.isDetailPresented)
        XCTAssertTrue(state.detailPath.isEmpty)
    }

    func testRemovingSelectedTorrentClosesInspectorAndClearsNavigation() {
        var state = iOSNavigationState()
        state.selectTorrent(42)
        state.detailPath = [.files]

        state.reconcileTorrentSelection(availableIDs: [43])

        XCTAssertNil(state.selectedTorrentID)
        XCTAssertTrue(state.detailPath.isEmpty)
        XCTAssertFalse(state.isDetailPresented)
    }

    func testServerChangeCannotReuseATorrentDestinationWithTheSameID() {
        var state = iOSNavigationState()
        state.selectTorrent(42)
        state.detailPath = [.peers]

        state.clearTorrentSelection()

        XCTAssertFalse(state.isDetailPresented)
        XCTAssertNil(state.selectedTorrentID)

        state.selectTorrent(42)

        XCTAssertTrue(state.detailPath.isEmpty)
        XCTAssertTrue(state.isDetailPresented)
    }
    func testNoSelectionCannotOpenAnEmptyInspector() {
        var state = iOSNavigationState()
        state.presentation = .inspector
        state.setInspectorPresented(true)
        XCTAssertFalse(state.isInspectorPresented)
        XCTAssertFalse(state.isDetailPresented)
    }

    func testCompactSelectionPushesDetailsAndBackReturnsToList() {
        var state = iOSNavigationState()
        state.selectTorrent(42)
        XCTAssertEqual(state.stackPath, [.overview])
        XCTAssertFalse(state.isInspectorPresented)

        state.setStackPath([.overview, .files])
        XCTAssertEqual(state.detailPath, [.files])
        state.setStackPath([.overview])
        XCTAssertTrue(state.detailPath.isEmpty)
        state.setStackPath([])
        XCTAssertFalse(state.isDetailPresented)
        XCTAssertTrue(state.stackPath.isEmpty)
    }

    func testAdaptationPreservesRouteAndIgnoresOutgoingContainerDismissal() {
        var state = iOSNavigationState()
        state.selectTorrent(42)
        state.setStackPath([.overview, .files])
        state.presentation = .inspector
        state.setStackPath([])

        XCTAssertTrue(state.isInspectorPresented)
        XCTAssertEqual(state.detailPath, [.files])
        XCTAssertTrue(state.stackPath.isEmpty)

        state.presentation = .stack
        state.setInspectorPresented(false)
        state.setInspectorPath([])
        XCTAssertEqual(state.stackPath, [.overview, .files])
        XCTAssertEqual(state.selectedTorrentID, 42)
    }

    func testHiddenDetailsStayHiddenAcrossAdaptation() {
        var state = iOSNavigationState()
        state.presentation = .inspector
        state.selectTorrent(42)
        state.setInspectorPath([.peers])
        state.hideDetails()
        state.presentation = .stack
        XCTAssertTrue(state.stackPath.isEmpty)
        state.presentation = .inspector
        XCTAssertFalse(state.isInspectorPresented)
        state.selectTorrent(42)
        XCTAssertEqual(state.detailPath, [.peers])
        XCTAssertTrue(state.isInspectorPresented)
    }
}
