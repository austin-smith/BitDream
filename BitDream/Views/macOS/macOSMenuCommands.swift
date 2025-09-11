//
//  macOSMenuCommands.swift
//  BitDream
//
//  Created by Austin Smith on 12/29/22.
//

import SwiftUI
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
    @ObservedObject var store: Store
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

// Inspector Commands for panel visibility
struct InspectorCommands: Commands {
    @ObservedObject var store: Store
    
    var body: some Commands {
        // Panel Commands - group inspector with sidebar
        CommandGroup(after: .toolbar) {
            Divider()
            Button(action: {
                store.shouldToggleInspector.toggle()
            }) {
                Label(store.isInspectorVisible ? "Hide Inspector" : "Show Inspector", systemImage: "sidebar.right")
            }
            .keyboardShortcut("i", modifiers: [.option, .command])
        }
    }
}

// Appearance Commands for theme management
struct AppearanceCommands: Commands {
    @ObservedObject var themeManager: ThemeManager
    @Binding var showAppearanceHUD: Bool
    @Binding var appearanceHUDText: String
    @Binding var hideHUDWork: DispatchWorkItem?
    
    var body: some Commands {
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
