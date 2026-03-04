import SwiftUI
import UserNotifications
import Foundation
import Combine
import UniformTypeIdentifiers
import SwiftData

@main
struct BitDreamApp: App {
    let persistenceController = PersistenceController.shared
    private let swiftDataSchemaVersion = "swiftdata_v1"

    // Create a shared store instance that will be used by both the main app and settings
    @StateObject private var store = Store()
    @StateObject private var themeManager = ThemeManager.shared
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppFileOpenDelegate.self) private var appFileOpenDelegate
    @StateObject private var menuBarStatusItemController = MenuBarStatusItemBridge()
    @StateObject private var appUpdater = AppUpdater()
    #endif

    // HUD state for macOS appearance toggle feedback
    @State private var showAppearanceHUD: Bool = false
    @State private var appearanceHUDText: String = ""
    @State private var hideHUDWork: DispatchWorkItem?
    @AppStorage(UserDefaultsKeys.menuBarTransferWidgetEnabled) private var menuBarTransferWidgetEnabled: Bool = AppDefaults.menuBarTransferWidgetEnabled

    #if os(iOS)
    @Environment(\.scenePhase) private var scenePhase
    #endif

    init() {
        performPersistenceFreshStartCutoverIfNeeded(targetVersion: swiftDataSchemaVersion)

        // Register default values for view state
        UserDefaults.registerViewStateDefaults()

        // Register additional defaults
        UserDefaults.standard.register(defaults: [
            "sortBySelection": "nameAsc", // Default sort by name ascending
            "themeModeKey": ThemeMode.system.rawValue // Default theme mode
        ])

        // Request permission to use badges on macOS
        #if os(macOS)
        UNUserNotificationCenter.current().requestAuthorization(options: [.badge]) { granted, error in
            if let error = error {
                print("Error requesting notification authorization: \(error)")
            }
        }
        #endif

        #if os(iOS)
        BackgroundRefreshManager.register()
        #endif

        #if os(macOS)
        BackgroundActivityScheduler.register()
        #endif
    }

    #if os(macOS)
    private func syncMenuBarStatusItem(isEnabled: Bool? = nil) {
        menuBarStatusItemController.configure(
            isEnabled: isEnabled ?? menuBarTransferWidgetEnabled,
            store: store
        )
    }
    #endif

    var body: some Scene {
        #if os(macOS)
        Window("BitDream", id: "main") {
            ContentView()
                .environmentObject(store) // Pass the shared store to the ContentView
                .accentColor(themeManager.accentColor) // Apply the accent color to the entire app
                .environmentObject(themeManager) // Pass the ThemeManager to all views
                .immediateTheme(manager: themeManager)
                .onOpenURL { url in
                    // Handle bitdream://server?id=<serverID>
                    guard url.scheme == DeepLinkConfig.scheme else { return }
                    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                    let serverID = components?.queryItems?.first(where: { $0.name == DeepLinkConfig.QueryKey.id })?.value
                    guard let serverID, !serverID.isEmpty else { return }
                    let targetServerID = serverID
                    let descriptor = FetchDescriptor<Host>(
                        predicate: #Predicate<Host> { host in
                            host.serverID == targetServerID
                        }
                    )
                    let context = persistenceController.container.mainContext
                    if let host = try? context.fetch(descriptor).first {
                        store.setHost(host: host)
                    }
                }
                .task {
                    await HostRepository.shared.bootstrap()
                    appFileOpenDelegate.configure(with: store)
                    ensureStartupConnectionBehaviorApplied(store: store, modelContext: persistenceController.container.mainContext)
                    syncMenuBarStatusItem()
                    appUpdater.start()
                }
                .onChange(of: menuBarTransferWidgetEnabled) { _, isEnabled in
                    syncMenuBarStatusItem(isEnabled: isEnabled)
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    BackgroundActivityScheduler.unregister()
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
                            DispatchQueue.main.async {
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
                        }
                    case .failure(let error):
                        DispatchQueue.main.async {
                            store.globalAlertTitle = "Error"
                            store.globalAlertMessage = "File import failed\n\n\(error.localizedDescription)"
                            store.showGlobalAlert = true
                        }
                    }
                }
                #if os(macOS)
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
                                renameTorrentRoot(torrent: targetTorrent, to: newName, store: store) { error in
                                    DispatchQueue.main.async {
                                        if let error = error {
                                            store.globalAlertTitle = "Rename Error"
                                            store.globalAlertMessage = error
                                            store.showGlobalAlert = true
                                        } else {
                                            store.showGlobalRenameDialog = false
                                            store.globalRenameInput = ""
                                            store.globalRenameTargetId = nil
                                        }
                                    }
                                }
                            }
                        )
                        .frame(width: 420)
                        .padding()
                    }
                }
                #endif
        }
        .windowResizability(.contentSize)
        .commands {
            AppCommands(appUpdater: appUpdater)
            CommandGroup(replacing: .newItem) { }
            FileCommands(store: store)
            SearchCommands(store: store)
            ViewCommands(store: store)
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
        .modelContainer(persistenceController.container)
        WindowGroup("Connection Info", id: "connection-info") {
            macOSConnectionInfoView()
                .environmentObject(store)
                .accentColor(themeManager.accentColor)
                .environmentObject(themeManager)
                .immediateTheme(manager: themeManager)
                .frame(minWidth: 420, idealWidth: 460, maxWidth: 600, minHeight: 320, idealHeight: 360, maxHeight: 800)
        }
        .windowResizability(.contentSize)
        .modelContainer(persistenceController.container)

        WindowGroup("Statistics", id: "statistics") {
            macOSStatisticsView()
                .environmentObject(store)
                .accentColor(themeManager.accentColor)
                .environmentObject(themeManager)
                .immediateTheme(manager: themeManager)
                .frame(minWidth: 420, idealWidth: 460, maxWidth: 600, minHeight: 320, idealHeight: 360, maxHeight: 800)
        }
        .windowResizability(.contentSize)
        .modelContainer(persistenceController.container)

        // About window - Using WindowGroup to prevent automatic Window menu entry
        // This follows Apple's recommended pattern for auxiliary windows that shouldn't
        // appear in the Window menu, as About windows are not user-managed utility windows
        WindowGroup(id: "about") {
            macOSAboutView()
                .navigationTitle("About BitDream")  // Proper window title handling
                .environmentObject(themeManager)
                .immediateTheme(manager: themeManager)
                .frame(width: 320, height: 400)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .modelContainer(persistenceController.container)

        #else
        WindowGroup {
            ContentView()
                .environmentObject(store) // Pass the shared store to the ContentView
                .accentColor(themeManager.accentColor) // Apply the accent color to the entire app
                .environmentObject(themeManager) // Pass the ThemeManager to all views
                .immediateTheme(manager: themeManager)
                .task {
                    await HostRepository.shared.bootstrap()
                    ensureStartupConnectionBehaviorApplied(store: store, modelContext: persistenceController.container.mainContext)
                    BackgroundRefreshManager.schedule()
                }
                .onChange(of: scenePhase) { oldPhase, newPhase in
                    if newPhase == .background {
                        BackgroundRefreshManager.schedule()
                    }
                }
        }
        .modelContainer(persistenceController.container)
        #endif

        #if os(macOS)
        Settings {
            SettingsView(store: store) // Use the same store instance
                .frame(minWidth: 500, idealWidth: 550, maxWidth: 650)
                .environmentObject(appUpdater)
                .environmentObject(themeManager) // Pass the ThemeManager to the Settings view
                .immediateTheme(manager: themeManager)
        }
        #endif
    }
}

// TODO(swiftdata-cutover): Remove this function entirely after the migration
// window for pre-SwiftData installs has ended.
private func performPersistenceFreshStartCutoverIfNeeded(targetVersion: String) {
    let defaults = UserDefaults.standard
    let currentVersion = defaults.string(forKey: UserDefaultsKeys.persistenceSchemaVersion)
    guard currentVersion != targetVersion else { return }

    defaults.removeObject(forKey: UserDefaultsKeys.selectedHost)
    // TODO(swiftdata-cutover): Remove this one-time widget snapshot cleanup
    // once legacy pre-SwiftData upgrade paths are no longer supported.
    AppGroup.Files.removeWidgetSnapshotFiles()
    removeLegacyCoreDataStoreFiles()
    defaults.set(targetVersion, forKey: UserDefaultsKeys.persistenceSchemaVersion)
}

// TODO(swiftdata-cutover): Remove this helper when
// `performPersistenceFreshStartCutoverIfNeeded` is deleted.
private func removeLegacyCoreDataStoreFiles() {
    guard let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
        return
    }

    let legacyFilenames = [
        "BitDream.sqlite",
        "BitDream.sqlite-shm",
        "BitDream.sqlite-wal"
    ]

    legacyFilenames.forEach { filename in
        let url = appSupportURL.appendingPathComponent(filename, isDirectory: false)
        try? FileManager.default.removeItem(at: url)
    }
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
