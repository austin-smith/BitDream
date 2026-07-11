#if os(macOS)
import Foundation
import Sparkle

@MainActor
final class AppUpdater: NSObject, ObservableObject {
    static let defaultAutomaticallyChecksForUpdates = true

    @Published private(set) var canCheckForUpdates: Bool = false
    @Published private(set) var lastUpdateCheckDate: Date?

    private var updaterController: SPUStandardUpdaterController?
    private var disabledAutomaticallyChecksForUpdates = AppUpdater.defaultAutomaticallyChecksForUpdates

    private var hasStartedUpdater = false
    private var canCheckObservation: NSKeyValueObservation?

    var automaticallyChecksForUpdates: Bool {
        get { updaterController?.updater.automaticallyChecksForUpdates ?? disabledAutomaticallyChecksForUpdates }
        set {
            if let updaterController {
                updaterController.updater.automaticallyChecksForUpdates = newValue
            } else {
                disabledAutomaticallyChecksForUpdates = newValue
            }
        }
    }

    init(updatesEnabled: Bool = true) {
        super.init()
        guard updatesEnabled else { return }

        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        observeUpdaterState()
        refreshState()
    }

    func start() {
        guard !hasStartedUpdater, let updaterController else { return }
        updaterController.startUpdater()
        hasStartedUpdater = true
        refreshState()
    }

    func checkForUpdates() {
        guard canCheckForUpdates, let updaterController else { return }
        updaterController.checkForUpdates(nil)
    }

    func resetToDefaults() {
        automaticallyChecksForUpdates = Self.defaultAutomaticallyChecksForUpdates
    }

    private func refreshState() {
        guard let updaterController else {
            canCheckForUpdates = false
            lastUpdateCheckDate = nil
            return
        }
        canCheckForUpdates = updaterController.updater.canCheckForUpdates
        lastUpdateCheckDate = updaterController.updater.lastUpdateCheckDate
    }

    private func observeUpdaterState() {
        guard let updaterController else { return }
        canCheckObservation = updaterController.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, change in
            guard let value = change.newValue else { return }
            Task { @MainActor [weak self] in
                self?.canCheckForUpdates = value
            }
        }
    }
}

extension AppUpdater: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        refreshState()
    }
}

#endif
