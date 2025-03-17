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
    
    // Helper function to check if a torrent matches the search query
    private func torrentMatchesSearch(_ torrent: Torrent, query: String) -> Bool {
        if query.isEmpty {
            return true
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
        return "\(count) dream\(count == 1 ? "" : "s")"
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
                    List(selection: torrentSelection) {
                        if store.torrents.isEmpty {
                            Text("No dreams available")
                                .foregroundColor(.gray)
                                .padding()
                        } else {
                            // Break up the complex expression into steps
                            let filteredTorrents = store.torrents.filtered(by: filterBySelection)
                                .filter { torrent in
                                    torrentMatchesSearch(torrent, query: searchText)
                                }
                            let sortedTorrents = sortTorrents(filteredTorrents, by: sortProperty, order: sortOrder)
                            
                            ForEach(sortedTorrents, id: \.id) { torrent in
                                TorrentListRow(
                                    torrent: binding(for: torrent, in: store),
                                    store: store,
                                    selectedTorrents: torrentSelection
                                )
                                .tag(torrent)
                                .listRowSeparator(.visible)
                            }
                        }
                    }
                    .listStyle(.inset)
                    .tint(themeManager.accentColor) // Apply accent color to list selection
                }
            }
            .navigationTitle(sidebarSelection.rawValue)
            .navigationSubtitle(navigationSubtitle)
            .searchable(text: $searchText, placement: .toolbar)
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
                
                // Add spacer between sort and inspector buttons
                ToolbarItem(placement: .automatic) {
                    Spacer()
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
        .tint(themeManager.accentColor) // Apply tint to NavigationSplitView
        .accentColor(themeManager.accentColor) // Apply accent color to the entire view
        .onChange(of: sidebarSelection) { oldValue, newValue in
            // Update the filter
            filterBySelection = newValue.filter
            
            // Only clear selection if the selected torrent isn't in the new filtered list
            if let selectedTorrent = torrentSelection.wrappedValue.first {
                // Break up the complex expression
                let filteredTorrents = store.torrents.filtered(by: newValue.filter)
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
