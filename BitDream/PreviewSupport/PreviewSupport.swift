#if DEBUG
import SwiftData
import SwiftUI
import Observation

@MainActor
enum PreviewScenario {
    case empty
    case connected
    case reconnecting
    case error
}

@MainActor
@Observable
final class PreviewEnvironment {
    let container: ModelContainer
    let hosts: [Host]
    let hostRepository: any HostPersisting
    let store: TransmissionStore
    let serverServices: ServerServices
    let themeManager: ThemeManager
    let userDefaults: UserDefaults
    let scenario: PreviewScenario
    #if os(iOS)
    let appIconManager: AppIconManager
    #endif
    #if os(macOS) && canImport(Sparkle)
    let appUpdater: AppUpdater
    #endif
    #if os(macOS)
    let serverEditingCoordinator: MacOSServerEditingCoordinator
    #endif

    init(scenario: PreviewScenario = .connected) {
        self.scenario = scenario
        let suiteName = "BitDream.Preview.\(UUID().uuidString)"
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Unable to create isolated preview preferences.")
        }
        let hosts = PreviewFixtures.makeHosts()
        let server: SampleTransmissionServer
        do { server = try SampleTransmissionServer() } catch { preconditionFailure("Invalid sample data: \(error)") }
        self.userDefaults = userDefaults
        self.hosts = hosts
        self.container = PreviewFixtures.makeModelContainer(hosts: hosts)
        self.hostRepository = SampleHostRepository(modelContext: container.mainContext)
        self.store = PreviewFixtures.makeStore(
            scenario: scenario,
            selectedHost: hosts.first,
            userDefaults: userDefaults,
            server: server
        )
        self.serverServices = ServerServices(
            testConnection: { try await server.connection(for: $0).fetchSessionSettings() },
            readPassword: { _ in "" }, allowsTailscale: false
        )
        self.themeManager = ThemeManager(userDefaults: userDefaults)
        #if os(iOS)
        self.appIconManager = AppIconManager.inert()
        #endif
        #if os(macOS) && canImport(Sparkle)
        self.appUpdater = AppUpdater(updatesEnabled: false)
        #endif
        #if os(macOS)
        self.serverEditingCoordinator = MacOSServerEditingCoordinator()
        #endif
    }

}

@MainActor
struct PreviewContainer<Content: View>: View {
    @State private var previewEnvironment: PreviewEnvironment
    private let content: (PreviewEnvironment) -> Content

    init(
        scenario: PreviewScenario = .connected,
        @ViewBuilder content: @escaping (PreviewEnvironment) -> Content
    ) {
        _previewEnvironment = State(initialValue: PreviewEnvironment(scenario: scenario))
        self.content = content
    }

    var body: some View {
        configuredContent
            .modelContainer(previewEnvironment.container)
            .defaultAppStorage(previewEnvironment.userDefaults)
            .environment(\.appUserDefaults, previewEnvironment.userDefaults)
            .environment(
                \.hostRepositoryProvider,
                HostRepositoryProvider(resolve: { previewEnvironment.hostRepository })
            )
            .environmentObject(previewEnvironment.store)
            .environmentObject(previewEnvironment.themeManager)
            .environment(\.presentationDate, SampleLibrary.referenceDate)
            .environment(\.serverServices, previewEnvironment.serverServices)
            .task {
                if previewEnvironment.scenario == .connected {
                    previewEnvironment.store.reconnect()
                }
            }
    }

    @ViewBuilder
    private var configuredContent: some View {
        #if os(macOS) && canImport(Sparkle)
        content(previewEnvironment)
            .environmentObject(previewEnvironment.appUpdater)
            .environmentObject(previewEnvironment.serverEditingCoordinator)
        #elseif os(macOS)
        content(previewEnvironment)
            .environmentObject(previewEnvironment.serverEditingCoordinator)
        #elseif os(iOS)
        content(previewEnvironment)
            .environmentObject(previewEnvironment.appIconManager)
        #else
        content(previewEnvironment)
        #endif
    }
}

@MainActor
enum PreviewFixtures {
    static let referenceDate = SampleLibrary.referenceDate
    static let torrents = SampleFixtures.torrents
    static let sessionStats = SampleFixtures.sessionStats
    static let sessionConfiguration = SampleFixtures.sessionConfiguration
    static let files = SampleFixtures.details[0].files
    static let fileStats = SampleFixtures.details[0].fileStats
    static let peers = SampleFixtures.details[0].peers
    static let peersFrom = SampleFixtures.details[0].peersFrom!

    static func makeHosts() -> [Host] { SampleFixtures.makeHosts() }

    static func makeModelContainer(hosts: [Host] = makeHosts()) -> ModelContainer {
        SampleFixtures.makeModelContainer(hosts: hosts)
    }

    static func makeStore(
        scenario: PreviewScenario = .connected,
        selectedHost: Host? = makeHosts().first,
        userDefaults: UserDefaults = .standard,
        server: SampleTransmissionServer? = nil
    ) -> TransmissionStore {
        let sender: SampleTransmissionServer
        do { sender = try server ?? SampleTransmissionServer() } catch { preconditionFailure("Invalid sample data: \(error)") }
        let store = TransmissionStore(
            resolveConnection: { descriptor in
                try sender.connection(for: descriptor)
            },
            snapshotWriter: WidgetSnapshotWriter(
                writeServerIndex: { _ in },
                writeSessionSnapshot: { _, _, _, _, _ in },
                reloadTimelines: {}
            ),
            userDefaults: userDefaults,
            automaticallyRetriesConnection: false,
            updateBackgroundActivityInterval: { _ in },
            persistVersion: { _, _ in },
            wallTime: { SampleLibrary.referenceDate }
        )

        switch scenario {
        case .empty:
            break
        case .connected:
            store.host = selectedHost
            store.torrents = torrents
            store.sessionStats = sessionStats
            store.sessionConfiguration = sessionConfiguration
            store.defaultDownloadDir = SampleLibrary.downloadDirectory
            store.connectionState = .connected
            store.lastRefreshAt = referenceDate
        case .reconnecting:
            store.host = selectedHost
            store.torrents = torrents
            store.sessionStats = sessionStats
            store.lastRefreshAt = referenceDate
            store.connectionState = .failed(.timeout, retryAt: referenceDate.addingTimeInterval(15))
        case .error:
            store.host = selectedHost
            store.torrents = torrents
            store.connectionState = .requiresAction(.unauthorized)
            store.isError = true
            store.debugBrief = "Unable to connect"
            store.debugMessage = "The preview server rejected the connection."
        }

        return store
    }
}

#endif
