import SwiftData
import SwiftUI

/// Dependencies are chosen before any live persistence or networking is created.
@MainActor
final class AppEnvironment {
    let container: ModelContainer
    let userDefaults: UserDefaults
    let hostRepository: any HostPersisting
    let store: TransmissionStore
    let themeManager: ThemeManager
    let allowsExternalServices: Bool
    let serverServices: ServerServices
    let presentationDate: Date?

    #if BITDREAM_SAMPLE_SUPPORT
    let demoSession: DemoSession?
    let screenshotConfiguration: ScreenshotConfiguration?
    #endif

    init(
        processEnvironment: [String: String] = ProcessInfo.processInfo.environment,
        demoUserDefaults: UserDefaults? = nil
    ) {
        #if BITDREAM_SAMPLE_SUPPORT
        let capture: ScreenshotConfiguration?
        do {
            capture = try ScreenshotConfiguration.fromProcess(environment: processEnvironment)
        } catch {
            preconditionFailure("Invalid launch configuration: \(error)")
        }
        screenshotConfiguration = capture
        if AppIdentity.isDevelopment, processEnvironment["BITDREAM_DEMO"] == "1" {
            let fixedDate = capture?.referenceDate
            let session = DemoSession(
                userDefaults: capture?.makeUserDefaults() ?? demoUserDefaults,
                automaticallyRetriesConnection: capture == nil,
                wallTime: { fixedDate ?? Date() }
            )
            demoSession = session
            container = session.container
            userDefaults = session.userDefaults
            hostRepository = session.repository
            store = session.store
            themeManager = ThemeManager(userDefaults: session.userDefaults)
            allowsExternalServices = false
            serverServices = session.serverServices
            presentationDate = fixedDate
            return
        }
        demoSession = nil
        #endif
        let persistence = PersistenceController.shared
        container = persistence.container
        userDefaults = .standard
        userDefaults.registerViewStateDefaults()
        hostRepository = HostRepository.shared
        store = TransmissionStore()
        themeManager = .shared
        allowsExternalServices = !persistence.isInMemory
        serverServices = .live
        presentationDate = nil
    }

    var isDemo: Bool {
        #if BITDREAM_SAMPLE_SUPPORT
        return demoSession != nil
        #else
        return false
        #endif
    }

    var mainWindowID: String {
        if screenshotWindowSize != nil { return "screenshot-main" }
        return isDemo ? "demo-main" : "main"
    }

    var screenshotWindowSize: CGSize? {
        #if BITDREAM_SAMPLE_SUPPORT
        return screenshotConfiguration?.windowSize
        #else
        return nil
        #endif
    }

    var screenshotDynamicTypeSize: DynamicTypeSize? {
        #if BITDREAM_SAMPLE_SUPPORT
        return screenshotConfiguration?.dynamicTypeSize
        #else
        return nil
        #endif
    }

    func start() async {
        #if BITDREAM_SAMPLE_SUPPORT
        if let demoSession {
            demoSession.start()
            return
        }
        #endif
        guard allowsExternalServices else { return }
        await hostRepository.bootstrap()
        ensureStartupConnectionBehaviorApplied(store: store, modelContext: container.mainContext, userDefaults: userDefaults)
    }
}

struct ServerServices: Sendable {
    var testConnection: @Sendable (TransmissionConnectionDescriptor) async throws -> TransmissionSessionResponseArguments
    var readPassword: @MainActor @Sendable (Host) -> String
    var allowsTailscale: Bool

    static let live = Self(
        testConnection: { try await ServerConnectionTester.test($0) },
        readPassword: { host in
            guard let key = KeychainService.credentialKeyIfPresent(for: host) else { return "" }
            return KeychainService.readPassword(credentialKey: key)
        },
        allowsTailscale: true
    )
}

extension EnvironmentValues {
    @Entry var serverServices: ServerServices = .live
    @Entry var presentationDate: Date?
}

struct AppEnvironmentModifier: ViewModifier {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let environment: AppEnvironment

    func body(content: Content) -> some View {
        content
            .modelContainer(environment.container)
            .defaultAppStorage(environment.userDefaults)
            .environment(\.appUserDefaults, environment.userDefaults)
            .environment(\.hostRepositoryProvider, HostRepositoryProvider(resolve: { environment.hostRepository }))
            .environment(\.serverServices, environment.serverServices)
            .environment(\.presentationDate, environment.presentationDate)
            .environment(\.dynamicTypeSize, environment.screenshotDynamicTypeSize ?? dynamicTypeSize)
    }
}
