import Combine
import Observation

/// A window owns its connection and presentation flags, not the saved server catalog.
/// Kept platform-neutral so the lifecycle can be exercised by the unit-test target.
@MainActor
@Observable
final class iOSWindowSession {
    let store: TransmissionStore
    private var serverChanges: AnyCancellable?

    init(store: TransmissionStore = TransmissionStore()) {
        self.store = store
        serverChanges = ServerChanges.publisher.sink { [weak self] change in
            guard let self, change.source !== self.store else { return }
            switch change.mutation {
            case .updated(let host):
                self.store.applyPersistedHostUpdate(host)
            case .deleted(let serverID, let remainingHosts):
                completeServerDeletion(serverID: serverID, store: self.store, remainingHosts: remainingHosts)
            }
        }
    }

    isolated deinit {
        // Polling tasks retain the store while running; closing the owner must stop them.
        serverChanges?.cancel()
        store.clearSelectedHost()
    }
}
