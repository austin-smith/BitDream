#if os(iOS)
import SwiftUI
import UIKit

/// Shared manager for reading and updating the current app icon on iOS.
/// Centralizes state so multiple views stay in sync and refreshes on foreground.
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

    deinit {
        if let observer = foregroundObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Refresh the in-memory state from the system.
    func refreshCurrentIcon() {
        currentIconName = UIApplication.shared.alternateIconName
    }

    /// Attempt to switch to a specific icon name (nil = primary).
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
            DispatchQueue.main.async {
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

