#if os(macOS)
import AppKit
import Combine
import Foundation
import SwiftUI

private struct DockBadgeMetrics: Equatable {
    var isConnected = false
    var completedTorrentCount = 0
    var downloadSpeed: Int64 = 0
    var uploadSpeed: Int64 = 0
}

private struct DockBadgePreferences: Equatable {
    let showCompleted: Bool
    let showDownload: Bool
    let showUpload: Bool

    init(defaults: UserDefaults) {
        showCompleted = defaults.object(forKey: UserDefaultsKeys.dockShowCompletedBadge) as? Bool
            ?? AppDefaults.dockShowCompletedBadge
        showDownload = defaults.object(forKey: UserDefaultsKeys.dockShowDownloadSpeed) as? Bool
            ?? AppDefaults.dockShowDownloadSpeed
        showUpload = defaults.object(forKey: UserDefaultsKeys.dockShowUploadSpeed) as? Bool
            ?? AppDefaults.dockShowUploadSpeed
    }
}

@MainActor
final class DockBadgeController: ObservableObject {
    private let defaults: UserDefaults
    private weak var store: TransmissionStore?
    private var cancellables = Set<AnyCancellable>()
    private var metrics = DockBadgeMetrics()
    private var preferences: DockBadgePreferences
    private var speedTileView: DockSpeedTileHostingView?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        preferences = DockBadgePreferences(defaults: defaults)
    }

    func configure(store: TransmissionStore) {
        preferences = DockBadgePreferences(defaults: defaults)
        if self.store !== store || cancellables.isEmpty {
            metrics = DockBadgeMetrics()
            self.store = store
            observeChanges(store)
        }
        updateDockTile()
    }

    private func observeChanges(_ store: TransmissionStore) {
        cancellables.removeAll()

        let transferRates = store.$sessionStats
            .map { stats in
                (
                    download: stats?.downloadSpeed ?? 0,
                    upload: stats?.uploadSpeed ?? 0
                )
            }

        let completedTorrentCount = store.$torrents
            .map { torrents in
                torrents.lazy.filter { $0.statusCalc == .complete }.count
            }

        let isConnected = store.$connectionStatus
            .map { status in
                if case .connected = status { return true }
                return false
            }

        Publishers.CombineLatest3(transferRates, completedTorrentCount, isConnected)
            .map { transferRates, completedTorrentCount, isConnected in
                DockBadgeMetrics(
                    isConnected: isConnected,
                    completedTorrentCount: completedTorrentCount,
                    downloadSpeed: transferRates.download,
                    uploadSpeed: transferRates.upload
                )
            }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] metrics in
                self?.metrics = metrics
                self?.updateDockTile()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification, object: defaults)
            .receive(on: RunLoop.main)
            .map { [defaults] _ in DockBadgePreferences(defaults: defaults) }
            .removeDuplicates()
            .sink { [weak self] preferences in
                guard let self, preferences != self.preferences else { return }
                self.preferences = preferences
                self.updateDockTile()
            }
            .store(in: &cancellables)
    }

    private func updateDockTile() {
        let dockTile = NSApplication.shared.dockTile
        let badgeLabel = metrics.isConnected && preferences.showCompleted && metrics.completedTorrentCount > 0
            ? String(metrics.completedTorrentCount)
            : nil
        var needsDisplay = false

        if dockTile.badgeLabel != badgeLabel {
            dockTile.badgeLabel = badgeLabel
            needsDisplay = true
        }

        let content = DockSpeedTileContent(
            downloadSpeed: speedValue(isEnabled: preferences.showDownload, bytesPerSecond: metrics.downloadSpeed),
            uploadSpeed: speedValue(isEnabled: preferences.showUpload, bytesPerSecond: metrics.uploadSpeed)
        )

        if content.downloadSpeed != nil || content.uploadSpeed != nil {
            let alreadyInstalled = dockTile.contentView === speedTileView
            let speedTileView = installedSpeedTileView(for: dockTile)
            needsDisplay = !alreadyInstalled || speedTileView.update(content: content) || needsDisplay
        } else if dockTile.contentView === speedTileView {
            dockTile.contentView = nil
            speedTileView = nil
            needsDisplay = true
        }

        if needsDisplay {
            dockTile.display()
        }
    }

    private func speedValue(isEnabled: Bool, bytesPerSecond: Int64) -> Int64? {
        guard metrics.isConnected, isEnabled, bytesPerSecond > 0 else { return nil }
        return bytesPerSecond
    }

    private func installedSpeedTileView(for dockTile: NSDockTile) -> DockSpeedTileHostingView {
        if let speedTileView, dockTile.contentView === speedTileView {
            return speedTileView
        }

        let view = DockSpeedTileHostingView(frame: NSRect(origin: .zero, size: dockTile.size))
        view.autoresizingMask = [.width, .height]
        dockTile.contentView = view
        speedTileView = view
        return view
    }
}
#endif
