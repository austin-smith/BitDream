import SwiftUI
import Foundation
import KeychainAccess
import CoreData

#if os(iOS)
struct iOSContentView: View {
    let viewContext: NSManagedObjectContext
    let hosts: FetchedResults<Host>
    @ObservedObject var store: Store
    
    // Add explicit initializer with internal access level
    init(viewContext: NSManagedObjectContext, hosts: FetchedResults<Host>, store: Store) {
        self.viewContext = viewContext
        self.hosts = hosts
        self.store = store
    }

    private var keychain = Keychain(service: "crapshack.BitDream")
    
    // Store the selected torrent IDs instead of a single ID
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
    @State var filterBySelection: [TorrentStatusCalc] = TorrentStatusCalc.allCases
    
    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                StatsHeaderView(store: store)
                
                List(selection: torrentSelection) {
                    torrentRows
                }
                .listStyle(PlainListStyle())
            }
            .navigationTitle("Dreams")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable {
                updateList(store: store, update: {_ in})
            }
            .toolbar {
                serverToolbarItem
                actionToolbarItems
            }
            .onAppear {
                if store.host == nil {
                    setupHost(hosts: hosts, store: store)
                }
            }
            .onChange(of: sortProperty) { oldValue, newValue in
                UserDefaults.standard.sortProperty = newValue
            }
            .onChange(of: sortOrder) { oldValue, newValue in
                UserDefaults.standard.sortOrder = newValue
            }
        } detail: {
            if let selectedTorrent = torrentSelection.wrappedValue.first {
                TorrentDetail(store: store, viewContext: viewContext, torrent: binding(for: selectedTorrent, in: store))
            } else {
                Text("Select a Dream")
            }
        }
        .sheet(isPresented: $store.setup) {
            ServerDetail(store: store, viewContext: viewContext, hosts: hosts, isAddNew: true)
        }
        .sheet(isPresented: $store.editServers) {
            ServerList(store: store, viewContext: viewContext)
                .toolbar {}
        }
        .sheet(isPresented: $store.isShowingAddAlert) {
            AddTorrent(store: store)
        }
        .sheet(isPresented: $store.isError) {
            ErrorDialog(store: store)
                .frame(width: 400, height: 400)
        }
        .sheet(isPresented: $store.showSettings) {
            SettingsView(store: store)
        }
    }
    
    // MARK: - iOS Views
    
    private var torrentRows: some View {
        Group {
            if store.torrents.isEmpty {
                Text("No dreams available")
                    .foregroundColor(.gray)
                    .padding()
            } else {
                let filteredTorrents = store.torrents.filtered(by: filterBySelection)
                let sortedTorrents = sortTorrents(filteredTorrents, by: sortProperty, order: sortOrder)
                ForEach(sortedTorrents, id: \.id) { torrent in
                    TorrentListRow(
                        torrent: binding(for: torrent, in: store),
                        store: store,
                        selectedTorrents: torrentSelection
                    )
                    .tag(torrent)
                    .id(torrent.id)
                    .listRowSeparator(.visible)
                }
            }
        }
    }
    
    // MARK: - Toolbar Items
    
    private var serverToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            Menu {
                Menu {
                    Picker("Server", selection: .init(
                        get: { store.host },
                        set: { host in
                            if let host = host {
                                store.setHost(host: host)
                            }
                        }
                    )) {
                        ForEach(hosts, id: \.self) { host in
                            Text(host.name!)
                                .tag(host as Host?)
                        }
                    }
                } label: {
                    Label("Server", systemImage: "arrow.triangle.2.circlepath")
                }
                Divider()
                Button(action: {store.setup.toggle()}) {
                    Label("Add", systemImage: "plus")
                }
                Button(action: {store.editServers.toggle()}) {
                    Label("Edit", systemImage: "square.and.pencil")
                }
            } label: {
                Image(systemName: "server.rack")
            }
        }
    }
    
    private var actionToolbarItems: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            Menu {
                Menu {
                    Section(header: Text("Include")) {
                        Button("All") {
                            filterBySelection = TorrentStatusCalc.allCases
                        }
                        Button("Downloading") {
                            filterBySelection = [.downloading]
                        }
                        Button("Complete") {
                            filterBySelection = [.complete]
                        }
                        Button("Paused") {
                            filterBySelection = [.paused]
                        }
                    }
                    Section(header: Text("Exclude")) {
                        Button("Complete") {
                            filterBySelection = TorrentStatusCalc.allCases.filter {$0 != .complete}
                        }
                    }
                } label: {
                    Text("Filter By")
                    Image(systemName: "slider.horizontal.3")
                }.environment(\.menuOrder, .fixed)
                
                Menu {
                    // Sort properties
                    ForEach(SortProperty.allCases, id: \.self) { property in
                        Button {
                            sortProperty = property
                        } label: {
                            HStack {
                                Text(property.rawValue)
                                Spacer()
                                if sortProperty == property {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                    
                    Divider()
                    
                    // Sort order
                    Button {
                        sortOrder = .ascending
                    } label: {
                        HStack {
                            Text("Ascending")
                            Spacer()
                            if sortOrder == .ascending {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    
                    Button {
                        sortOrder = .descending
                    } label: {
                        HStack {
                            Text("Descending")
                            Spacer()
                            if sortOrder == .descending {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }.environment(\.menuOrder, .fixed)
                
                Divider()
                
                Button(action: {
                    playPauseAllTorrents(start: false, info: makeConfig(store: store), onResponse: { response in
                        updateList(store: store, update: {_ in})
                    })
                }) {
                    Label("Pause All", systemImage: "pause")
                }
                
                Button(action: {
                    playPauseAllTorrents(start: true, info: makeConfig(store: store), onResponse: { response in
                        updateList(store: store, update: {_ in})
                    })
                }) {
                    Label("Resume All", systemImage: "play")
                }
                
                Divider()
                
                Button(action: {
                    store.isShowingAddAlert.toggle()
                }) {
                    Label("Add Torrent", systemImage: "plus")
                }
                
                Divider()
                
                Button(action: {
                    store.showSettings.toggle()
                }) {
                    Label("Settings", systemImage: "gear")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }
}
#else
// Empty struct for macOS to reference - this won't be compiled on macOS but provides the type
struct iOSContentView: View {
    let viewContext: NSManagedObjectContext
    let hosts: FetchedResults<Host>
    @ObservedObject var store: Store
    
    // Add explicit initializer with internal access level
    init(viewContext: NSManagedObjectContext, hosts: FetchedResults<Host>, store: Store) {
        self.viewContext = viewContext
        self.hosts = hosts
        self.store = store
    }
    
    var body: some View {
        EmptyView()
    }
}
#endif 