#if BITDREAM_SAMPLE_SUPPORT
import SwiftData
import Foundation

@MainActor
final class DemoSession {
    let container: ModelContainer
    let userDefaults: UserDefaults
    let repository: SampleHostRepository
    let store: TransmissionStore
    let serverServices: ServerServices
    private let hosts: [Host]
    private var hasStarted = false

    init(
        userDefaults: UserDefaults? = nil,
        automaticallyRetriesConnection: Bool = true,
        wallTime: @escaping @Sendable () -> Date = { Date() }
    ) {
        guard let defaults = userDefaults ?? UserDefaults(suiteName: "\(AppIdentity.bundleIdentifier).demo") else {
            preconditionFailure("Unable to create demo preferences.")
        }
        defaults.registerViewStateDefaults()
        defaults.register(defaults: ["sortProperty": SortProperty.dateAdded.rawValue, "sortOrder": false])
        self.userDefaults = defaults
        hosts = SampleFixtures.makeHosts()
        container = SampleFixtures.makeModelContainer(hosts: hosts)
        let repository = SampleHostRepository(modelContext: container.mainContext)
        self.repository = repository
        do {
            let server = try SampleTransmissionServer()
            let resolver: @Sendable (TransmissionConnectionDescriptor) async throws -> TransmissionConnection = { descriptor in
                try server.connection(for: descriptor)
            }
            store = TransmissionStore(
                resolveConnection: resolver,
                snapshotWriter: WidgetSnapshotWriter(writeServerIndex: { _ in }, writeSessionSnapshot: { _, _, _, _, _ in }, reloadTimelines: {}),
                userDefaults: defaults, automaticallyRetriesConnection: automaticallyRetriesConnection,
                updateBackgroundActivityInterval: { _ in },
                persistVersion: { id, version in await repository.persistVersionIfNeeded(serverID: id, version: version) },
                wallTime: wallTime
            )
            serverServices = ServerServices(
                testConnection: { descriptor in try await resolver(descriptor).fetchSessionSettings() },
                readPassword: { _ in "" }, allowsTailscale: false
            )
        } catch {
            preconditionFailure("Invalid demo fixtures: \(error)")
        }
    }

    func start() {
        guard !hasStarted, let host = hosts.first else { return }
        hasStarted = true
        store.setHost(host: host)
    }
}
#endif
