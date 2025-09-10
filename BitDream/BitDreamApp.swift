//
//  BitDreamApp.swift
//  BitDream
//
//  Created by Austin Smith on 12/29/22.
//

import SwiftUI
import UserNotifications
import CoreData
// Import Store from the main module
import Foundation
import Combine
import UniformTypeIdentifiers


// Search Commands for menu and keyboard shortcut
struct SearchCommands: Commands {
    @ObservedObject var store: Store
    
    var body: some Commands {
        CommandGroup(after: .textEditing) {
            Divider()
            Button(action: {
                store.shouldActivateSearch.toggle()
            }) {
                Label("Search Torrents", systemImage: "magnifyingglass")
            }
            .keyboardShortcut("f", modifiers: .command)
        }
    }
}

// File Commands for file-related actions
struct FileCommands: Commands {
    @ObservedObject var store: Store
    
    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button(action: {
                #if os(macOS)
                store.presentGlobalTorrentFileImporter = true
                #else
                store.isShowingAddAlert.toggle()
                #endif
            }) {
                Label("Add Torrent from File…", systemImage: "doc.badge.plus")
            }
            .keyboardShortcut("o", modifiers: .command)

            Button(action: {
                #if os(macOS)
                store.addTorrentInitialMode = .magnet
                #endif
                store.isShowingAddAlert.toggle()
            }) {
                Label("Add Torrent from Magnet Link…", systemImage: "link.badge.plus")
            }
            .keyboardShortcut("o", modifiers: [.option, .command])
            
            #if os(macOS)
            Divider()
            
            Button(action: {
                if let firstTorrent = store.selectedTorrents.first {
                    store.globalRenameInput = firstTorrent.name
                    store.globalRenameTargetId = firstTorrent.id
                    store.showGlobalRenameDialog = true
                }
            }) {
                Label("Rename…", systemImage: "pencil")
            }
            .disabled(store.selectedTorrents.count != 1)
            #endif
        }
    }
}

#if os(macOS)
// Torrent Commands for macOS torrent management
struct TorrentCommands: Commands {
    @ObservedObject var store: Store
    
    var body: some Commands {
        CommandMenu("Torrent") {
            // Selected torrent actions
            Button(action: {
                pauseSelectedTorrents()
            }) {
                Label("Pause Selected", systemImage: "pause")
            }
            .keyboardShortcut(".", modifiers: .command)
            .disabled(store.selectedTorrents.shouldDisablePause)
            
            Button(action: {
                resumeSelectedTorrents()
            }) {
                Label("Resume Selected", systemImage: "play")
            }
            .keyboardShortcut("/", modifiers: .command)
            .disabled(store.selectedTorrents.shouldDisableResume)
            
            Button(action: {
                resumeSelectedTorrentsNow()
            }) {
                Label("Resume Selected Now", systemImage: "play.fill")
            }
            .disabled(store.selectedTorrents.shouldDisableResume)
            
            Divider()
            
            // Remove action
            Button(action: {
                store.showingMenuRemoveConfirmation = true
            }) {
                Label("Remove…", systemImage: "trash")
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(store.selectedTorrents.isEmpty)
            
            Divider()
            
            // Queue movement actions
            Button(action: {
                moveSelectedTorrentsToFront()
            }) {
                Label("Move to Front of Queue", systemImage: "arrow.up.to.line")
            }
            .disabled(store.selectedTorrents.isEmpty)
            
            Button(action: {
                moveSelectedTorrentsUp()
            }) {
                Label("Move Up in Queue", systemImage: "arrow.up")
            }
            .disabled(store.selectedTorrents.isEmpty)
            
            Button(action: {
                moveSelectedTorrentsDown()
            }) {
                Label("Move Down in Queue", systemImage: "arrow.down")
            }
            .disabled(store.selectedTorrents.isEmpty)
            
            Button(action: {
                moveSelectedTorrentsToBack()
            }) {
                Label("Move to Back of Queue", systemImage: "arrow.down.to.line")
            }
            .disabled(store.selectedTorrents.isEmpty)
            
            Divider()
            
            // All torrents actions
            Button(action: {
                pauseAllTorrents()
            }) {
                Label("Pause All", systemImage: "pause.circle")
            }
            .keyboardShortcut(".", modifiers: [.option, .command])
            .disabled(store.torrents.isEmpty)
            
            Button(action: {
                resumeAllTorrents()
            }) {
                Label("Resume All", systemImage: "play.circle")
            }
            .keyboardShortcut("/", modifiers: [.option, .command])
            .disabled(store.torrents.isEmpty)
            
            Divider()
            
            // Ask for more peers action
            Button(action: {
                reannounceSelectedTorrents()
            }) {
                Label("Ask For More Peers", systemImage: "arrow.left.arrow.right")
            }
            .disabled(store.selectedTorrents.isEmpty)
            
            // Verify action
            Button(action: {
                verifySelectedTorrents()
            }) {
                Label("Verify Local Data", systemImage: "checkmark.arrow.trianglehead.counterclockwise")
            }
            .disabled(store.selectedTorrents.isEmpty)
        }
    }
    
    // MARK: - Action Implementations
    
    private func pauseSelectedTorrents() {
        let selected = Array(store.selectedTorrents)
        guard !selected.isEmpty else { return }
        
        let info = makeConfig(store: store)
        let ids = selected.map { $0.id }

        pauseTorrents(ids: ids, info: info) { response in
            handleTransmissionResponse(response,
                onSuccess: {},
                onError: { error in
                    DispatchQueue.main.async {
                        store.debugBrief = "Failed to pause torrents"
                        store.debugMessage = error
                        store.isError = true
                    }
                }
            )
        }
    }
    
    private func resumeSelectedTorrents() {
        let selected = Array(store.selectedTorrents)
        guard !selected.isEmpty else { return }
        
        let info = makeConfig(store: store)
        let ids = selected.map { $0.id }

        resumeTorrents(ids: ids, info: info) { response in
            handleTransmissionResponse(response,
                onSuccess: {},
                onError: { error in
                    DispatchQueue.main.async {
                        store.debugBrief = "Failed to resume torrents"
                        store.debugMessage = error
                        store.isError = true
                    }
                }
            )
        }
    }
    
    private func resumeSelectedTorrentsNow() {
        let selected = Array(store.selectedTorrents)
        guard !selected.isEmpty else { return }

        for torrent in selected {
            resumeTorrentNow(torrent: torrent, store: store) { response in
                handleTransmissionResponse(response,
                    onSuccess: {},
                    onError: { error in
                        DispatchQueue.main.async {
                            store.debugBrief = "Failed to resume torrents now"
                            store.debugMessage = error
                            store.isError = true
                        }
                    }
                )
            }
        }
    }
    
    private func pauseAllTorrents() {
        guard !store.torrents.isEmpty else { return }
        
        let info = makeConfig(store: store)
        
        playPauseAllTorrents(start: false, info: info) { response in
            handleTransmissionResponse(response,
                onSuccess: {},
                onError: { error in
                    DispatchQueue.main.async {
                        store.debugBrief = "Failed to pause all torrents"
                        store.debugMessage = error
                        store.isError = true
                    }
                }
            )
        }
    }
    
    private func resumeAllTorrents() {
        guard !store.torrents.isEmpty else { return }
        
        let info = makeConfig(store: store)
        
        playPauseAllTorrents(start: true, info: info) { response in
            handleTransmissionResponse(response,
                onSuccess: {},
                onError: { error in
                    DispatchQueue.main.async {
                        store.debugBrief = "Failed to resume all torrents"
                        store.debugMessage = error
                        store.isError = true
                    }
                }
            )
        }
    }
    
    private func reannounceSelectedTorrents() {
        let selected = Array(store.selectedTorrents)
        guard !selected.isEmpty else { return }
        
        for torrent in selected {
            reAnnounceToTrackers(torrent: torrent, store: store) { response in
                handleTransmissionResponse(response,
                    onSuccess: {},
                    onError: { error in
                        DispatchQueue.main.async {
                            store.debugBrief = "Failed to ask for more peers"
                            store.debugMessage = error
                            store.isError = true
                        }
                    }
                )
            }
        }
    }
    
    private func verifySelectedTorrents() {
        let selected = Array(store.selectedTorrents)
        guard !selected.isEmpty else { return }
        
        let info = makeConfig(store: store)
        
        for torrent in selected {
            verifyTorrent(torrent: torrent, config: info.config, auth: info.auth) { response in
                handleTransmissionResponse(response,
                    onSuccess: {},
                    onError: { error in
                        DispatchQueue.main.async {
                            store.debugBrief = "Failed to verify torrent"
                            store.debugMessage = error
                            store.isError = true
                        }
                    }
                )
            }
        }
    }
    
    // MARK: - Queue Movement Helper Functions
    
    private func moveSelectedTorrentsToFront() {
        let selectedIds = Array(store.selectedTorrents.map { $0.id })
        guard !selectedIds.isEmpty else { return }
        
        let info = makeConfig(store: store)
        queueMoveTop(ids: selectedIds, info: info) { response in
            handleTransmissionResponse(response,
                onSuccess: {},
                onError: { error in
                    DispatchQueue.main.async {
                        store.globalAlertTitle = "Queue Error"
                        store.globalAlertMessage = error
                        store.showGlobalAlert = true
                    }
                }
            )
        }
    }
    
    private func moveSelectedTorrentsUp() {
        let selectedIds = Array(store.selectedTorrents.map { $0.id })
        guard !selectedIds.isEmpty else { return }
        
        let info = makeConfig(store: store)
        queueMoveUp(ids: selectedIds, info: info) { response in
            handleTransmissionResponse(response,
                onSuccess: {},
                onError: { error in
                    DispatchQueue.main.async {
                        store.globalAlertTitle = "Queue Error"
                        store.globalAlertMessage = error
                        store.showGlobalAlert = true
                    }
                }
            )
        }
    }
    
    private func moveSelectedTorrentsDown() {
        let selectedIds = Array(store.selectedTorrents.map { $0.id })
        guard !selectedIds.isEmpty else { return }
        
        let info = makeConfig(store: store)
        queueMoveDown(ids: selectedIds, info: info) { response in
            handleTransmissionResponse(response,
                onSuccess: {},
                onError: { error in
                    DispatchQueue.main.async {
                        store.globalAlertTitle = "Queue Error"
                        store.globalAlertMessage = error
                        store.showGlobalAlert = true
                    }
                }
            )
        }
    }
    
    private func moveSelectedTorrentsToBack() {
        let selectedIds = Array(store.selectedTorrents.map { $0.id })
        guard !selectedIds.isEmpty else { return }
        
        let info = makeConfig(store: store)
        queueMoveBottom(ids: selectedIds, info: info) { response in
            handleTransmissionResponse(response,
                onSuccess: {},
                onError: { error in
                    DispatchQueue.main.async {
                        store.globalAlertTitle = "Queue Error"
                        store.globalAlertMessage = error
                        store.showGlobalAlert = true
                    }
                }
            )
        }
    }
}
#endif

// View Commands for view-related toggles
struct ViewCommands: Commands {
    @AppStorage("torrentListCompactMode") private var isCompactMode: Bool = false
    @AppStorage("showContentTypeIcons") private var showContentTypeIcons: Bool = true
    
    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Divider()
            
            Toggle(isOn: $isCompactMode) {
                Label("Compact View", systemImage: "list.bullet")
            }
            
            Toggle(isOn: $showContentTypeIcons) {
                Label("Show File Type Icons", systemImage: "doc.richtext")
            }
        }
    }
}

#if os(macOS)
// App Commands for About and app-related actions
struct AppCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    
    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button(action: {
                openWindow(id: "about")
            }) {
                Label("About BitDream", systemImage: "info.circle")
            }
        }
    }
}
#endif

@main
struct BitDreamApp: App {
    let persistenceController = PersistenceController.shared
    
    // Create a shared store instance that will be used by both the main app and settings
    @StateObject private var store = Store()
    @StateObject private var themeManager = ThemeManager.shared
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppFileOpenDelegate.self) private var appFileOpenDelegate
    #endif
    
    // HUD state for macOS appearance toggle feedback
    @State private var showAppearanceHUD: Bool = false
    @State private var appearanceHUDText: String = ""
    @State private var hideHUDWork: DispatchWorkItem?
    
    init() {
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
    }

    var body: some Scene {
        #if os(macOS)
        Window("BitDream", id: "main") {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(store) // Pass the shared store to the ContentView
                .accentColor(themeManager.accentColor) // Apply the accent color to the entire app
                .environmentObject(themeManager) // Pass the ThemeManager to all views
                .immediateTheme(manager: themeManager)
                .onAppear {
                    // Bind delegate to Store and auto-flush when host becomes available
                    appFileOpenDelegate.configure(with: store)
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
            AppCommands()
            CommandGroup(replacing: .newItem) { }
            FileCommands(store: store)
            SearchCommands(store: store)
            ViewCommands()
            TorrentCommands(store: store)
            SidebarCommands()
            CommandGroup(before: .sidebar) {
                Divider()
                Menu {
                    Picker("Appearance", selection: $themeManager.themeMode) {
                        Label("System", systemImage: "circle.lefthalf.filled").tag(ThemeMode.system)
                        Label("Light", systemImage: "sun.max").tag(ThemeMode.light)
                        Label("Dark", systemImage: "moon").tag(ThemeMode.dark)
                    }
                    .pickerStyle(.inline)
                    
                    Divider()
                    
                    Button(action: {
                        themeManager.cycleThemeMode()
                        appearanceHUDText = "Appearance: \(themeManager.themeMode.rawValue)"
                        hideHUDWork?.cancel()
                        showAppearanceHUD = true
                        let work = DispatchWorkItem {
                            showAppearanceHUD = false
                        }
                        hideHUDWork = work
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: work)
                    }) {
                        Label("Toggle Appearance", systemImage: "circle.lefthalf.filled")
                    }
                    .keyboardShortcut("j", modifiers: .command)
                } label: {
                    Label("Appearance", systemImage: "circle.lefthalf.filled")
                }
                Divider()
            }
        }
        // Statistics window - Intentionally using Window (not WindowGroup) to appear in Window menu
        // This follows Apple's pattern for utility/tool windows that users should be able to manage
        // Statistics is a user-manageable utility window, unlike About which is informational-only
        Window("Statistics", id: "statistics") {
            macOSStatisticsView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(store)
                .accentColor(themeManager.accentColor)
                .environmentObject(themeManager)
                .immediateTheme(manager: themeManager)
                .frame(minWidth: 420, idealWidth: 460, maxWidth: 600, minHeight: 320, idealHeight: 360, maxHeight: 800)
        }
        .windowResizability(.contentSize)
        
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
        
        #else
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(store) // Pass the shared store to the ContentView
                .accentColor(themeManager.accentColor) // Apply the accent color to the entire app
                .environmentObject(themeManager) // Pass the ThemeManager to all views
                .immediateTheme(manager: themeManager)
        }
        #endif
        
        #if os(macOS)
        Settings {
            SettingsView(store: store) // Use the same store instance
                .frame(minWidth: 500, idealWidth: 550, maxWidth: 650)
                .environmentObject(themeManager) // Pass the ThemeManager to the Settings view
                .immediateTheme(manager: themeManager)
        }
        #endif
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
