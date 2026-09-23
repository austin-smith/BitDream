import SwiftUI

struct TorrentFilterSynchronization: ViewModifier {
    let preferences: TorrentFilterPreferences
    @ObservedObject var store: TransmissionStore

    func body(content: Content) -> some View {
        content
            .onChange(of: store.host?.serverID, initial: true) {
                synchronize()
            }
            .onChange(of: store.availableLabels) {
                synchronize()
            }
            .onChange(of: store.hasLoadedSnapshot) {
                synchronize()
            }
    }

    private func synchronize() {
        preferences.synchronize(
            serverID: store.host?.serverID,
            availableLabels: store.availableLabels,
            hasLoadedSnapshot: store.hasLoadedSnapshot
        )
    }
}
