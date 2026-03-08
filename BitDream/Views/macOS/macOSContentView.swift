import SwiftUI
import Foundation
import SwiftData

#if os(macOS)

// MARK: - Main Content View

struct macOSContentView: View {
    @Environment(\.openSettings) private var openSettings
    let modelContext: ModelContext
    let hosts: [Host]
    @ObservedObject var store: TransmissionStore

    @ObservedObject private var themeManager = ThemeManager.shared

    @State var sortProperty: SortProperty = UserDefaults.standard.sortProperty
    @State var sortOrder: SortOrder = UserDefaults.standard.sortOrder
    @State private var filterBySelection: [TorrentStatusCalc] = TorrentStatusCalc.allCases
    @State private var sidebarSelection: SidebarSelection = .allDreams
    @State private var isInspectorVisible: Bool = UserDefaults.standard.inspectorVisibility
    @State private var columnVisibility: NavigationSplitViewVisibility = UserDefaults.standard.sidebarVisibility
    @State private var searchText: String = ""
    @State private var includedLabels: Set<String> = []
    @State private var excludedLabels: Set<String> = []
    @State private var showOnlyNoLabels: Bool = false
    @AppStorage(UserDefaultsKeys.torrentListCompactMode) private var isCompactMode: Bool = false
    @AppStorage(UserDefaultsKeys.showContentTypeIcons) private var showContentTypeIcons: Bool = true

    // Selection state - kept local to avoid "Publishing changes from within view updates" warning
    // Exposed to menu commands via @FocusedValue
    @State private var selectedTorrentIds: Set<Int> = []

    enum FocusTarget: Hashable { case contentList }
    @FocusState private var focusedTarget: FocusTarget?

    // Search activation state - using isPresented for searchable
    @State private var isSearchPresented: Bool = false

    // Drag and drop state
    @State private var isDropTargeted = false
    @State private var draggedTorrentInfo: [TorrentInfo] = []
    @State private var showingFilterPopover = false

    // Base view with basic modifiers
    private var baseView: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebarView
        } detail: {
            detailView
        }
        .defaultFocus($focusedTarget, .contentList)
    }

    // View with just sheet modifiers
    private var viewWithSheets: some View {
        baseView
        .sheet(isPresented: $store.setup, content: {
            ServerDetail(store: store, modelContext: modelContext, hosts: hosts, isAddNew: true)
        })
        .sheet(isPresented: $store.editServers, content: {
            ServerList(store: store, modelContext: modelContext, hosts: hosts)
        })
        .sheet(isPresented: $store.isShowingAddAlert, onDismiss: {
            // Advance queued magnet links when the sheet closes
            store.advanceMagnetQueue()
        }, content: {
            AddTorrent(store: store)
        })
        .sheet(isPresented: $store.isError, content: {
            ErrorDialog(store: store)
                .frame(width: 400, height: 400)
        })
    }

    // View with basic event handlers
    private var viewWithHandlers: some View {
        viewWithSheets
        .onChange(of: sidebarSelection) { _, newValue in
            // Update the filter
            filterBySelection = newValue.filter

            // Only clear selection if the selected torrent isn't in the new filtered list
            if let selectedId = selectedTorrentIds.first {
                let filteredTorrents = store.torrents.filtered(by: newValue.filter)
                    .filter { torrentMatchesSearch($0, query: searchText) }
                let isSelectedTorrentInFilteredList = filteredTorrents.contains { $0.id == selectedId }

                if !isSelectedTorrentInFilteredList {
                    selectedTorrentIds.removeAll()
                }
            }
        }
        .onReceive(store.$torrents) { _ in
            updateAppBadge()
        }
        .onAppear {
            updateAppBadge()
        }
    }

    // Enhanced view (state changes + search + toolbar)
    private var enhancedView: some View {
        viewWithHandlers
        .onChange(of: columnVisibility) { _, newValue in
            UserDefaults.standard.sidebarVisibility = newValue
            focusedTarget = .contentList
        }
        .onChange(of: isInspectorVisible) { _, newValue in
            UserDefaults.standard.inspectorVisibility = newValue
            // Defer state change to avoid publishing during view update
            Task { @MainActor in
                store.isInspectorVisible = newValue
            }
            focusedTarget = .contentList
        }
        .onChange(of: sortProperty) { _, newValue in
            UserDefaults.standard.sortProperty = newValue
        }
        .onChange(of: sortOrder) { _, newValue in
            UserDefaults.standard.sortOrder = newValue
        }
        .onChange(of: store.shouldActivateSearch) { _, newValue in
            if newValue {
                isSearchPresented = true
                // Defer state change to avoid publishing during view update
                Task { @MainActor in
                    store.shouldActivateSearch = false
                }
            }
        }
        .onChange(of: store.shouldToggleInspector) { _, newValue in
            if newValue {
                withAnimation {
                    isInspectorVisible.toggle()
                }
                // Defer state change to avoid publishing during view update
                Task { @MainActor in
                    store.shouldToggleInspector = false
                }
            }
        }
        .onChange(of: searchText) { oldValue, newValue in
            handleSearchTextChange(oldValue: oldValue, newValue: newValue)
        }
        .searchable(text: $searchText, isPresented: $isSearchPresented, placement: .toolbar, prompt: "Search torrents")
        .searchSuggestions { EmptyView() }
        .toolbar {
            macOSContentToolbar(
                sortProperty: $sortProperty,
                sortOrder: $sortOrder,
                showingFilterPopover: $showingFilterPopover,
                hasActiveFilters: hasActiveFilters,
                activeFilterCount: activeFilterCount,
                accentColor: themeManager.accentColor,
                availableLabels: store.availableLabels,
                includedLabels: $includedLabels,
                excludedLabels: $excludedLabels,
                showOnlyNoLabels: $showOnlyNoLabels,
                noLabelCount: store.torrents.filter { $0.labels.isEmpty }.count,
                countForLabel: { store.torrentCount(for: $0) },
                isCompactMode: $isCompactMode,
                isInspectorVisible: $isInspectorVisible,
                onAddTorrent: {
                    store.isShowingAddAlert.toggle()
                }
            )
        }
    }

    // Final view with all remaining modifiers
    private var finalView: some View {
        enhancedView
            // Expose selection to menu commands via FocusedValue
            .focusedValue(\.selectedTorrentIds, $selectedTorrentIds)
    }

    var body: some View {
        finalView
    }

    // MARK: - macOS Views

    private var sidebarView: some View {
        macOSContentSidebar(
            hosts: hosts,
            sidebarSelection: $sidebarSelection,
            selectedHostID: store.host?.serverID,
            accentColor: themeManager.accentColor,
            torrentCount: { torrentCount(for: $0) },
            onSelectHost: { host in
                store.setHost(host: host)
                selectedTorrentIds.removeAll()
            },
            onAddServer: {
                store.setup.toggle()
            },
            onManageServers: {
                store.editServers.toggle()
            },
            onOpenSettings: {
                openSettings()
            }
        )
    }

    private var detailView: some View {
        macOSContentDetail(
            store: store,
            torrents: displayedTorrents,
            isCompactMode: isCompactMode,
            selectedTorrentIds: $selectedTorrentIds,
            sortProperty: $sortProperty,
            sortOrder: $sortOrder,
            selectedTorrents: selectedTorrents,
            showContentTypeIcons: showContentTypeIcons,
            accentColor: themeManager.accentColor,
            isDropTargeted: $isDropTargeted,
            draggedTorrentInfo: $draggedTorrentInfo,
            focusedTarget: $focusedTarget
        )
        .navigationTitle(sidebarSelection.rawValue)
        .navigationSubtitle(navigationSubtitle)
        .refreshable {
            await store.refreshNow()
        }
        .alert(
            "Remove \(selectedTorrents.count > 1 ? "\(selectedTorrents.count) Torrents" : "Torrent")",
            isPresented: $store.showingMenuRemoveConfirmation) {
                Button(role: .destructive) {
                    removeSelectedTorrentsFromMenu(deleteData: true)
                } label: {
                    Text("Delete file(s)")
                }
                Button("Remove from list only") {
                    removeSelectedTorrentsFromMenu(deleteData: false)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Do you want to delete the file(s) from the disk?")
            }
        .inspector(isPresented: $isInspectorVisible) {
            macOSContentInspector(store: store, selectedTorrent: selectedTorrent)
                .inspectorColumnWidth(min: 350, ideal: 400, max: 500)
        }
    }
}

private extension macOSContentView {
    var selectedTorrents: Set<Torrent> {
        Set(selectedTorrentIds.compactMap { id in
            store.torrents.first { $0.id == id }
        })
    }

    var displayedTorrents: [Torrent] {
        let filteredTorrents = store.torrents.filtered(by: filterBySelection)
            .filter { torrent in
                torrentMatchesSearch(torrent, query: searchText)
            }
        return sortTorrents(filteredTorrents, by: sortProperty, order: sortOrder)
    }

    var selectedTorrent: Torrent? {
        guard let selectedId = selectedTorrentIds.first else { return nil }
        return store.torrents.first { $0.id == selectedId }
    }

    var completedTorrentsCount: Int {
        getCompletedTorrentsCount(in: store)
    }

    var hasActiveFilters: Bool {
        !includedLabels.isEmpty || !excludedLabels.isEmpty || showOnlyNoLabels
    }

    var activeFilterCount: Int {
        includedLabels.count + excludedLabels.count + (showOnlyNoLabels ? 1 : 0)
    }

    var navigationSubtitle: String {
        let count = torrentCount(for: sidebarSelection)
        var subtitle = "\(count) dream\(count == 1 ? "" : "s")"

        if hasActiveFilters {
            subtitle += " • \(activeFilterCount) label filter\(activeFilterCount == 1 ? "" : "s")"
        }

        return subtitle
    }

    func torrentMatchesSearch(_ torrent: Torrent, query: String) -> Bool {
        if showOnlyNoLabels && !torrent.labels.isEmpty {
            return false
        }

        if !includedLabels.isEmpty {
            let hasIncludedLabel = torrent.labels.contains { torrentLabel in
                includedLabels.contains { includedLabel in
                    torrentLabel.lowercased() == includedLabel.lowercased()
                }
            }
            if !hasIncludedLabel {
                return false
            }
        }

        if !excludedLabels.isEmpty {
            let hasExcludedLabel = torrent.labels.contains { torrentLabel in
                excludedLabels.contains { excludedLabel in
                    torrentLabel.lowercased() == excludedLabel.lowercased()
                }
            }
            if hasExcludedLabel {
                return false
            }
        }

        if query.isEmpty {
            return true
        }

        return torrent.name.localizedCaseInsensitiveContains(query)
    }

    func torrentCount(for category: SidebarSelection) -> Int {
        let filteredByCategory = store.torrents.filtered(by: category.filter)
        let filteredBySearch = filteredByCategory.filter { torrent in
            torrentMatchesSearch(torrent, query: searchText)
        }
        return filteredBySearch.count
    }

    func updateAppBadge() {
        updateMacOSAppBadge(count: completedTorrentsCount)
    }

    func removeSelectedTorrentsFromMenu(deleteData: Bool) {
        let selected = Array(selectedTorrents)
        guard !selected.isEmpty else { return }

        let info = makeConfig(store: store)

        for torrent in selected {
            deleteTorrent(torrent: torrent, erase: deleteData, config: info.config, auth: info.auth) { response in
                handleTransmissionResponse(response,
                    onSuccess: {},
                    onError: { error in
                        store.debugBrief = "Failed to remove torrent"
                        store.debugMessage = error
                        store.isError = true
                    }
                )
            }
        }

        selectedTorrentIds.removeAll()
    }

    func handleSearchTextChange(oldValue: String, newValue: String) {
        if let selectedId = selectedTorrentIds.first {
            let selectedMatches = store.torrents.first(where: { $0.id == selectedId }).map { torrentMatchesSearch($0, query: searchText) } ?? false
            let isInFiltered = store.torrents.filtered(by: filterBySelection).contains { $0.id == selectedId }
            if !selectedMatches || !isInFiltered {
                selectedTorrentIds.removeAll()
            }
        }
    }
}

// MARK: - Label Filter Chip Component

enum LabelFilterAction {
    case include, exclude, clear
}

struct LabelFilterChip: View {
    let label: String
    let count: Int
    let isIncluded: Bool
    let isExcluded: Bool
    let onAction: (LabelFilterAction) -> Void
    @ObservedObject private var themeManager = ThemeManager.shared

    private var backgroundColor: Color {
        if isIncluded {
            return themeManager.accentColor.opacity(0.2)
        } else if isExcluded {
            return Color.red.opacity(0.2)
        } else {
            return Color(NSColor.controlColor)
        }
    }

    private var borderColor: Color {
        if isIncluded {
            return themeManager.accentColor
        } else if isExcluded {
            return Color.red
        } else {
            return Color.secondary.opacity(0.3)
        }
    }

    private var textColor: Color {
        if isIncluded {
            return themeManager.accentColor
        } else if isExcluded {
            return Color.red
        } else {
            return Color.primary
        }
    }

    var body: some View {
        Button(action: {
            if isIncluded {
                onAction(.exclude)
            } else if isExcluded {
                onAction(.clear)
            } else {
                onAction(.include)
            }
        }, label: {
            HStack(spacing: 4) {
                Image(systemName: "tag.fill")
                    .font(.caption2)
                    .foregroundColor(textColor)

                Text(label)
                    .font(.caption)
                    .foregroundColor(textColor)

                Text("(\(count))")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                if isExcluded {
                    Image(systemName: "minus.circle.fill")
                        .font(.caption2)
                        .foregroundColor(.red)
                }
            }
        })
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(backgroundColor)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(borderColor, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        .buttonStyle(.plain)
        .help(isIncluded ? "Click to exclude '\(label)'" : isExcluded ? "Click to clear filter" : "Click to include '\(label)'")
    }
}
#endif
