import SwiftUI

enum AppHapticFeedback: Sendable, Equatable {
    case actionTriggered
    case selectionChanged
    case operationSucceeded
    case operationNeedsAttention
    case operationFailed

    var sensoryFeedback: SensoryFeedback {
        switch self {
        case .actionTriggered:
            .impact(weight: .light, intensity: 0.7)
        case .selectionChanged:
            .selection
        case .operationSucceeded:
            .success
        case .operationNeedsAttention:
            .warning
        case .operationFailed:
            .error
        }
    }
}

struct HapticFeedbackClient: Sendable {
    private let playAction: @MainActor @Sendable (AppHapticFeedback) -> Void

    init(play: @escaping @MainActor @Sendable (AppHapticFeedback) -> Void) {
        self.playAction = play
    }

    @MainActor
    func play(_ feedback: AppHapticFeedback) {
        playAction(feedback)
    }

    static let disabled = Self(play: { _ in })
}

struct HapticFeedbackTriggers: Equatable {
    private(set) var action = 0
    private(set) var selection = 0
    private(set) var success = 0
    private(set) var warning = 0
    private(set) var error = 0

    mutating func play(_ feedback: AppHapticFeedback) {
        switch feedback {
        case .actionTriggered:
            action &+= 1
        case .selectionChanged:
            selection &+= 1
        case .operationSucceeded:
            success &+= 1
        case .operationNeedsAttention:
            warning &+= 1
        case .operationFailed:
            error &+= 1
        }
    }
}

extension RefreshOutcome {
    var appHapticFeedback: AppHapticFeedback? {
        switch self {
        case .succeeded:
            .operationSucceeded
        case .unavailable:
            .operationNeedsAttention
        case .failed:
            .operationFailed
        case .cancelled:
            nil
        }
    }
}

extension SessionSettingsSaveState {
    var appHapticFeedback: AppHapticFeedback? {
        switch self {
        case .pending:
            .selectionChanged
        case .failed:
            .operationFailed
        case .idle, .saving:
            nil
        }
    }
}

extension SessionFreeSpaceState {
    var appHapticFeedback: AppHapticFeedback? {
        switch self {
        case .result:
            .operationSucceeded
        case .failed:
            .operationFailed
        case .idle, .checking:
            nil
        }
    }
}

extension SessionPortTestState {
    var appHapticFeedback: AppHapticFeedback? {
        switch self {
        case .result(.open):
            .operationSucceeded
        case .result(.closed), .result(.checkerUnavailable):
            .operationNeedsAttention
        case .failed:
            .operationFailed
        case .idle, .testing:
            nil
        }
    }
}

extension SessionBlocklistUpdateState {
    var appHapticFeedback: AppHapticFeedback? {
        switch self {
        case .success:
            .operationSucceeded
        case .failed:
            .operationFailed
        case .idle, .updating:
            nil
        }
    }
}
