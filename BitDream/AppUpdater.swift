#if os(macOS)
import Foundation
import Sparkle

@MainActor
final class AppUpdater: NSObject, ObservableObject {
    @Published private(set) var canCheckForUpdates: Bool = false
    @Published private(set) var lastUpdateCheckDate: Date?

    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: self,
        userDriverDelegate: nil
    )

    private var hasStartedUpdater = false

    var automaticallyChecksForUpdates: Bool {
        get { updaterController.updater.automaticallyChecksForUpdates }
        set { updaterController.updater.automaticallyChecksForUpdates = newValue }
    }

    override init() {
        super.init()
        // Force initialization after self is fully initialized.
        _ = updaterController
        refreshState()
    }

    func start() {
        guard !hasStartedUpdater else { return }
        updaterController.startUpdater()
        hasStartedUpdater = true
        refreshState()
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        updaterController.checkForUpdates(nil)
    }

    private func refreshState() {
        canCheckForUpdates = updaterController.updater.canCheckForUpdates
        lastUpdateCheckDate = updaterController.updater.lastUpdateCheckDate
    }
}

extension AppUpdater: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        refreshState()
    }
}

#endif
