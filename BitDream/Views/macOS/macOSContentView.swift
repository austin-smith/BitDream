import SwiftUI
import Foundation
import KeychainAccess
import CoreData

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
    
    @State private var selectedTorrentIds: Set<Int> = []
    
    // Computed property to get the selected torrents from the IDs
    private var torrentSelection: Binding<Set<Torrent>> {
        Binding<Set<Torrent>>(
            get: {
                Set(selectedTorrentIds.compactMap { id in
                    store.torrents.first { $0.id == id }
                })
            },
            set: { newSelection in
                selectedTorrentIds = Set(newSelection.map { $0.id })
            }
        )
    }
    
    @State var sortProperty: SortProperty = UserDefaults.standard.sortProperty
    @State var sortOrder: SortOrder = UserDefaults.standard.sortOrder
    @State private var filterBySelection: [TorrentStatusCalc] = TorrentStatusCalc.allCases
    @State private var sidebarSelection: SidebarSelection = .allDreams
    @State private var isInspectorVisible: Bool = UserDefaults.standard.inspectorVisibility
    @State private var columnVisibility: NavigationSplitViewVisibility = UserDefaults.standard.sidebarVisibility
    @State private var searchText: String = ""
    @State private var includedLabels: Set<String> = []
    @State private var excludedLabels: Set<String> = []
    @State private var isCompactMode: Bool = UserDefaults.standard.torrentListCompactMode
    @AppStorage("showContentTypeIcons") private var showContentTypeIcons: Bool = true
    
    // Helper function to extract label query from "label:something" syntax
    private func extractLabelQuery(from query: String) -> String {
        let colonIndex = query.firstIndex(of: ":")
        return colonIndex != nil ? String(query[query.index(after: colonIndex!)...]) : ""
    }
    
    // Helper function to check if a torrent matches the search query and label filters
    private func torrentMatchesSearch(_ torrent: Torrent, query: String) -> Bool {
        // Check label filters first
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
        
        // Check for label-specific search syntax: "label:tv"
        if query.lowercased().hasPrefix("label:") {
            let labelQuery = extractLabelQuery(from: query)
            if labelQuery.isEmpty {
                // Show all torrents with any labels
                return !torrent.labels.isEmpty
            }
            return torrent.labels.contains { label in
                label.localizedCaseInsensitiveContains(labelQuery)
            }
        }
        
        // Search in name
        if torrent.name.localizedCaseInsensitiveContains(query) {
            return true
        }
        
        // Search in labels
        return torrent.labels.contains { label in
            label.localizedCaseInsensitiveContains(query)
        }
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
    
    // Computed property for navigation subtitle
    private var navigationSubtitle: String {
        let count = torrentCount(for: sidebarSelection)
        var subtitle = "\(count) dream\(count == 1 ? "" : "s")"
        
        // Add label filter indicators
        let totalFilters = includedLabels.count + excludedLabels.count
        if totalFilters > 0 {
            subtitle += " • \(totalFilters) label filter\(totalFilters == 1 ? "" : "s")"
        }
        
        return subtitle
    }
    
    var body: some View {       
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // Sidebar
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
                            selectedTorrentIds.removeAll()
                            // Force refresh data when changing host
                            updateList(store: store, update: { _ in })
                        } label: {
                            HStack {
                                Label(host.name!, systemImage: "server.rack")
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
        } detail: {
            // Content (middle pane)
            VStack(spacing: 0) {
                StatsHeaderView(store: store)
                
                VStack {
                    // Torrent list
                    if store.torrents.isEmpty {
                        VStack {
                            Spacer()
                            Text("No dreams available")
                                .foregroundColor(.gray)
                                .padding()
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
                                selection: $selectedTorrentIds,
                                store: store,
                                showContentTypeIcons: showContentTypeIcons
                            )
                        } else {
                            // Expanded list view
                            List(selection: torrentSelection) {
                                ForEach(sortedTorrents, id: \.id) { torrent in
                                    macOSTorrentListExpanded(
                                        torrent: binding(for: torrent, in: store),
                                        store: store,
                                        selectedTorrents: torrentSelection,
                                        showContentTypeIcons: showContentTypeIcons
                                    )
                                    .tag(torrent)
                                    .listRowSeparator(.visible)
                                }
                            }
                            .listStyle(.plain)
                            .tint(themeManager.accentColor) // Apply accent color to list selection
                        }
                    }
                }
            }
            .navigationTitle(sidebarSelection.rawValue)
            .navigationSubtitle(navigationSubtitle)
            .searchable(text: $searchText, placement: .toolbar, prompt: "Search torrents") {
                if !store.availableLabels.isEmpty {
                    Section("Filter by Labels") {
                        ForEach(store.availableLabels, id: \.self) { label in
                            Button(action: {
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
                        
                        if !includedLabels.isEmpty || !excludedLabels.isEmpty {
                            Divider()
                            Button("Clear filters") {
                                includedLabels.removeAll()
                                excludedLabels.removeAll()
                            }
                        }
                    }
                }
            }
            .toolbar {              
                // Content toolbar items
                ToolbarItem(placement: .automatic) {
                    Menu {
                        // Sort properties
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
                        
                        // Sort order
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
                    } label: {
                        Label("Sort", systemImage: "arrow.up.arrow.down.circle")
                    }
                }

                // Add torrent button
                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        store.isShowingAddAlert.toggle()
                    }) {
                        Label("Add Torrent", systemImage: "plus")
                    }
                    .help("Add a new torrent")
                }
                
                // // Pause all button
                // ToolbarItem(placement: .automatic) {
                //     Button(action: {
                //         playPauseAllTorrents(start: false, info: makeConfig(store: store), onResponse: { response in
                //             updateList(store: store, update: {_ in})
                //         })
                //     }) {
                //         Label("Pause All", systemImage: "pause")
                //     }
                //     .help("Pause all active torrents")
                // }
                
                // // Resume all button
                // ToolbarItem(placement: .automatic) {
                //     Button(action: {
                //         playPauseAllTorrents(start: true, info: makeConfig(store: store), onResponse: { response in
                //             updateList(store: store, update: {_ in})
                //         })
                //     }) {
                //         Label("Resume All", systemImage: "play")
                //     }
                //     .help("Resume all paused torrents")
                // }
                
                // Add spacer between sort and view mode buttons
                ToolbarItem(placement: .automatic) {
                    Spacer()
                }
                
                // Toggle compact mode button
                ToolbarItem(placement: .automatic) {
                    Button(action: {
                        withAnimation {
                            isCompactMode.toggle()
                            UserDefaults.standard.torrentListCompactMode = isCompactMode
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
            .inspector(isPresented: $isInspectorVisible) {
                macOSDetail
                    .inspectorColumnWidth(min: 350, ideal: 400, max: 500)
            }
        }
        .sheet(isPresented: $store.setup) {
            ServerDetail(store: store, viewContext: viewContext, hosts: hosts, isAddNew: true)
        }
        .sheet(isPresented: $store.editServers) {
            ServerList(store: store, viewContext: viewContext)
        }
        .sheet(isPresented: $store.isShowingAddAlert) {
            AddTorrent(store: store)
        }
        .sheet(isPresented: $store.isError) {
            ErrorDialog(store: store)
                .frame(width: 400, height: 400)
        }
        .accentColor(themeManager.accentColor) // Apply accent color to the entire view
        .onChange(of: sidebarSelection) { oldValue, newValue in
            // Update the filter
            filterBySelection = newValue.filter
            
            // Only clear selection if the selected torrent isn't in the new filtered list
            if let selectedTorrent = torrentSelection.wrappedValue.first {
                // Break up the complex expression
                let filteredTorrents = store.torrents.filtered(by: newValue.filter)
                    .filter { torrentMatchesSearch($0, query: searchText) }
                let isSelectedTorrentInFilteredList = filteredTorrents.contains { $0.id == selectedTorrent.id }
                
                if !isSelectedTorrentInFilteredList {
                    // Selected torrent is not in the new filtered list, clear selection
                    torrentSelection.wrappedValue.removeAll()
                }
            }
            
            print("\(newValue.rawValue) selected")
        }
        .onReceive(store.$torrents) { _ in
            updateAppBadge()
        }
        .onAppear {
            setupHost(hosts: hosts, store: store)
            updateAppBadge()
        }
        .onChange(of: columnVisibility) { oldValue, newValue in
            UserDefaults.standard.sidebarVisibility = newValue
        }
        .onChange(of: isInspectorVisible) { oldValue, newValue in
            UserDefaults.standard.inspectorVisibility = newValue
        }
        .onChange(of: sortProperty) { oldValue, newValue in
            UserDefaults.standard.sortProperty = newValue
        }
        .onChange(of: sortOrder) { oldValue, newValue in
            UserDefaults.standard.sortOrder = newValue
        }
        .onChange(of: searchText) { oldValue, newValue in
            // Check if user typed label: syntax and auto-select matching labels
            if newValue.lowercased().hasPrefix("label:") {
                let labelQuery = extractLabelQuery(from: newValue)
                
                // Clear any previous auto-selections that don't match exactly anymore
                let currentExactMatches = Set(store.availableLabels.filter { label in
                    !labelQuery.isEmpty && label.lowercased() == labelQuery.lowercased()
                })
                
                // Remove any included labels that are no longer exact matches
                includedLabels = includedLabels.intersection(currentExactMatches)
                
                if !labelQuery.isEmpty {
                    // Only auto-select if there's an exact match
                    let exactMatch = store.availableLabels.first { label in
                        label.lowercased() == labelQuery.lowercased()
                    }
                    
                    // Auto-include only exact matches
                    if let exactLabel = exactMatch {
                        if !includedLabels.contains(exactLabel) {
                            includedLabels.insert(exactLabel)
                            excludedLabels.remove(exactLabel)
                        }
                    }
                }
            } else {
                // If not using label: syntax, clear any auto-selections
                // (Keep only manually selected ones - but we don't track that, so clear all for now)
                if oldValue.lowercased().hasPrefix("label:") && !newValue.lowercased().hasPrefix("label:") {
                    includedLabels.removeAll()
                    excludedLabels.removeAll()
                }
            }
            
            // Only clear selection if the selected torrent isn't in the new filtered list
            if let selectedTorrent = torrentSelection.wrappedValue.first {
                // Check if the selected torrent matches the search filter
                let matchesSearch = torrentMatchesSearch(selectedTorrent, query: searchText)
                
                // Check if the selected torrent matches the category filter
                let filteredTorrents = store.torrents.filtered(by: filterBySelection)
                let isSelectedTorrentInFilteredList = filteredTorrents.contains { $0.id == selectedTorrent.id }
                
                if !matchesSearch || !isSelectedTorrentInFilteredList {
                    // Selected torrent is not in the new filtered list, clear selection
                    torrentSelection.wrappedValue.removeAll()
                }
            }
        }
    }
    
    // MARK: - macOS Views
    
    private var macOSDetail: some View {
        Group {
            if let selectedTorrent = torrentSelection.wrappedValue.first {
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
