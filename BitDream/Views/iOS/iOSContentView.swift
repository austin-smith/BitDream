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
    
    @State var torrentSelection: Torrent?
    @State var sortBySelection: sortBy = .name
    @State var filterBySelection: [TorrentStatusCalc] = TorrentStatusCalc.allCases
    
    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                StatsHeaderView(store: store)
                
                List(selection: $torrentSelection) {
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
                setupHost(hosts: hosts, store: store)
            }
        } detail: {
            if let selectedTorrent = torrentSelection {
                TorrentDetail(store: store, viewContext: viewContext, torrent: binding(for: selectedTorrent, in: store))
            } else {
                Text("select a dream")
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
        .sheet(isPresented: $store.isShowingTransferFiles) {
            FileSelectDialog(store: store)
                .frame(width: 400, height: 500)
        }
        .sheet(isPresented: $store.isError) {
            ErrorDialog(store: store)
                .frame(width: 400, height: 400)
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
                ForEach(store.torrents
                        .filtered(by: filterBySelection)
                        .sorted(by: sortBySelection), id: \.id) { torrent in
                    NavigationLink {
                        TorrentDetail(store: store, viewContext: viewContext, torrent: binding(for: torrent, in: store))
                    } label: {
                        TorrentListRow(torrent: binding(for: torrent, in: store), store: store)
                    }
                    .tag(torrent)
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
                    ForEach(hosts, id: \.self) { host in
                        Button(action: {
                            store.setHost(host: host)
                        }) {
                            Label(host.name!, systemImage: host == store.host ? "checkmark" : "")
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
                    Picker("Sort By", selection: $sortBySelection) {
                        ForEach(sortBy.allCases, id: \.self) { item in
                            Text(item.rawValue)
                        }
                        .pickerStyle(.automatic)
                    }
                } label: {
                    Text("Sort By")
                    Image(systemName: "arrow.up.arrow.down")
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