import SwiftUI
import XCTest
@testable import BitDream

@MainActor
final class HapticFeedbackTests: XCTestCase {
    func testSemanticFeedbackUsesAppleSystemPatterns() {
        XCTAssertEqual(
            AppHapticFeedback.actionTriggered.sensoryFeedback,
            .impact(weight: .light, intensity: 0.7)
        )
        XCTAssertEqual(AppHapticFeedback.selectionChanged.sensoryFeedback, .selection)
        XCTAssertEqual(AppHapticFeedback.operationSucceeded.sensoryFeedback, .success)
        XCTAssertEqual(AppHapticFeedback.operationNeedsAttention.sensoryFeedback, .warning)
        XCTAssertEqual(AppHapticFeedback.operationFailed.sensoryFeedback, .error)
    }

    func testTriggersIncrementTheMatchingFeedbackOnly() {
        var triggers = HapticFeedbackTriggers()

        triggers.play(.actionTriggered)
        triggers.play(.selectionChanged)
        triggers.play(.operationSucceeded)
        triggers.play(.operationSucceeded)
        triggers.play(.operationNeedsAttention)
        triggers.play(.operationFailed)

        XCTAssertEqual(triggers.action, 1)
        XCTAssertEqual(triggers.selection, 1)
        XCTAssertEqual(triggers.success, 2)
        XCTAssertEqual(triggers.warning, 1)
        XCTAssertEqual(triggers.error, 1)
    }

    func testDisabledClientIsInert() {
        HapticFeedbackClient.disabled.play(.operationFailed)
    }

    func testRefreshOutcomeFeedbackOnlyReportsTerminalResults() {
        XCTAssertEqual(RefreshOutcome.succeeded.appHapticFeedback, .operationSucceeded)
        XCTAssertEqual(RefreshOutcome.unavailable.appHapticFeedback, .operationNeedsAttention)
        XCTAssertEqual(RefreshOutcome.failed.appHapticFeedback, .operationFailed)
        XCTAssertNil(RefreshOutcome.cancelled.appHapticFeedback)
    }

    func testSettingsSaveFeedbackReportsEditsAndFailures() {
        let error = TransmissionErrorPresentation(title: "Error", message: "Failed")
        XCTAssertNil(SessionSettingsSaveState.idle.appHapticFeedback)
        XCTAssertEqual(SessionSettingsSaveState.pending.appHapticFeedback, .selectionChanged)
        XCTAssertNil(SessionSettingsSaveState.saving.appHapticFeedback)
        XCTAssertEqual(SessionSettingsSaveState.failed(error).appHapticFeedback, .operationFailed)
    }

    func testFreeSpaceFeedbackReportsTerminalOutcome() {
        let summary = SessionFreeSpaceSummary(freeSpace: "10 GB", totalSpace: "20 GB", percentUsed: "50%")
        let error = TransmissionErrorPresentation(title: "Error", message: "Failed")
        XCTAssertNil(SessionFreeSpaceState.idle.appHapticFeedback)
        XCTAssertNil(SessionFreeSpaceState.checking(previous: nil).appHapticFeedback)
        XCTAssertEqual(SessionFreeSpaceState.result(summary).appHapticFeedback, .operationSucceeded)
        XCTAssertEqual(SessionFreeSpaceState.failed(error).appHapticFeedback, .operationFailed)
    }

    func testPortFeedbackDistinguishesSuccessWarningAndFailure() {
        let error = TransmissionErrorPresentation(title: "Error", message: "Failed")
        XCTAssertNil(SessionPortTestState.idle.appHapticFeedback)
        XCTAssertNil(SessionPortTestState.testing.appHapticFeedback)
        XCTAssertEqual(SessionPortTestState.result(.open(protocolName: "IPv4")).appHapticFeedback, .operationSucceeded)
        XCTAssertEqual(SessionPortTestState.result(.closed(protocolName: "IPv4")).appHapticFeedback, .operationNeedsAttention)
        XCTAssertEqual(SessionPortTestState.result(.checkerUnavailable).appHapticFeedback, .operationNeedsAttention)
        XCTAssertEqual(SessionPortTestState.failed(error).appHapticFeedback, .operationFailed)
    }

    func testBlocklistFeedbackReportsTerminalOutcome() {
        let error = TransmissionErrorPresentation(title: "Error", message: "Failed")
        XCTAssertNil(SessionBlocklistUpdateState.idle.appHapticFeedback)
        XCTAssertNil(SessionBlocklistUpdateState.updating.appHapticFeedback)
        XCTAssertEqual(SessionBlocklistUpdateState.success(ruleCount: 42).appHapticFeedback, .operationSucceeded)
        XCTAssertEqual(SessionBlocklistUpdateState.failed(error).appHapticFeedback, .operationFailed)
    }
}
