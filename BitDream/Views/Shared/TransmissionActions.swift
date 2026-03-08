import Foundation
import SwiftUI

enum TransmissionActionFailureContext: Sendable {
    case addTorrent
    case askForMorePeers
    case pauseAllTorrents
    case pauseTorrents
    case queueMove
    case removeTorrents
    case resumeAllTorrents
    case resumeTorrents
    case resumeTorrentsNow
    case verifyTorrents

    var debugBrief: String {
        switch self {
        case .addTorrent:
            "Failed to add torrent"
        case .askForMorePeers:
            "Failed to ask for more peers"
        case .pauseAllTorrents:
            "Failed to pause all torrents"
        case .pauseTorrents:
            "Failed to pause torrents"
        case .queueMove:
            "Failed to move torrents in queue"
        case .removeTorrents:
            "Failed to remove torrent"
        case .resumeAllTorrents:
            "Failed to resume all torrents"
        case .resumeTorrents:
            "Failed to resume torrents"
        case .resumeTorrentsNow:
            "Failed to resume torrents now"
        case .verifyTorrents:
            "Failed to verify torrent"
        }
    }

    func inlineMessage(detail: String) -> String {
        "\(debugBrief): \(detail)"
    }

#if os(macOS)
    var globalAlertTitle: String {
        switch self {
        case .queueMove:
            "Queue Error"
        default:
            "Error"
        }
    }

    func globalAlertMessage(detail: String) -> String {
        "\(debugBrief)\n\n\(detail)"
    }
#endif
}

@MainActor
func presentTransmissionError(
    _ error: Error,
    onError: @escaping @MainActor @Sendable (String) -> Void
) {
    guard let message = TransmissionUserFacingError.message(for: error) else {
        return
    }

    onError(message)
}

@MainActor
/// Use for button taps and similar event handlers that intentionally launch detached async work.
func performTransmissionAction(
    operation: @escaping @MainActor @Sendable () async throws -> Void,
    onSuccess: @escaping @MainActor @Sendable () -> Void = {},
    onError: @escaping @MainActor @Sendable (String) -> Void
) {
    Task { @MainActor in
        do {
            try await operation()
            onSuccess()
        } catch {
            presentTransmissionError(error, onError: onError)
        }
    }
}

@MainActor
/// Use for button taps and similar event handlers that intentionally launch detached async work.
func performTransmissionAction<Result>(
    operation: @escaping @MainActor @Sendable () async throws -> Result,
    onSuccess: @escaping @MainActor @Sendable (Result) -> Void,
    onError: @escaping @MainActor @Sendable (String) -> Void
) {
    Task { @MainActor in
        do {
            let result = try await operation()
            onSuccess(result)
        } catch {
            presentTransmissionError(error, onError: onError)
        }
    }
}

@MainActor
/// Use for `.task`, `.refreshable`, and other structured lifetimes that must preserve parent cancellation.
func performStructuredTransmissionOperation<Result>(
    operation: @escaping @MainActor @Sendable () async throws -> Result,
    onError: @escaping @MainActor @Sendable (String) -> Void
) async -> Result? {
    do {
        try Task.checkCancellation()
        let result = try await operation()
        try Task.checkCancellation()
        return result
    } catch {
        presentTransmissionError(error, onError: onError)
        return nil
    }
}

@MainActor
func performTransmissionDebugAction(
    _ context: TransmissionActionFailureContext,
    store: TransmissionStore,
    operation: @escaping @MainActor @Sendable () async throws -> Void,
    onSuccess: @escaping @MainActor @Sendable () -> Void = {}
) {
    performTransmissionAction(
        operation: operation,
        onSuccess: onSuccess,
        onError: makeTransmissionDebugErrorHandler(
            store: store,
            context: context
        )
    )
}

#if os(macOS)
@MainActor
func performTransmissionGlobalAlertAction(
    _ context: TransmissionActionFailureContext,
    store: TransmissionStore,
    operation: @escaping @MainActor @Sendable () async throws -> Void,
    onSuccess: @escaping @MainActor @Sendable () -> Void = {}
) {
    performTransmissionAction(
        operation: operation,
        onSuccess: onSuccess,
        onError: makeTransmissionGlobalAlertHandler(
            store: store,
            context: context
        )
    )
}
#endif

@MainActor
func makeTransmissionBindingErrorHandler(
    isPresented: Binding<Bool>,
    message: Binding<String>
) -> @MainActor @Sendable (String) -> Void {
    { text in
        message.wrappedValue = text
        isPresented.wrappedValue = true
    }
}

@MainActor
func makeTransmissionDebugErrorHandler(
    store: TransmissionStore,
    context: TransmissionActionFailureContext
) -> @MainActor @Sendable (String) -> Void {
    { message in
        store.debugBrief = context.debugBrief
        store.debugMessage = message
        store.isError = true
    }
}

#if os(macOS)
@MainActor
func makeTransmissionGlobalAlertHandler(
    store: TransmissionStore,
    context: TransmissionActionFailureContext
) -> @MainActor @Sendable (String) -> Void {
    { message in
        store.globalAlertTitle = context.globalAlertTitle
        store.globalAlertMessage = message
        store.showGlobalAlert = true
    }
}
#endif

struct TransmissionErrorAlert: ViewModifier {
    @Binding var isPresented: Bool
    let message: String

    func body(content: Content) -> some View {
        content
            .alert("Error", isPresented: $isPresented) {
                Button("OK") { }
            } message: {
                Text(message)
            }
    }
}

extension View {
    func transmissionErrorAlert(isPresented: Binding<Bool>, message: String) -> some View {
        modifier(TransmissionErrorAlert(isPresented: isPresented, message: message))
    }
}
