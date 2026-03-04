#if os(iOS)
import SwiftUI
import UIKit

@MainActor
final class AppIconManager: ObservableObject {
    static let shared = AppIconManager()

    @Published private(set) var currentIconName: String?
    @Published private(set) var isChanging: Bool = false
    @Published var lastError: String?

    var supportsAlternateIcons: Bool {
        UIApplication.shared.supportsAlternateIcons
    }

    private var foregroundObserver: NSObjectProtocol?

    private init() {
        currentIconName = UIApplication.shared.alternateIconName
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshCurrentIcon()
            }
        }
    }

    func refreshCurrentIcon() {
        currentIconName = UIApplication.shared.alternateIconName
    }

    func selectIcon(name: String?) {
        lastError = nil

        guard supportsAlternateIcons else {
            lastError = "Alternate icons not supported on this device."
            return
        }

        // Avoid triggering the system alert when re-selecting the same icon.
        guard currentIconName != name else { return }

        isChanging = true
        UIApplication.shared.setAlternateIconName(name) { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                self.isChanging = false

                if let error = error {
                    self.lastError = "Failed to change icon: \(error.localizedDescription)"
                } else {
                    self.lastError = nil
                    self.currentIconName = name
                }
            }
        }
    }
}
#endif
