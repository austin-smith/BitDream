import SwiftUI

// TODO: Remove this file in phases 4/5 once callers stop using
// `TransmissionResponse` and `handleTransmissionResponse` for UI error handling.
/// Handles legacy `TransmissionResponse` values with user-facing error presentation.
func handleTransmissionResponse(
    _ response: TransmissionResponse,
    onSuccess: @escaping () -> Void,
    onError: @escaping (String) -> Void
) {
    guard let presentation = TransmissionLegacyCompatibility.presentation(for: response) else {
        onSuccess()
        return
    }

    onError(presentation.message)
}

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
