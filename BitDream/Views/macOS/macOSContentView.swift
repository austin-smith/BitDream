import SwiftUI
import Foundation
import KeychainAccess
import CoreData

#if os(macOS)
struct macOSContentView: View {
    let viewContext: NSManagedObjectContext
    let hosts: FetchedResults<Host>
    @ObservedObject var store: Store
    
    @State private var selectedTorrentId: Int? = nil
    
    // Computed property to get the selected torrent from the ID
    private var torrentSelection: Binding<Torrent?> {
        createTorrentSelectionBinding(selectedId: $selectedTorrentId, in: store)
    }
    
    @State var sortBySelection: sortBy = UserDefaults.standard.sortBySelection
    @State var filterBySelection: [TorrentStatusCalc] = TorrentStatusCalc.allCases
    @State private var sidebarSelection: SidebarSelection = .allDreams
    @State private var isInspectorVisible: Bool = UserDefaults.standard.inspectorVisibility
    @State private var columnVisibility: NavigationSplitViewVisibility = UserDefaults.standard.sidebarVisibility
    
    // Computed property to get counts for each category
    private func torrentCount(for category: SidebarSelection) -> Int {
        return store.torrents.filtered(by: category.filter).count
    }
    
    // Computed property to get completed torrents count
    private var completedTorrentsCount: Int {
        getCompletedTorrentsCount(in: store)
    }
    
    // Update the app badge
    private func updateAppBadge() {
        updateMacOSAppBadge(count: completedTorrentsCount)
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
                        store.showSettings.toggle()
                    } label: {
                        Label("Settings", systemImage: "gear")
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(SidebarListStyle())
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
                            let sortedTorrents = filteredTorrents.sorted(by: sortBySelection)
                            
                            ForEach(sortedTorrents, id: \.id) { torrent in
                                NavigationLink(value: torrent) {
                                    TorrentListRow(torrent: binding(for: torrent, in: store), store: store)
                                }
                                .tag(torrent)
                                .id(torrent.id)
                                .listRowSeparator(.visible)
                            }
                        }
                    }
                    .navigationDestination(for: Torrent.self) { torrent in
                        TorrentDetail(store: store, viewContext: viewContext, torrent: binding(for: torrent, in: store))
                    }
                    .listStyle(PlainListStyle())
                }
            }
            .navigationTitle("Dreams")
            .toolbar {
                // Content toolbar items
                ToolbarItem(placement: .automatic) {
                    HStack {
                        Text("Sort by:")
                        Picker("", selection: $sortBySelection) {
                            ForEach(sortBy.allCases, id: \.self) { item in
                                Text(item.rawValue).tag(item)
                            }
                        }
                        .labelsHidden()
                    }
                    .help("Sort torrents")
                }
                
                // Add torrent button
                ToolbarItem(placement: .automatic) {
                    Button(action: {
                        store.isShowingAddAlert.toggle()
                    }) {
                        Label("Add Torrent", systemImage: "plus")
                    }
                    .help("Add a new torrent")
                }
                
                // Pause all button
                ToolbarItem(placement: .automatic) {
                    Button(action: {
                        playPauseAllTorrents(start: false, info: makeConfig(store: store), onResponse: { response in
                            updateList(store: store, update: {_ in})
                        })
                    }) {
                        Label("Pause All", systemImage: "pause")
                    }
                    .help("Pause all active torrents")
                }
                
                // Resume all button
                ToolbarItem(placement: .automatic) {
                    Button(action: {
                        playPauseAllTorrents(start: true, info: makeConfig(store: store), onResponse: { response in
                            updateList(store: store, update: {_ in})
                        })
                    }) {
                        Label("Resume All", systemImage: "play")
                    }
                    .help("Resume all paused torrents")
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
        .sheet(isPresented: $store.showSettings) {
            SettingsView()
                .frame(width: 400)
                .fixedSize()
        }
        .onChange(of: sidebarSelection) { oldValue, newValue in
            // Update the filter
            filterBySelection = newValue.filter
            
            // Only clear selection if the selected torrent isn't in the new filtered list
            if let selectedTorrent = torrentSelection.wrappedValue {
                // Break up the complex expression
                let filteredTorrents = store.torrents.filtered(by: newValue.filter)
                let isSelectedTorrentInFilteredList = filteredTorrents.contains { $0.id == selectedTorrent.id }
                
                if !isSelectedTorrentInFilteredList {
                    // Selected torrent is not in the new filtered list, clear selection
                    torrentSelection.wrappedValue = nil
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
        .onChange(of: sortBySelection) { oldValue, newValue in
            UserDefaults.standard.sortBySelection = newValue
        }
    }
    
    // MARK: - macOS Views
    
    private var macOSDetail: some View {
        Group {
            if let selectedTorrent = torrentSelection.wrappedValue {
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
