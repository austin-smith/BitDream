import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)

// MARK: - Focused Value Keys for Selection State

/// Key for passing selected torrents to menu commands via SwiftUI's focused value system.
/// This is the proper pattern for communicating view state (selection) to menu commands
/// without using @Published state which can cause "Publishing changes from within view updates" warnings.
struct SelectedTorrentsKey: FocusedValueKey {
    typealias Value = Binding<Set<Int>>
}

extension FocusedValues {
    /// The currently selected torrent IDs, exposed via focused value for menu commands.
    var selectedTorrentIds: Binding<Set<Int>>? {
        get { self[SelectedTorrentsKey.self] }
        set { self[SelectedTorrentsKey.self] = newValue }
    }
}

// MARK: - Search Commands

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

// MARK: - File Commands

struct FileCommands: Commands {
    @ObservedObject var store: Store
    @FocusedBinding(\.selectedTorrentIds) private var selectedTorrentIds: Set<Int>?

    private var selectedTorrents: Set<Torrent> {
        guard let ids = selectedTorrentIds else { return [] }
        return Set(ids.compactMap { id in
            store.torrents.first { $0.id == id }
        })
    }

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button(action: {
                store.presentGlobalTorrentFileImporter = true
            }) {
                Label("Add Torrent from File…", systemImage: "doc.badge.plus")
            }
            .keyboardShortcut("o", modifiers: .command)

            Button(action: {
                store.addTorrentInitialMode = .magnet
                store.isShowingAddAlert.toggle()
            }) {
                Label("Add Torrent from Magnet Link…", systemImage: "link.badge.plus")
            }
            .keyboardShortcut("o", modifiers: [.option, .command])

            Divider()

            Button(action: {
                if let firstTorrent = selectedTorrents.first {
                    store.globalRenameInput = firstTorrent.name
                    store.globalRenameTargetId = firstTorrent.id
                    store.showGlobalRenameDialog = true
                }
            }) {
                Label("Rename…", systemImage: "pencil")
            }
            .disabled(selectedTorrents.count != 1)
        }
    }
}

// MARK: - Torrent Commands

struct TorrentCommands: Commands {
    @ObservedObject var store: Store
    @FocusedBinding(\.selectedTorrentIds) private var selectedTorrentIds: Set<Int>?

    private var selectedTorrents: Set<Torrent> {
        guard let ids = selectedTorrentIds else { return [] }
        return Set(ids.compactMap { id in
            store.torrents.first { $0.id == id }
        })
    }

    var body: some Commands {
        CommandMenu("Torrent") {
            Button(action: {
                pauseSelectedTorrents()
            }) {
                Label("Pause Selected", systemImage: "pause")
            }
            .keyboardShortcut(".", modifiers: .command)
            .disabled(selectedTorrents.shouldDisablePause)

            Button(action: {
                resumeSelectedTorrents()
            }) {
                Label("Resume Selected", systemImage: "play")
            }
            .keyboardShortcut("/", modifiers: .command)
            .disabled(selectedTorrents.shouldDisableResume)

            Button(action: {
                resumeSelectedTorrentsNow()
            }) {
                Label("Resume Selected Now", systemImage: "play.fill")
            }
            .disabled(selectedTorrents.shouldDisableResume)

            Divider()

            Button(action: {
                store.showingMenuRemoveConfirmation = true
            }) {
                Label("Remove…", systemImage: "trash")
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(selectedTorrents.isEmpty)

            Divider()

            Button(action: {
                moveSelectedTorrentsToFront()
            }) {
                Label("Move to Front of Queue", systemImage: "arrow.up.to.line")
            }
            .disabled(selectedTorrents.isEmpty)

            Button(action: {
                moveSelectedTorrentsUp()
            }) {
                Label("Move Up in Queue", systemImage: "arrow.up")
            }
            .disabled(selectedTorrents.isEmpty)

            Button(action: {
                moveSelectedTorrentsDown()
            }) {
                Label("Move Down in Queue", systemImage: "arrow.down")
            }
            .disabled(selectedTorrents.isEmpty)

            Button(action: {
                moveSelectedTorrentsToBack()
            }) {
                Label("Move to Back of Queue", systemImage: "arrow.down.to.line")
            }
            .disabled(selectedTorrents.isEmpty)

            Divider()

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

            Button(action: {
                reannounceSelectedTorrents()
            }) {
                Label("Ask For More Peers", systemImage: "arrow.left.arrow.right")
            }
            .disabled(selectedTorrents.isEmpty)

            Button(action: {
                verifySelectedTorrents()
            }) {
                Label("Verify Local Data", systemImage: "checkmark.arrow.trianglehead.counterclockwise")
            }
            .disabled(selectedTorrents.isEmpty)
        }
    }

    // MARK: - Action Implementations

    private func pauseSelectedTorrents() {
        let selected = Array(selectedTorrents)
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
        let selected = Array(selectedTorrents)
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
        let selected = Array(selectedTorrents)
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
        let selected = Array(selectedTorrents)
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
        let selected = Array(selectedTorrents)
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

    // MARK: - Queue Movement

    private func moveSelectedTorrentsToFront() {
        let selectedIds = Array(selectedTorrents.map { $0.id })
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
        let selectedIds = Array(selectedTorrents.map { $0.id })
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
        let selectedIds = Array(selectedTorrents.map { $0.id })
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
        let selectedIds = Array(selectedTorrents.map { $0.id })
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

// MARK: - View Commands

struct ViewCommands: Commands {
    @ObservedObject var store: Store
    @Environment(\.openWindow) private var openWindow
    @AppStorage(UserDefaultsKeys.torrentListCompactMode) private var isCompactMode: Bool = false
    @AppStorage(UserDefaultsKeys.showContentTypeIcons) private var showContentTypeIcons: Bool = true

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Divider()
            Toggle(isOn: $isCompactMode) {
                Label("Compact View", systemImage: "list.bullet")
            }

            Toggle(isOn: $showContentTypeIcons) {
                Label("Show File Type Icons", systemImage: "doc.richtext")
            }

            Divider()

            Button(action: {
                openWindow(id: "connection-info")
            }) {
                Label("Connection Info", systemImage: "network")
            }

            Button(action: {
                openWindow(id: "statistics")
            }) {
                Label("Statistics", systemImage: "chart.bar")
            }
        }
    }
}

// MARK: - Inspector Commands

struct InspectorCommands: Commands {
    @ObservedObject var store: Store

    var body: some Commands {
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

// MARK: - Appearance Commands

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

// MARK: - App Commands

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
