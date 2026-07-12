#if os(iOS)
import SwiftUI

extension EnvironmentValues {
    @Entry var hapticFeedback: HapticFeedbackClient = .disabled
}

struct iOSHapticFeedbackHost<Content: View>: View {
    @AppStorage(UserDefaultsKeys.hapticFeedbackEnabled)
    private var isHapticFeedbackEnabled = AppDefaults.hapticFeedbackEnabled

    @State private var triggers = HapticFeedbackTriggers()
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .environment(\.hapticFeedback, HapticFeedbackClient { feedback in
                guard isHapticFeedbackEnabled else { return }
                triggers.play(feedback)
            })
            .sensoryFeedback(.impact(weight: .light, intensity: 0.7), trigger: triggers.action)
            .sensoryFeedback(.selection, trigger: triggers.selection)
            .sensoryFeedback(.success, trigger: triggers.success)
            .sensoryFeedback(.warning, trigger: triggers.warning)
            .sensoryFeedback(.error, trigger: triggers.error)
    }
}

private struct iOSHapticNavigationTransitionModifier: ViewModifier {
    @Environment(\.hapticFeedback) private var hapticFeedback

    func body(content: Content) -> some View {
        content
            .onAppear {
                hapticFeedback.play(.actionTriggered)
            }
            .onDisappear {
                hapticFeedback.play(.actionTriggered)
            }
    }
}

private struct iOSHapticControlActivationModifier: ViewModifier {
    @Environment(\.hapticFeedback) private var hapticFeedback
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            TapGesture().onEnded {
                guard isEnabled else { return }
                hapticFeedback.play(.actionTriggered)
            }
        )
    }
}

extension View {
    func iOSHapticNavigationTransition() -> some View {
        modifier(iOSHapticNavigationTransitionModifier())
    }

    func iOSHapticControlActivation() -> some View {
        modifier(iOSHapticControlActivationModifier())
    }
}

#if DEBUG
#Preview("Haptic Feedback Host") {
    iOSHapticFeedbackHost {
        Text("Haptic feedback is attached at the scene root.")
            .padding()
    }
}
#endif
#endif
