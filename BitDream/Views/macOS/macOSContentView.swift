import SwiftUI
import Foundation
import KeychainAccess
import CoreData
import UniformTypeIdentifiers

#if os(macOS)
struct macOSContentView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openSettings) private var openSettings
    @State private var showingThemeSettings = false
    let viewContext: NSManagedObjectContext
    let hosts: FetchedResults<Host>
    @ObservedObject var store: Store
    
    // Add ThemeManager to access accent color
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
    
    enum FocusTarget: Hashable { case contentList }
    @FocusState private var focusedTarget: FocusTarget?
    
    // Search activation state - using isPresented for searchable
    @State private var isSearchPresented: Bool = false
    
    // Drag and drop state
    @State private var isDropTargeted = false
    @State private var draggedTorrentInfo: [TorrentInfo] = []
    @State private var showingFilterPopover = false
    
    // Torrent Preview Card Component
    private var torrentPreviewCard: some View {
        let totalSize = draggedTorrentInfo.reduce(0) { $0 + $1.totalSize }
        let totalFiles = draggedTorrentInfo.reduce(0) { $0 + $1.fileCount }
        let formattedTotalSize = byteCountFormatter.string(fromByteCount: totalSize)
        let fileCountText = totalFiles == 1 ? "1 file" : "\(totalFiles) files"
        
        let displayTitle: String = {
            if draggedTorrentInfo.count == 1 {
                if let name = draggedTorrentInfo.first?.name, !name.isEmpty {
                    return name
                } else {
                    return "1 Torrent"
                }
            } else {
                return "\(draggedTorrentInfo.count) Torrents"
            }
        }()

        return HStack(spacing: 16) {
            // Large icon spanning both rows
            Image(systemName: "document.badge.plus")
                .foregroundColor(.secondary)
                .font(.system(size: 40))
                .frame(width: 50, height: 50)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(displayTitle)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                
                HStack(spacing: 8) {
                    Text(formattedTotalSize)
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundColor(.secondary)
                    Text("•")
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundColor(.secondary)
                    Text(fileCountText)
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThickMaterial)
                .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 6)
        )
        .frame(maxWidth: 400, minHeight: 80)
    }
    
    // Binding for selected torrents derived from selected IDs
    private var selectedTorrentsBinding: Binding<Set<Torrent>> {
        Binding<Set<Torrent>>(
            get: {
                Set(store.selectedTorrentIds.compactMap { id in
                    store.torrents.first { $0.id == id }
                })
            },
            set: { newSelection in
                store.selectedTorrentIds = Set(newSelection.map { $0.id })
            }
        )
    }
    
    // Helper function to check if a torrent matches the search query and label filters
    private func torrentMatchesSearch(_ torrent: Torrent, query: String) -> Bool {
        // Check no-labels filter first
        if showOnlyNoLabels {
            if !torrent.labels.isEmpty {
                return false
            }
        }
        
        // Check label filters
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
        
        // If no search query, just return true (label filtering already applied above)
        if query.isEmpty {
            return true
        }
        
        // Search in name only (simplified text search)
        return torrent.name.localizedCaseInsensitiveContains(query)
    }
    
    // Computed property to get counts for each category
    private func torrentCount(for category: SidebarSelection) -> Int {
        let filteredByCategory = store.torrents.filtered(by: category.filter)
        let filteredBySearch = filteredByCategory.filter { torrent in
            torrentMatchesSearch(torrent, query: searchText)
        }
        return filteredBySearch.count
    }
    
    // Computed property to get completed torrents count
    private var completedTorrentsCount: Int {
        getCompletedTorrentsCount(in: store)
    }
    
    // Update the app badge
    private func updateAppBadge() {
        updateMacOSAppBadge(count: completedTorrentsCount)
    }
    
    // Remove selected torrents from menu command
    private func removeSelectedTorrentsFromMenu(deleteData: Bool) {
        let selected = Array(store.selectedTorrents)
        guard !selected.isEmpty else { return }
        
        let info = makeConfig(store: store)
        
        for torrent in selected {
            deleteTorrent(torrent: torrent, erase: deleteData, config: info.config, auth: info.auth) { response in
                handleTransmissionResponse(response,
                    onSuccess: {},
                    onError: { error in
                        DispatchQueue.main.async {
                            store.debugBrief = "Failed to remove torrent"
                            store.debugMessage = error
                            store.isError = true
                        }
                    }
                )
            }
        }
        
        // Clear selection after removal
        DispatchQueue.main.async {
            store.selectedTorrentIds.removeAll()
        }
    }
    
    // Computed properties for filter state
    private var hasActiveFilters: Bool {
        !includedLabels.isEmpty || !excludedLabels.isEmpty || showOnlyNoLabels
    }
    
    private var activeFilterCount: Int {
        includedLabels.count + excludedLabels.count + (showOnlyNoLabels ? 1 : 0)
    }
    
    // Computed property for navigation subtitle
    private var navigationSubtitle: String {
        let count = torrentCount(for: sidebarSelection)
        var subtitle = "\(count) dream\(count == 1 ? "" : "s")"
        
        // Add label filter indicators
        if hasActiveFilters {
            subtitle += " • \(activeFilterCount) label filter\(activeFilterCount == 1 ? "" : "s")"
        }
        
        return subtitle
    }
    
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
        .sheet(isPresented: $store.setup) {
            ServerDetail(store: store, viewContext: viewContext, hosts: hosts, isAddNew: true)
        }
        .sheet(isPresented: $store.editServers) {
            ServerList(store: store, viewContext: viewContext)
        }
        .sheet(isPresented: $store.isShowingAddAlert, onDismiss: {
            // Advance queued magnet links when the sheet closes
            store.advanceMagnetQueue()
        }) {
            AddTorrent(store: store)
        }
        .sheet(isPresented: $store.isError) {
            ErrorDialog(store: store)
                .frame(width: 400, height: 400)
        }
    }
    
    // View with basic event handlers
    private var viewWithHandlers: some View {
        viewWithSheets
        .onChange(of: sidebarSelection) { oldValue, newValue in
            // Update the filter
            filterBySelection = newValue.filter
            
            // Only clear selection if the selected torrent isn't in the new filtered list
            if let selectedId = store.selectedTorrentIds.first {
                let filteredTorrents = store.torrents.filtered(by: newValue.filter)
                    .filter { torrentMatchesSearch($0, query: searchText) }
                let isSelectedTorrentInFilteredList = filteredTorrents.contains { $0.id == selectedId }
                
                if !isSelectedTorrentInFilteredList {
                    store.selectedTorrentIds.removeAll()
                }
            }
            
            print("\(newValue.rawValue) selected")
        }
        .onReceive(store.$torrents) { _ in
            updateAppBadge()
        }
        .onAppear {
            if store.host == nil {
                setupHost(hosts: hosts, store: store)
            }
            updateAppBadge()
        }
    }
    
    // Search suggestions - simplified for text search only
    private var searchSuggestions: some View {
        Group {
            // Could add recent searches or other text-based suggestions here in the future
            EmptyView()
        }
    }
    
    // Sort menu content extracted to reduce type-check complexity
    private var sortMenuContent: some View {
        Group {
            ForEach(SortProperty.allCases, id: \.self) { property in
                let isSelected = Binding<Bool>(
                    get: { sortProperty == property },
                    set: { if $0 { sortProperty = property } }
                )
                Toggle(isOn: isSelected) {
                    Text(property.rawValue)
                }
            }
            
            Divider()
            
            let isAscending = Binding<Bool>(
                get: { sortOrder == .ascending },
                set: { if $0 { sortOrder = .ascending } }
            )
            Toggle(isOn: isAscending) {
                Text("Ascending")
            }
            
            let isDescending = Binding<Bool>(
                get: { sortOrder == .descending },
                set: { if $0 { sortOrder = .descending } }
            )
            Toggle(isOn: isDescending) {
                Text("Descending")
            }
        }
    }
    
    // Filter menu content for the filter button
    private var filterMenuContent: some View {
        Group {
            Section("Filter by Labels") {
                // Available labels
                if !store.availableLabels.isEmpty {
                    ForEach(store.availableLabels, id: \.self) { label in
                        Button(action: {
                            // Clear no-labels filter when selecting specific labels
                            if showOnlyNoLabels {
                                showOnlyNoLabels = false
                            }
                            
                            if includedLabels.contains(label) {
                                includedLabels.remove(label)
                                excludedLabels.insert(label)
                            } else if excludedLabels.contains(label) {
                                excludedLabels.remove(label)
                            } else {
                                includedLabels.insert(label)
                            }
                        }) {
                            HStack {
                                Image(systemName: includedLabels.contains(label) ? "checkmark.circle.fill" : excludedLabels.contains(label) ? "minus.circle.fill" : "circle")
                                    .foregroundColor(includedLabels.contains(label) ? themeManager.accentColor : excludedLabels.contains(label) ? .red : .secondary)
                                
                                Text(label)
                                    .foregroundColor(.primary)
                                
                                Spacer()
                                
                                Text("\(store.torrentCount(for: label))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Divider()
                }
                
                // No labels option at bottom
                Button(action: {
                    showOnlyNoLabels.toggle()
                    // Clear other label filters when showing no labels
                    if showOnlyNoLabels {
                        includedLabels.removeAll()
                        excludedLabels.removeAll()
                    }
                }) {
                    HStack {
                        Image(systemName: showOnlyNoLabels ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(showOnlyNoLabels ? themeManager.accentColor : .secondary)
                        
                        Text("No labels")
                            .foregroundColor(.primary)
                            .italic()
                        
                        Spacer()
                        
                        Text("\(store.torrents.filter { $0.labels.isEmpty }.count)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            
            if hasActiveFilters {
                Divider()
                Button("Clear All Filters") {
                    includedLabels.removeAll()
                    excludedLabels.removeAll()
                    showOnlyNoLabels = false
                }
            }
        }
    }
    
    // Extracted to simplify onChange(of: searchText)
    private func handleSearchTextChange(oldValue: String, newValue: String) {
        // Clear selection if the selected torrent no longer matches the search
        if let selectedId = store.selectedTorrentIds.first {
            let selectedMatches = store.torrents.first(where: { $0.id == selectedId }).map { torrentMatchesSearch($0, query: searchText) } ?? false
            let isInFiltered = store.torrents.filtered(by: filterBySelection).contains { $0.id == selectedId }
            if !selectedMatches || !isInFiltered {
                store.selectedTorrentIds.removeAll()
            }
        }
    }

    // Enhanced view (state changes + search + toolbar)
    private var enhancedView: some View {
        viewWithHandlers
        .onChange(of: columnVisibility) { oldValue, newValue in
            UserDefaults.standard.sidebarVisibility = newValue
            focusedTarget = .contentList
        }
        .onChange(of: isInspectorVisible) { oldValue, newValue in
            UserDefaults.standard.inspectorVisibility = newValue
            store.isInspectorVisible = newValue
            focusedTarget = .contentList
        }
        .onChange(of: sortProperty) { oldValue, newValue in
            UserDefaults.standard.sortProperty = newValue
        }
        .onChange(of: sortOrder) { oldValue, newValue in
            UserDefaults.standard.sortOrder = newValue
        }
        .onChange(of: store.shouldActivateSearch) { oldValue, newValue in
            if newValue {
                isSearchPresented = true
                store.shouldActivateSearch = false
            }
        }
        .onChange(of: store.shouldToggleInspector) { oldValue, newValue in
            if newValue {
                withAnimation {
                    isInspectorVisible.toggle()
                }
                store.shouldToggleInspector = false
            }
        }
        .onChange(of: searchText) { oldValue, newValue in
            handleSearchTextChange(oldValue: oldValue, newValue: newValue)
        }
        .searchable(text: $searchText, isPresented: $isSearchPresented, placement: .toolbar, prompt: "Search torrents")
        .searchSuggestions { searchSuggestions }
        .toolbar {
            // Content toolbar items
            ToolbarItem(placement: .automatic) {
                Menu {
                    sortMenuContent
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down.circle")
                }
            }
            
            // Filter button
            ToolbarItem(placement: .automatic) {
                Button(action: {
                    showingFilterPopover.toggle()
                }) {
                    Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
                        .if(hasActiveFilters) { view in
                            view.foregroundColor(themeManager.accentColor)
                        }
                }
                .help(hasActiveFilters ? "Active filters (\(activeFilterCount))" : "Filter torrents")
                .popover(isPresented: $showingFilterPopover, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 12) {
                        filterMenuContent
                    }
                    .padding()
                    .frame(minWidth: 250)
                }
            }
            
            // Add torrent button
            ToolbarItem(placement: .primaryAction) {
                Button(action: {
                    store.isShowingAddAlert.toggle()
                }) {
                    Label("Add Torrent", systemImage: "plus")
                }
                .help("Add torrent")
            }
            
            // Toggle compact mode button
            ToolbarItem(placement: .automatic) {
                Button(action: {
                    withAnimation {
                        isCompactMode.toggle()
                    }
                }) {
                    Label(
                        isCompactMode ? "Expanded View" : "Compact View",
                        systemImage: isCompactMode ? "rectangle.grid.1x2" : "list.bullet"
                    )
                }
                .help(isCompactMode ? "Expanded view" : "Compact view")
            }
            
            // Toggle inspector button
            ToolbarItem(placement: .automatic) {
                Button(action: {
                    // Toggle inspector visibility
                    withAnimation {
                        isInspectorVisible.toggle()
                    }
                }) {
                    Label("Inspector", systemImage: "sidebar.right")
                }
                .help(isInspectorVisible ? "Hide inspector" : "Show inspector")
            }
        }
    }

    // Final view with all remaining modifiers
    private var finalView: some View {
        enhancedView
    }
    
    var body: some View {
        finalView
    }
    
    // MARK: - macOS Views
    
    private var sidebarView: some View {
        List(selection: $sidebarSelection) {
            Section("Dreams") {
                ForEach(SidebarSelection.allCases) { item in
                    Label(item.rawValue, systemImage: item.icon)
                        .badge(torrentCount(for: item))
                        .tag(item)
                }
            }
            
            Section("Servers") {
                ForEach(hosts, id: \.self) { host in
                    Button {
                        store.setHost(host: host)
                        // Clear selection when changing host
                        store.selectedTorrentIds.removeAll()
                        // Force refresh data when changing host
                        updateList(store: store, update: { _ in })
                    } label: {
                        HStack {
                            Label(host.name ?? "Unnamed Server", systemImage: "server.rack")
                            Spacer()
                            if host == store.host {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                
                Button {
                    store.setup.toggle()
                } label: {
                    Label("Add Server", systemImage: "plus")
                }
                .buttonStyle(.plain)
            }
            
            Section("Settings") {
                Button {
                    store.editServers.toggle()
                } label: {
                    Label("Manage Servers", systemImage: "gearshape")
                }
                .buttonStyle(.plain)
                
                Button {
                    openSettings()
                } label: {
                    Label("Settings", systemImage: "gear")
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(SidebarListStyle())
        .tint(themeManager.accentColor) // Apply accent color to sidebar selection
    }
    
    private var detailView: some View {
        VStack(spacing: 0) {
            StatsHeaderView(store: store)
            
            VStack {
                // Torrent list
                if store.torrents.isEmpty {
                    VStack {
                        Spacer()
                        
                        if isDropTargeted {
                            VStack(spacing: 12) {
                                Image(systemName: "plus.circle")
                                    .font(.system(size: 48))
                                    .foregroundColor(themeManager.accentColor)
                                Text("Drop .torrent files here to add")
                                    .font(.title2)
                                    .foregroundColor(themeManager.accentColor)
                            }
                        } else {
                            VStack(spacing: 12) {
                                Text("💭")
                                    .font(.system(size: 40))
                                Text("No dreams available")
                                    .foregroundColor(.gray)
                                Text("Drag .torrent files here or use the + button")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                    }
                } else {
                    // Break up the complex expression into steps
                    let filteredTorrents = store.torrents.filtered(by: filterBySelection)
                        .filter { torrent in
                            torrentMatchesSearch(torrent, query: searchText)
                        }
                    let sortedTorrents = sortTorrents(filteredTorrents, by: sortProperty, order: sortOrder)
                    
                    if isCompactMode {
                        // Compact table view
                        macOSTorrentListCompact(
                            torrents: sortedTorrents,
                            selection: $store.selectedTorrentIds,
                            store: store,
                            showContentTypeIcons: showContentTypeIcons
                        )
                        .focusable(true)
                        .focused($focusedTarget, equals: .contentList)
                    } else {
                        // Expanded list view
                        List(selection: $store.selectedTorrentIds) {
                            ForEach(sortedTorrents, id: \.id) { torrent in
                                TorrentListRow(
                                    torrent: binding(for: torrent, in: store),
                                    store: store,
                                    selectedTorrents: selectedTorrentsBinding,
                                    showContentTypeIcons: showContentTypeIcons
                                )
                                .tag(torrent.id)
                                .listRowSeparator(.visible)
                            }
                        }
                        .listStyle(.plain)
                        .tint(themeManager.accentColor) // Apply accent color to list selection
                        .focusable(true)
                        .focused($focusedTarget, equals: .contentList)
                    }
                }
            }
            .onDrop(of: [.fileURL], delegate: TorrentDropDelegate(
                isDropTargeted: $isDropTargeted,
                draggedTorrentInfo: $draggedTorrentInfo,
                store: store
            ))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .fill(themeManager.accentColor.opacity(isDropTargeted ? 0.1 : 0))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(themeManager.accentColor, lineWidth: isDropTargeted ? 2.5 : 0)
                            .opacity(isDropTargeted ? 0.8 : 0)
                    )
                    .animation(.easeInOut(duration: 0.2), value: isDropTargeted)
            )
            .overlay(
                // Torrent preview card
                Group {
                    if isDropTargeted && !draggedTorrentInfo.isEmpty {
                        torrentPreviewCard
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isDropTargeted)
            )
            .onChange(of: isDropTargeted) { oldValue, newValue in
                if !newValue {
                    // Clear dragged files when drag ends
                    draggedTorrentInfo = []
                }
            }
        }
        .navigationTitle(sidebarSelection.rawValue)
        .navigationSubtitle(navigationSubtitle)
        
        .refreshable {
            updateList(store: store, update: {_ in})
        }
        .alert("Connection Error", isPresented: $store.showConnectionErrorAlert) {
            Button("Edit Server", role: .none) {
                store.editServers.toggle()
            }
            Button("Retry", role: .none) {
                store.reconnect()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(store.connectionErrorMessage)
        }
        .alert(
            "Remove \(store.selectedTorrents.count > 1 ? "\(store.selectedTorrents.count) Torrents" : "Torrent")",
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
            macOSDetail
                .inspectorColumnWidth(min: 350, ideal: 400, max: 500)
        }
    }
    
    private var macOSDetail: some View {
        Group {
            if let selectedId = store.selectedTorrentIds.first,
               let selectedTorrent = store.torrents.first(where: { $0.id == selectedId }) {
                TorrentDetail(store: store, viewContext: viewContext, torrent: binding(for: selectedTorrent, in: store))
                    .id(selectedTorrent.id)
            } else {
                VStack {
                    Spacer()
                    Text("💭")
                        .font(.system(size: 40))
                        .padding(.bottom, 8)
                    Text("Select a Dream")
                        .font(.title2)
                        .foregroundColor(.gray)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// MARK: - Custom Drop Delegate

struct TorrentDropDelegate: DropDelegate {
    @Binding var isDropTargeted: Bool
    @Binding var draggedTorrentInfo: [TorrentInfo]
    let store: Store
    
    func dropEntered(info: DropInfo) {
        isDropTargeted = true
        
        // Count expected torrents first
        let providers = info.itemProviders(for: [.fileURL])
        var parsedInfos: [TorrentInfo] = []
        let group = DispatchGroup()
        let resultsLock = NSLock()
        
        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self) {
                group.enter()
                _ = provider.loadObject(ofClass: URL.self) { url, error in
                    defer { group.leave() }
                    guard let url = url, url.pathExtension.lowercased() == "torrent" else { return }
                    
                    do {
                        var didAccess = false
                        if url.isFileURL {
                            didAccess = url.startAccessingSecurityScopedResource()
                        }
                        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
                        
                        let data = try Data(contentsOf: url)
                        if let torrentInfo = parseTorrentInfo(from: data) {
                            resultsLock.lock()
                            parsedInfos.append(torrentInfo)
                            resultsLock.unlock()
                        }
                    } catch {
                        print("Failed to parse torrent during drag: \(error)")
                    }
                }
            }
        }
        
        // Update UI only when ALL torrents are parsed
        group.notify(queue: .main) {
            draggedTorrentInfo = parsedInfos
        }
    }
    
    func dropExited(info: DropInfo) {
        isDropTargeted = false
        draggedTorrentInfo = []
    }
    
    func performDrop(info: DropInfo) -> Bool {
        isDropTargeted = false
        
        for provider in info.itemProviders(for: [.fileURL]) {
            if provider.canLoadObject(ofClass: URL.self) {
                _ = provider.loadObject(ofClass: URL.self) { url, error in
                    guard let url = url, url.pathExtension.lowercased() == "torrent" else { return }
                    
                    DispatchQueue.global(qos: .userInitiated).async {
                        do {
                            var didAccess = false
                            if url.isFileURL {
                                didAccess = url.startAccessingSecurityScopedResource()
                            }
                            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
                            
                            let data = try Data(contentsOf: url)
                            DispatchQueue.main.async {
                                addTorrentFromFileData(data, store: store)
                            }
                        } catch {
                            print("Failed to read dropped torrent file: \(error)")
                        }
                    }
                }
            }
        }
        
        return true
    }
    
    func validateDrop(info: DropInfo) -> Bool {
        return info.hasItemsConforming(to: [.fileURL])
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
        }) {
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
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(backgroundColor)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(borderColor, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .help(isIncluded ? "Click to exclude '\(label)'" : isExcluded ? "Click to clear filter" : "Click to include '\(label)'")
    }
}

#else
// Empty struct for iOS to reference - this won't be compiled on iOS but provides the type
struct macOSContentView: View {
    let viewContext: NSManagedObjectContext
    let hosts: FetchedResults<Host>
    @ObservedObject var store: Store
    
    var body: some View {
        EmptyView()
    }
}
#endif 
