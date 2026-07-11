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
        supportsAlternateIconsProvider()
    }

    private var foregroundObserver: NSObjectProtocol?
    private let supportsAlternateIconsProvider: () -> Bool
    private let currentIconNameProvider: () -> String?
    private let setAlternateIconName: (String?, @escaping @Sendable (Error?) -> Void) -> Void

    init(
        supportsAlternateIcons: @escaping () -> Bool = { UIApplication.shared.supportsAlternateIcons },
        currentIconName: @escaping () -> String? = { UIApplication.shared.alternateIconName },
        setAlternateIconName: @escaping (String?, @escaping @Sendable (Error?) -> Void) -> Void = { name, completion in
            UIApplication.shared.setAlternateIconName(name, completionHandler: completion)
        },
        observesApplicationForeground: Bool = true
    ) {
        self.supportsAlternateIconsProvider = supportsAlternateIcons
        self.currentIconNameProvider = currentIconName
        self.setAlternateIconName = setAlternateIconName
        self.currentIconName = currentIconName()

        if observesApplicationForeground {
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
    }

    static func inert(currentIconName: String? = nil) -> AppIconManager {
        AppIconManager(
            supportsAlternateIcons: { true },
            currentIconName: { currentIconName },
            setAlternateIconName: { _, completion in completion(nil) },
            observesApplicationForeground: false
        )
    }

    func refreshCurrentIcon() {
        currentIconName = currentIconNameProvider()
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
        setAlternateIconName(name) { [weak self] error in
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
