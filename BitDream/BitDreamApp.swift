import SwiftUI
import UserNotifications
import Foundation
import Combine
import UniformTypeIdentifiers
import SwiftData

@main
struct BitDreamApp: App {
    private let appEnvironment: AppEnvironment

    // Create a shared store instance that will be used by both the main app and settings
    @StateObject private var store: TransmissionStore
    @StateObject private var themeManager: ThemeManager
    #if os(iOS)
    @StateObject private var appIconManager: AppIconManager
    #endif
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppFileOpenDelegate.self) private var appFileOpenDelegate
    @StateObject private var menuBarStatusItemController = MenuBarStatusItemBridge()
    @StateObject private var dockBadgeController = DockBadgeController()
    #if canImport(Sparkle)
    @StateObject private var appUpdater: AppUpdater
    #endif
    @StateObject private var serverEditingCoordinator = MacOSServerEditingCoordinator()
    #endif

    // HUD state for macOS appearance toggle feedback
    @State private var showAppearanceHUD: Bool = false
    @State private var appearanceHUDText: String = ""
    @State private var hideHUDWork: DispatchWorkItem?
    @AppStorage(UserDefaultsKeys.menuBarTransferWidgetEnabled) private var menuBarTransferWidgetEnabled: Bool = AppDefaults.menuBarTransferWidgetEnabled
    @AppStorage(UserDefaultsKeys.menuBarShowActiveCount) private var menuBarShowActiveCount: Bool = AppDefaults.menuBarShowActiveCount

    @Environment(\.scenePhase) private var scenePhase

    init() {
        let environment = AppEnvironment()
        appEnvironment = environment
        _store = StateObject(wrappedValue: environment.store)
        _themeManager = StateObject(wrappedValue: environment.themeManager)
        _menuBarTransferWidgetEnabled = AppStorage(wrappedValue: AppDefaults.menuBarTransferWidgetEnabled,
            UserDefaultsKeys.menuBarTransferWidgetEnabled, store: environment.userDefaults)
        _menuBarShowActiveCount = AppStorage(wrappedValue: AppDefaults.menuBarShowActiveCount,
            UserDefaultsKeys.menuBarShowActiveCount, store: environment.userDefaults)
        #if os(iOS)
        _appIconManager = StateObject(wrappedValue: environment.allowsExternalServices ? .shared : .inert())
        #endif
        #if os(macOS) && canImport(Sparkle)
        _appUpdater = StateObject(wrappedValue: AppUpdater(updatesEnabled: environment.allowsExternalServices))
        #endif
        // Register default values for view state
        environment.userDefaults.registerViewStateDefaults()

        // Register additional defaults
        environment.userDefaults.register(defaults: [
            "sortBySelection": "nameAsc", // Default sort by name ascending
            "themeModeKey": ThemeMode.system.rawValue // Default theme mode
        ])

        // The test host must not request permissions or schedule real server work.
        guard appEnvironment.allowsExternalServices else { return }

        // Request permission to use badges on macOS
        #if os(macOS)
        UNUserNotificationCenter.current().requestAuthorization(options: [.badge]) { _, _ in }
        #endif

        #if os(iOS)
        BackgroundRefreshManager.register()
        #endif

        #if os(macOS)
        Task { @MainActor in
            BackgroundActivityScheduler.register()
        }
        #endif
    }

    var body: some Scene {
        #if os(macOS)
        macOSScenes
        #else
        iOSScene
        #endif
    }
}

private extension BitDreamApp {
    func openWidgetURL(_ url: URL) {
        guard let serverID = DeepLinkBuilder.serverID(from: url) else { return }
        let descriptor = FetchDescriptor<Host>(
            predicate: #Predicate<Host> { $0.serverID == serverID }
        )
        let context = appEnvironment.container.mainContext
        if let host = try? context.fetch(descriptor).first {
            store.setHost(host: host)
        }
    }

    #if os(macOS)
    func syncMenuBarStatusItem(isEnabled: Bool? = nil) {
        guard appEnvironment.allowsExternalServices else { return }
        menuBarStatusItemController.configure(
            isEnabled: isEnabled ?? menuBarTransferWidgetEnabled,
            store: store
        )
    }

    @SceneBuilder
    var macOSScenes: some Scene {
        mainWindowScene
        manageServersScene
        connectionInfoScene
        statisticsScene
        aboutScene
        settingsScene
    }

    var mainWindowScene: some Scene {
        Window(AppIdentity.displayName, id: appEnvironment.mainWindowID) {
            ContentView()
                .frame(width: appEnvironment.screenshotWindowSize?.width, height: appEnvironment.screenshotWindowSize?.height)
                .environmentObject(store) // Pass the shared store to the ContentView
                .environmentObject(serverEditingCoordinator)
                .accentColor(themeManager.accentColor) // Apply the accent color to the entire app
                .environmentObject(themeManager) // Pass the ThemeManager to all views
                .immediateTheme(manager: themeManager)
                .modifier(AppEnvironmentModifier(environment: appEnvironment))
                .onOpenURL(perform: openWidgetURL)
                .task {
                    await appEnvironment.start()
                    guard appEnvironment.allowsExternalServices else { return }
                    appFileOpenDelegate.configure(with: store)
                    syncMenuBarStatusItem()
                    dockBadgeController.configure(store: store)
                    #if canImport(Sparkle)
                    appUpdater.start()
                    #endif
                }
                .onChange(of: scenePhase) { _, phase in
                    if appEnvironment.allowsExternalServices, phase == .active, store.host?.connectionRoute == "tailscale" {
                        store.reconnect()
                    }
                }
                .onChange(of: menuBarTransferWidgetEnabled) { _, isEnabled in
                    syncMenuBarStatusItem(isEnabled: isEnabled)
                }
                .onChange(of: menuBarShowActiveCount) { _, _ in
                    syncMenuBarStatusItem()
                }
                .onReceive(
                    NotificationCenter.default
                        .publisher(for: NSApplication.willTerminateNotification)
                        .receive(on: RunLoop.main)
                ) { _ in
                    if appEnvironment.allowsExternalServices { BackgroundActivityScheduler.unregister() }
                }
                .overlay(alignment: .center) {
                    if showAppearanceHUD {
                        AppearanceHUDView(text: appearanceHUDText)
                            .allowsHitTesting(false)
                    }
                }
                .animation(.easeOut(duration: 0.25), value: showAppearanceHUD)
                .alert(store.globalAlertTitle, isPresented: $store.showGlobalAlert) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(store.globalAlertMessage)
                }
                .fileImporter(
                    isPresented: $store.presentGlobalTorrentFileImporter,
                    allowedContentTypes: [UTType.torrent],
                    allowsMultipleSelection: true
                ) { result in
                    switch result {
                    case .success(let urls):
                        guard store.host != nil else {
                            presentAddTorrentStoreError(
                                detail: addTorrentNoServerConfiguredMessage,
                                store: store
                            )
                            return
                        }
                        var failures: [(String, String)] = []
                        for url in urls {
                            do {
                                let data = try Data(contentsOf: url)
                                addTorrentFromFileData(data, store: store)
                            } catch {
                                failures.append((url.lastPathComponent, error.localizedDescription))
                            }
                        }
                        if !failures.isEmpty {
                            if failures.count == 1, let first = failures.first {
                                store.globalAlertTitle = "Error"
                                store.globalAlertMessage = "Failed to open '\(first.0)'\n\n\(first.1)"
                            } else {
                                let list = failures.prefix(10).map { "- \($0.0): \($0.1)" }.joined(separator: "\n")
                                let remainder = failures.count - min(failures.count, 10)
                                let suffix = remainder > 0 ? "\n...and \(remainder) more" : ""
                                store.globalAlertTitle = "Error"
                                store.globalAlertMessage = "Failed to open \(failures.count) torrent files\n\n\(list)\(suffix)"
                            }
                            store.showGlobalAlert = true
                        }
                    case .failure(let error):
                        store.globalAlertTitle = "Error"
                        store.globalAlertMessage = "File import failed\n\n\(error.localizedDescription)"
                        store.showGlobalAlert = true
                    }
                }
                .sheet(isPresented: $store.showGlobalRenameDialog) {
                    // Resolve target torrent using the stored ID
                    if let targetId = store.globalRenameTargetId,
                       let targetTorrent = store.torrents.first(where: { $0.id == targetId }) {
                        RenameSheetView(
                            title: "Rename Torrent",
                            name: $store.globalRenameInput,
                            currentName: targetTorrent.name,
                            onCancel: {
                                store.showGlobalRenameDialog = false
                                store.globalRenameInput = ""
                                store.globalRenameTargetId = nil
                            },
                            onSave: { newName in
                                if let validation = validateNewName(newName, current: targetTorrent.name) {
                                    store.globalAlertTitle = "Rename Error"
                                    store.globalAlertMessage = validation
                                    store.showGlobalAlert = true
                                    return
                                }
                                performTransmissionAction(
                                    operation: { try await store.renameTorrentRoot(targetTorrent, to: newName) },
                                    onSuccess: { (_: TorrentRenameResponseArgs) in
                                        store.showGlobalRenameDialog = false
                                        store.globalRenameInput = ""
                                        store.globalRenameTargetId = nil
                                    },
                                    onError: { message in
                                        store.globalAlertTitle = "Rename Error"
                                        store.globalAlertMessage = message
                                        store.showGlobalAlert = true
                                    }
                                )
                            }
                        )
                        .frame(width: 420)
                        .padding()
                    }
                }
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .defaultLaunchBehavior(appEnvironment.isDemo ? .presented : .automatic)
        .commands {
            #if canImport(Sparkle)
            AppCommands(appUpdater: appUpdater)
            #else
            AppCommands()
            #endif
            CommandGroup(replacing: .newItem) { }
            FileCommands(store: store)
            SearchCommands(store: store)
            ViewCommands(store: store, userDefaults: appEnvironment.userDefaults)
            TorrentCommands(store: store)
            InspectorCommands(store: store)
            SidebarCommands()
            AppearanceCommands(
                themeManager: themeManager,
                showAppearanceHUD: $showAppearanceHUD,
                appearanceHUDText: $appearanceHUDText,
                hideHUDWork: $hideHUDWork
            )
        }
        .modelContainer(appEnvironment.container)
    }

    var manageServersScene: some Scene {
        Window("Manage Servers", id: "manage-servers") {
            macOSManageServersWindow()
                .environmentObject(store)
                .environmentObject(serverEditingCoordinator)
                .tint(themeManager.accentColor)
                .environmentObject(themeManager)
                .immediateTheme(manager: themeManager)
                .modifier(AppEnvironmentModifier(environment: appEnvironment))
        }
        .defaultSize(width: 760, height: 480)
        .windowResizability(.contentMinSize)
        .modelContainer(appEnvironment.container)
    }

    var connectionInfoScene: some Scene {
        WindowGroup("Connection Info", id: "connection-info") {
            macOSConnectionInfoView()
                .environmentObject(store)
                .accentColor(themeManager.accentColor)
                .environmentObject(themeManager)
                .immediateTheme(manager: themeManager)
                .modifier(AppEnvironmentModifier(environment: appEnvironment))
                .frame(minWidth: 420, idealWidth: 460, maxWidth: 600, minHeight: 320, idealHeight: 360, maxHeight: 800)
        }
        .windowResizability(.contentSize)
        .modelContainer(appEnvironment.container)
    }

    var statisticsScene: some Scene {
        WindowGroup("Statistics", id: "statistics") {
            macOSStatisticsView()
                .environmentObject(store)
                .accentColor(themeManager.accentColor)
                .environmentObject(themeManager)
                .immediateTheme(manager: themeManager)
                .modifier(AppEnvironmentModifier(environment: appEnvironment))
                .frame(minWidth: 420, idealWidth: 460, maxWidth: 600, minHeight: 320, idealHeight: 720, maxHeight: 800)
        }
        .windowResizability(.contentSize)
        .modelContainer(appEnvironment.container)
    }

    var aboutScene: some Scene {
        // About window - Using WindowGroup to prevent automatic Window menu entry
        // This follows Apple's recommended pattern for auxiliary windows that shouldn't
        // appear in the Window menu, as About windows are not user-managed utility windows
        WindowGroup(id: "about") {
            macOSAboutView()
                .navigationTitle("About \(AppIdentity.displayName)")  // Proper window title handling
                .environmentObject(themeManager)
                .immediateTheme(manager: themeManager)
                .modifier(AppEnvironmentModifier(environment: appEnvironment))
                .frame(width: 320)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .modelContainer(appEnvironment.container)
    }

    var settingsScene: some Scene {
        Settings {
            Group {
                #if canImport(Sparkle)
                SettingsView(store: store)
                    .environmentObject(appUpdater)
                #else
                SettingsView(store: store)
                #endif
            }
                .frame(minWidth: 500, idealWidth: 550, maxWidth: 650, minHeight: 650)
                .environmentObject(themeManager) // Pass the ThemeManager to the Settings view
                .immediateTheme(manager: themeManager)
                .modifier(AppEnvironmentModifier(environment: appEnvironment))
        }
    }
    #else
    var iOSScene: some Scene {
        WindowGroup {
            iOSHapticFeedbackHost {
                ContentView()
                    .environmentObject(store) // Pass the shared store to the ContentView
                    .accentColor(themeManager.accentColor) // Apply the accent color to the entire app
                    .environmentObject(themeManager) // Pass the ThemeManager to all views
                    .environmentObject(appIconManager)
                    .onOpenURL(perform: openWidgetURL)
                    .immediateTheme(manager: themeManager)
                    .task {
                        await appEnvironment.start()
                        guard appEnvironment.allowsExternalServices else { return }
                        BackgroundRefreshManager.schedule()
                    }
                    .onChange(of: scenePhase) { _, newPhase in
                        guard appEnvironment.allowsExternalServices else { return }
                        if newPhase == .active, store.host?.connectionRoute == "tailscale" {
                            store.reconnect()
                        }
                        if newPhase == .background {
                            BackgroundRefreshManager.schedule()
                        }
                    }
            }
            .modifier(AppEnvironmentModifier(environment: appEnvironment))
        }
        .modelContainer(appEnvironment.container)
    }
    #endif
}

#if os(macOS)
private struct AppearanceHUDView: View {
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "circle.lefthalf.filled")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        )
    }
}
#endif

#if os(macOS) && DEBUG
#Preview("Appearance HUD", traits: .sizeThatFitsLayout) {
    AppearanceHUDView(text: "Dark Appearance")
        .padding()
}
#endif
