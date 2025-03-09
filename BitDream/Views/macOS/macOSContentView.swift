import SwiftUI
import Foundation
import KeychainAccess
import CoreData

#if os(macOS)
struct macOSContentView: View {
    let viewContext: NSManagedObjectContext
    let hosts: FetchedResults<Host>
    @ObservedObject var store: Store
    
    @State var torrentSelection: Torrent?
    @State var sortBySelection: sortBy = .name
    @State var filterBySelection: [TorrentStatusCalc] = TorrentStatusCalc.allCases
    @State private var sidebarSelection: SidebarSelection = .allDreams
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // Sidebar
            List(selection: $sidebarSelection) {
                Section("Library") {
                    ForEach(SidebarSelection.allCases) { item in
                        Label(item.rawValue, systemImage: item.icon)
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
                }
            }
            .listStyle(SidebarListStyle())
        } content: {
            // Content (middle pane)
            VStack(spacing: 0) {
                StatsHeaderView(store: store)
                
                VStack(spacing: 0) {
                    // Debug text to show torrent count
                    Text("Torrents: \(store.torrents.count)")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.top, 4)
                    
                    // Torrent list
                    List(selection: $torrentSelection) {
                        if store.torrents.isEmpty {
                            Text("No dreams available")
                                .foregroundColor(.gray)
                                .padding()
                        } else {
                            ForEach(store.torrents
                                    .filtered(by: filterBySelection)
                                    .sorted(by: sortBySelection), id: \.id) { torrent in
                                NavigationLink(value: torrent) {
                                    TorrentListRow(torrent: binding(for: torrent, in: store), store: store)
                                }
                                .tag(torrent)
                                .listRowSeparator(.visible)
                            }
                        }
                    }
                    .navigationDestination(for: Torrent.self) { torrent in
                        TorrentDetail(store: store, viewContext: viewContext, torrent: binding(for: torrent, in: store))
                    }
                    .listStyle(PlainListStyle())
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Dreams")
            .toolbar {
                // Content toolbar items
                ToolbarItem(placement: .automatic) {
                    Menu {
                        ForEach(sortBy.allCases, id: \.self) { item in
                            Button(action: {
                                sortBySelection = item
                            }) {
                                Label(item.rawValue, systemImage: sortBySelection == item ? "checkmark" : "")
                            }
                        }
                    } label: {
                        Label("Sort", systemImage: "arrow.up.arrow.down")
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
            }
            .refreshable {
                updateList(store: store, update: {_ in})
            }
        } detail: {
            // Detail (right pane)
            macOSDetail
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
        .sheet(isPresented: $store.isShowingTransferFiles) {
            FileSelectDialog(store: store)
                .frame(width: 400, height: 500)
        }
        .sheet(isPresented: $store.isError) {
            ErrorDialog(store: store)
                .frame(width: 400, height: 400)
        }
        .onChange(of: sidebarSelection) { newValue in
            // Update the filter
            filterBySelection = newValue.filter
            
            // Only clear selection if the selected torrent isn't in the new filtered list
            if let selectedTorrent = torrentSelection {
                let filteredTorrents = store.torrents.filtered(by: newValue.filter)
                let isSelectedTorrentInFilteredList = filteredTorrents.contains { $0.id == selectedTorrent.id }
                
                if !isSelectedTorrentInFilteredList {
                    // Selected torrent is not in the new filtered list, clear selection
                    torrentSelection = nil
                }
            }
            
            print("\(newValue.rawValue) selected")
        }
        .onAppear {
            setupHost(hosts: hosts, store: store)
        }
    }
    
    // MARK: - macOS Views
    
    private var macOSDetail: some View {
        Group {
            if let selectedTorrent = torrentSelection {
                TorrentDetail(store: store, viewContext: viewContext, torrent: binding(for: selectedTorrent, in: store))
                    .id(selectedTorrent.id)
            } else {
                VStack {
                    Spacer()
                    Text("💭")
                        .font(.system(size: 40))
                        .padding(.bottom, 8)
                    Text("select a dream")
                        .font(.title2)
                        .foregroundColor(.gray)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.controlBackgroundColor))
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