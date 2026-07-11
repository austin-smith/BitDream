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
    let themeManager: ThemeManager
    let userDefaults: UserDefaults
    #if os(iOS)
    let appIconManager: AppIconManager
    #endif
    #if os(macOS)
    let appUpdater: AppUpdater
    #endif

    init(scenario: PreviewScenario = .connected) {
        let suiteName = "BitDream.Preview.\(UUID().uuidString)"
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Unable to create isolated preview preferences.")
        }
        let hosts = PreviewFixtures.makeHosts()
        self.userDefaults = userDefaults
        self.hosts = hosts
        self.container = PreviewFixtures.makeModelContainer(hosts: hosts)
        self.hostRepository = PreviewHostRepository(modelContext: container.mainContext)
        self.store = PreviewFixtures.makeStore(
            scenario: scenario,
            selectedHost: hosts.first,
            userDefaults: userDefaults
        )
        self.themeManager = ThemeManager(userDefaults: userDefaults)
        #if os(iOS)
        self.appIconManager = AppIconManager.inert()
        #endif
        #if os(macOS)
        self.appUpdater = AppUpdater(updatesEnabled: false)
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
    }

    @ViewBuilder
    private var configuredContent: some View {
        #if os(macOS)
        content(previewEnvironment)
            .environmentObject(previewEnvironment.appUpdater)
        #elseif os(iOS)
        content(previewEnvironment)
            .environmentObject(previewEnvironment.appIconManager)
        #else
        content(previewEnvironment)
        #endif
    }
}

@MainActor
private final class PreviewHostRepository: HostPersisting {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func bootstrap() async {}

    func create(draft: HostDraft) async throws -> Host {
        let host = Host(
            isDefault: draft.isDefault,
            isSSL: draft.isSSL,
            name: draft.name,
            port: Int16(draft.port),
            server: draft.server,
            username: draft.username
        )
        if draft.isDefault {
            try clearDefaults(except: nil)
        }
        modelContext.insert(host)
        try modelContext.save()
        return host
    }

    func update(serverID: String, draft: HostDraft) async throws -> Host {
        guard let host = try fetchHost(serverID: serverID) else {
            throw HostPersistenceError.notFound(serverID)
        }
        if draft.isDefault {
            try clearDefaults(except: serverID)
        }
        host.name = draft.name
        host.server = draft.server
        host.port = Int16(draft.port)
        host.username = draft.username
        host.isSSL = draft.isSSL
        host.isDefault = draft.isDefault
        try modelContext.save()
        return host
    }

    func delete(serverID: String) async throws {
        guard let host = try fetchHost(serverID: serverID) else {
            throw HostPersistenceError.notFound(serverID)
        }
        modelContext.delete(host)
        try modelContext.save()
    }

    func setDefault(serverID: String) async throws {
        guard try fetchHost(serverID: serverID) != nil else {
            throw HostPersistenceError.notFound(serverID)
        }
        try clearDefaults(except: serverID)
        try modelContext.save()
    }

    func persistVersionIfNeeded(serverID: String, version: String) async {
        guard let host = try? fetchHost(serverID: serverID), host.version != version else { return }
        host.version = version
        try? modelContext.save()
    }

    func syncCatalog() async {}

    private func fetchHost(serverID: String) throws -> Host? {
        let descriptor = FetchDescriptor<Host>(
            predicate: #Predicate<Host> { $0.serverID == serverID }
        )
        return try modelContext.fetch(descriptor).first
    }

    private func clearDefaults(except serverID: String?) throws {
        let hosts = try modelContext.fetch(FetchDescriptor<Host>())
        for host in hosts {
            host.isDefault = host.serverID == serverID
        }
    }
}

@MainActor
enum PreviewFixtures {
    static let referenceDate = Date(timeIntervalSince1970: 1_735_689_600)

    static func makeHosts() -> [Host] {
        [
            Host(
                serverID: "preview-home",
                isDefault: true,
                isSSL: true,
                name: "Home Server",
                port: 9091,
                server: "transmission.example.com",
                username: "preview",
                version: "4.0.6"
            ),
            Host(
                serverID: "preview-remote",
                name: "Remote Seedbox",
                port: 9091,
                server: "seedbox.example.com",
                username: "preview",
                version: "4.0.6"
            )
        ]
    }

    static func makeModelContainer(hosts: [Host] = makeHosts()) -> ModelContainer {
        let schema = Schema([Host.self])
        let configuration = ModelConfiguration(
            "bitdream.preview.hosts",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )

        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            hosts.forEach(container.mainContext.insert)
            try container.mainContext.save()
            return container
        } catch {
            preconditionFailure("Unable to create the preview model container: \(error)")
        }
    }

    static func makeStore(
        scenario: PreviewScenario = .connected,
        selectedHost: Host? = makeHosts().first,
        userDefaults: UserDefaults = .standard
    ) -> TransmissionStore {
        let store = TransmissionStore(
            resolveConnection: { _ in
                throw TransmissionError.transport(
                    underlyingDescription: "Networking is disabled in previews."
                )
            },
            snapshotWriter: WidgetSnapshotWriter(
                writeServerIndex: { _ in },
                writeSessionSnapshot: { _, _, _, _, _ in },
                reloadTimelines: {}
            ),
            monotonicTime: { 0 },
            userDefaults: userDefaults,
            automaticallyRetriesConnection: false,
            updateBackgroundActivityInterval: { _ in },
            persistVersion: { _, _ in }
        )

        switch scenario {
        case .empty:
            break
        case .connected:
            store.host = selectedHost
            store.torrents = torrents
            store.sessionStats = sessionStats
            store.sessionConfiguration = sessionConfiguration
            store.defaultDownloadDir = "/Volumes/Downloads"
            store.connectionStatus = .connected
            store.lastRefreshAt = referenceDate
        case .reconnecting:
            store.host = selectedHost
            store.torrents = torrents
            store.sessionStats = sessionStats
            store.connectionStatus = .reconnecting
            store.lastErrorMessage = "The server is temporarily unavailable."
            store.nextRetryAt = referenceDate.addingTimeInterval(15)
        case .error:
            store.host = selectedHost
            store.torrents = torrents
            store.connectionStatus = .reconnecting
            store.isError = true
            store.debugBrief = "Unable to connect"
            store.debugMessage = "The preview server rejected the connection."
            store.lastErrorMessage = store.debugMessage
        }

        return store
    }
}

@MainActor
extension PreviewFixtures {
    static let torrents: [Torrent] = [
        torrent(
            id: 1,
            name: "Ubuntu 26.04 Desktop",
            status: .downloading,
            percentDone: 0.64,
            labels: ["Linux", "ISO"],
            rateDownload: 18_400_000,
            rateUpload: 420_000,
            peersConnected: 24,
            eta: 1_245
        ),
        torrent(
            id: 2,
            name: "Big Buck Bunny",
            status: .seeding,
            percentDone: 1,
            labels: ["Movies"],
            rateUpload: 5_200_000,
            peersConnected: 8,
            uploadRatio: 2.34
        ),
        torrent(
            id: 3,
            name: "Public Domain Audiobooks Collection",
            status: .stopped,
            percentDone: 0.27,
            labels: [],
            isStalled: false
        ),
        torrent(
            id: 4,
            name: "Open Source Archive",
            status: .downloading,
            percentDone: 0.81,
            labels: ["Archive", "Long-term storage"],
            isStalled: true,
            error: TorrentError.trackerWarning.rawValue,
            errorString: "Tracker has not responded yet"
        ),
        torrent(
            id: 5,
            name: "Completed Sample",
            status: .stopped,
            percentDone: 1,
            labels: ["Complete"],
            uploadRatio: 1.1
        )
    ]

    static func torrent(
        id: Int,
        name: String,
        status: TorrentStatus,
        percentDone: Double,
        labels: [String],
        rateDownload: Int64 = 0,
        rateUpload: Int64 = 0,
        peersConnected: Int = 0,
        eta: Int = -1,
        isStalled: Bool = false,
        error: Int = TorrentError.none.rawValue,
        errorString: String = "",
        uploadRatio: Double = 0.42
    ) -> Torrent {
        let totalSize: Int64 = 8_000_000_000
        let downloaded = Int64(Double(totalSize) * percentDone)
        return Torrent(
            activityDate: Int(referenceDate.timeIntervalSince1970),
            addedDate: Int(referenceDate.addingTimeInterval(-86_400).timeIntervalSince1970),
            desiredAvailable: totalSize - downloaded,
            error: error,
            errorString: errorString,
            eta: eta,
            haveUnchecked: 0,
            haveValid: downloaded,
            id: id,
            isFinished: percentDone == 1,
            isStalled: isStalled,
            labels: labels,
            leftUntilDone: totalSize - downloaded,
            magnetLink: "magnet:?xt=urn:btih:preview-\(id)",
            metadataPercentComplete: 1,
            name: name,
            peersConnected: peersConnected,
            peersGettingFromUs: status == .seeding ? peersConnected : 0,
            peersSendingToUs: status == .downloading ? peersConnected : 0,
            percentDone: percentDone,
            primaryMimeType: "application/octet-stream",
            downloadDir: "/Volumes/Downloads",
            queuePosition: id - 1,
            rateDownload: rateDownload,
            rateUpload: rateUpload,
            sizeWhenDone: totalSize,
            status: status.rawValue,
            totalSize: totalSize,
            uploadRatioRaw: uploadRatio,
            uploadedEver: Int64(Double(totalSize) * uploadRatio),
            downloadedEver: downloaded
        )
    }

    static let sessionStats = SessionStats(
        activeTorrentCount: 3,
        downloadSpeed: 18_400_000,
        pausedTorrentCount: 1,
        torrentCount: torrents.count,
        uploadSpeed: 5_620_000,
        cumulativeStats: TransmissionCumulativeStats(
            downloadedBytes: 4_800_000_000_000,
            filesAdded: 412,
            secondsActive: 31_536_000,
            sessionCount: 86,
            uploadedBytes: 7_200_000_000_000
        ),
        currentStats: TransmissionCumulativeStats(
            downloadedBytes: 48_000_000_000,
            filesAdded: 8,
            secondsActive: 86_400,
            sessionCount: 1,
            uploadedBytes: 72_000_000_000
        )
    )

    static let files: [TorrentFile] = [
        TorrentFile(bytesCompleted: 3_200_000_000, length: 5_000_000_000, name: "Ubuntu 26.04/ubuntu-26.04.iso"),
        TorrentFile(bytesCompleted: 2_048, length: 2_048, name: "Ubuntu 26.04/README.txt"),
        TorrentFile(bytesCompleted: 0, length: 4_096, name: "Ubuntu 26.04/CHECKSUMS")
    ]

    static let fileStats: [TorrentFileStats] = [
        TorrentFileStats(bytesCompleted: 3_200_000_000, wanted: true, priority: FilePriority.high.rawValue),
        TorrentFileStats(bytesCompleted: 2_048, wanted: true, priority: FilePriority.normal.rawValue),
        TorrentFileStats(bytesCompleted: 0, wanted: false, priority: FilePriority.low.rawValue)
    ]

    static let peers: [Peer] = [
        Peer(
            address: "203.0.113.10",
            clientName: "Transmission 4.0.6",
            clientIsChoked: false,
            clientIsInterested: true,
            flagStr: "UTEP",
            isDownloadingFrom: true,
            isEncrypted: true,
            isIncoming: false,
            isUploadingTo: false,
            isUTP: true,
            peerIsChoked: false,
            peerIsInterested: true,
            port: 51_413,
            progress: 0.72,
            rateToClient: 2_400_000,
            rateToPeer: 120_000
        ),
        Peer(
            address: "2001:db8::42",
            clientName: "qBittorrent 5.0",
            clientIsChoked: false,
            clientIsInterested: false,
            flagStr: "DE",
            isDownloadingFrom: false,
            isEncrypted: true,
            isIncoming: true,
            isUploadingTo: true,
            isUTP: false,
            peerIsChoked: false,
            peerIsInterested: true,
            port: 68_81,
            progress: 1,
            rateToClient: 0,
            rateToPeer: 860_000
        )
    ]

    static let peersFrom = PeersFrom(
        fromCache: 1,
        fromDht: 8,
        fromIncoming: 2,
        fromLpd: 0,
        fromLtep: 1,
        fromPex: 12,
        fromTracker: 4
    )

    static let sessionConfiguration = TransmissionSessionResponseArguments(
        downloadDir: "/Volumes/Downloads",
        version: "4.0.6",
        speedLimitDown: 50_000,
        speedLimitDownEnabled: false,
        speedLimitUp: 10_000,
        speedLimitUpEnabled: true,
        altSpeedDown: 5_000,
        altSpeedUp: 1_000,
        altSpeedEnabled: false,
        altSpeedTimeBegin: 480,
        altSpeedTimeEnd: 1_020,
        altSpeedTimeEnabled: true,
        altSpeedTimeDay: 127,
        incompleteDir: "/Volumes/Downloads/Incomplete",
        incompleteDirEnabled: true,
        startAddedTorrents: true,
        trashOriginalTorrentFiles: false,
        renamePartialFiles: true,
        downloadQueueEnabled: true,
        downloadQueueSize: 5,
        seedQueueEnabled: true,
        seedQueueSize: 10,
        seedRatioLimited: true,
        seedRatioLimit: 2,
        idleSeedingLimit: 30,
        idleSeedingLimitEnabled: false,
        queueStalledEnabled: true,
        queueStalledMinutes: 30,
        peerPort: 51_413,
        peerPortRandomOnStart: false,
        portForwardingEnabled: true,
        dhtEnabled: true,
        pexEnabled: true,
        lpdEnabled: false,
        encryption: "preferred",
        utpEnabled: true,
        peerLimitGlobal: 200,
        peerLimitPerTorrent: 50,
        blocklistEnabled: true,
        blocklistSize: 124_806,
        blocklistUrl: "https://example.com/blocklist",
        defaultTrackers: ""
    )
}
#endif
