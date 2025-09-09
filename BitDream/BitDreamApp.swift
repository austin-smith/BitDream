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
            Button("Search Torrents") {
                store.shouldActivateSearch.toggle()
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
            Button("Add Torrent from File…") {
                #if os(macOS)
                store.presentGlobalTorrentFileImporter = true
                #else
                store.isShowingAddAlert.toggle()
                #endif
            }
            .keyboardShortcut("o", modifiers: .command)

            Button("Add Torrent from Magnet Link…") {
                #if os(macOS)
                store.addTorrentInitialMode = .magnet
                #endif
                store.isShowingAddAlert.toggle()
            }
            .keyboardShortcut("o", modifiers: [.option, .command])
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
            Button("Pause Selected") {
                pauseSelectedTorrents()
            }
            .keyboardShortcut(".", modifiers: .command)
            .disabled(store.selectedTorrents.shouldDisablePauseAction)
            
            Button("Resume Selected") {
                resumeSelectedTorrents()
            }
            .keyboardShortcut("/", modifiers: .command)
            .disabled(store.selectedTorrents.shouldDisableResumeAction)
            
            Button("Resume Selected Now") {
                resumeSelectedTorrentsNow()
            }
            .disabled(store.selectedTorrents.shouldDisableResumeAction)
            
            Divider()
            
            // Remove action
            Button("Remove...") {
                store.showingMenuRemoveConfirmation = true
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(store.selectedTorrents.isEmpty)
            
            Divider()
            
            // All torrents actions
            Button("Pause All") {
                pauseAllTorrents()
            }
            .keyboardShortcut(".", modifiers: [.option, .command])
            .disabled(store.torrents.isEmpty)
            
            Button("Resume All") {
                resumeAllTorrents()
            }
            .keyboardShortcut("/", modifiers: [.option, .command])
            .disabled(store.torrents.isEmpty)
            
            Divider()
            
            // Verify action
            Button("Verify Local Data") {
                verifySelectedTorrents()
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
        
        performTransmissionStatusRequest(
            method: "torrent-stop",
            args: ["ids": ids] as [String: [Int]],
            config: info.config,
            auth: info.auth
        ) { response in
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
        
        performTransmissionStatusRequest(
            method: "torrent-start",
            args: ["ids": ids] as [String: [Int]],
            config: info.config,
            auth: info.auth
        ) { response in
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
        
        let info = makeConfig(store: store)
        let ids = selected.map { $0.id }
        
        performTransmissionStatusRequest(
            method: "torrent-start-now",
            args: ["ids": ids] as [String: [Int]],
            config: info.config,
            auth: info.auth
        ) { response in
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
}
#endif

// View Commands for view-related toggles
struct ViewCommands: Commands {
    @AppStorage("torrentListCompactMode") private var isCompactMode: Bool = false
    @AppStorage("showContentTypeIcons") private var showContentTypeIcons: Bool = true
    
    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Divider()
            
            Toggle("Compact View", isOn: $isCompactMode)
            
            Toggle("Show File Type Icons", isOn: $showContentTypeIcons)
        }
    }
}

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
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
            FileCommands(store: store)
            SearchCommands(store: store)
            ViewCommands()
            TorrentCommands(store: store)
            SidebarCommands()
            CommandGroup(before: .sidebar) {
                Divider()
                Menu("Appearance") {
                    Picker("Appearance", selection: $themeManager.themeMode) {
                        Text("System").tag(ThemeMode.system)
                        Text("Light").tag(ThemeMode.light)
                        Text("Dark").tag(ThemeMode.dark)
                    }
                    .pickerStyle(.inline)
                    
                    Divider()
                    
                    Button("Toggle Appearance") {
                        themeManager.cycleThemeMode()
                        appearanceHUDText = "Appearance: \(themeManager.themeMode.rawValue)"
                        hideHUDWork?.cancel()
                        showAppearanceHUD = true
                        let work = DispatchWorkItem {
                            showAppearanceHUD = false
                        }
                        hideHUDWork = work
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: work)
                    }
                    .keyboardShortcut("j", modifiers: .command)
                }
                Divider()
            }
        }
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
                .frame(minWidth: 500, idealWidth: 550, maxWidth: 650, minHeight: 300, idealHeight: 350, maxHeight: 450)
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
