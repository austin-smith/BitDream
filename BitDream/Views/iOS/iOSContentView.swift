import SwiftUI
import Foundation
import SwiftData

#if os(iOS)
struct iOSContentView: View {
    let modelContext: ModelContext
    let hosts: [Host]
    @ObservedObject var store: TransmissionStore

    // Add explicit initializer with internal access level
    init(modelContext: ModelContext, hosts: [Host], store: TransmissionStore) {
        self.modelContext = modelContext
        self.hosts = hosts
        self.store = store
    }

    // Store the selected torrent IDs
    @State private var selectedTorrentIds: Set<Int> = []

    @State var sortProperty: SortProperty = UserDefaults.standard.sortProperty
    @State var sortOrder: SortOrder = UserDefaults.standard.sortOrder
    @State var filterBySelection: [TorrentStatusCalc] = TorrentStatusCalc.allCases
    @AppStorage(UserDefaultsKeys.showContentTypeIcons) private var showContentTypeIcons: Bool = true
    @State private var searchText: String = ""

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                StatsHeaderView(store: store)

                // Show list regardless of connection status
                List(selection: $selectedTorrentIds) {
                    torrentRows
                }
                .listStyle(PlainListStyle())
            }
            .navigationTitle("Dreams")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable {
                await store.refreshNow()
            }
            .searchable(text: $searchText, prompt: "Search torrents")
            .toolbar {
                serverToolbarItem
                actionToolbarItems
                bottomToolbarItems
            }
            .onChange(of: sortProperty) { _, newValue in
                UserDefaults.standard.sortProperty = newValue
            }
            .onChange(of: sortOrder) { _, newValue in
                UserDefaults.standard.sortOrder = newValue
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
                Text(store.lastErrorMessage)
            }
        } detail: {
            if let selectedTorrent = selectedTorrentsSet.first {
                TorrentDetail(store: store, torrent: selectedTorrent)
            } else {
                Text("Select a Dream")
            }
        }
        .sheet(isPresented: $store.setup, content: {
            ServerDetail(store: store, modelContext: modelContext, hosts: hosts, isAddNew: true)
        })
        .sheet(isPresented: $store.editServers, content: {
            ServerList(store: store, modelContext: modelContext, hosts: hosts)
                .toolbar {}
        })
        .sheet(isPresented: $store.isShowingAddAlert, content: {
            AddTorrent(store: store)
        })
        .sheet(isPresented: $store.isError, content: {
            ErrorDialog(store: store)
                .frame(width: 400, height: 400)
        })
        .sheet(isPresented: $store.showSettings, content: {
            SettingsView(store: store)
        })
    }
}

private extension iOSContentView {
    var selectedTorrentsSet: Set<Torrent> {
        Set(selectedTorrentIds.compactMap { id in
            store.torrents.first { $0.id == id }
        })
    }

    var torrentRows: some View {
        Group {
            if store.torrents.isEmpty {
                Text("No dreams available")
                    .foregroundColor(.gray)
                    .padding()
            } else {
                let filteredByStatus = store.torrents.filtered(by: filterBySelection)
                let filteredBySearch = searchText.isEmpty
                    ? filteredByStatus
                    : filteredByStatus.filter { torrent in
                        torrent.name.localizedCaseInsensitiveContains(searchText)
                    }
                let sortedTorrents = sortTorrents(filteredBySearch, by: sortProperty, order: sortOrder)
                ForEach(sortedTorrents, id: \.id) { torrent in
                    TorrentListRow(
                        torrent: torrent,
                        store: store,
                        selectedTorrents: selectedTorrentsSet,
                        showContentTypeIcons: showContentTypeIcons
                    )
                    .tag(torrent.id)
                    .listRowSeparator(.visible)
                }
            }
        }
    }

    var serverToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            Menu {
                serverSelectionMenu
                Divider()
                Button(action: { store.setup.toggle() }, label: {
                    Label("Add", systemImage: "plus")
                })
                Button(action: { store.editServers.toggle() }, label: {
                    Label("Edit", systemImage: "square.and.pencil")
                })
            } label: {
                Image(systemName: "server.rack")
            }
        }
    }

    var actionToolbarItems: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            Menu {
                filterMenu
                sortMenu
                Divider()
                Button(action: pauseAllTorrents, label: {
                    Label("Pause All", systemImage: "pause")
                })
                Button(action: resumeAllTorrents, label: {
                    Label("Resume All", systemImage: "play")
                })
                Divider()
                Button(action: {
                    store.showSettings.toggle()
                }, label: {
                    Label("Settings", systemImage: "gear")
                })
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    var bottomToolbarItems: some ToolbarContent {
        Group {
            DefaultToolbarItem(kind: .search, placement: .bottomBar)
            ToolbarSpacer(.flexible, placement: .bottomBar)

            ToolbarItem(placement: .bottomBar) {
                Button(action: {
                    store.isShowingAddAlert.toggle()
                }, label: {
                    Label("Add Torrent", systemImage: "plus")
                })
                .foregroundStyle(.tint)
            }
        }
    }

    var serverSelectionMenu: some View {
        Menu {
            Picker("Server", selection: .init(
                get: { store.host },
                set: { host in
                    if let host {
                        store.setHost(host: host)
                    }
                }
            )) {
                ForEach(hosts, id: \.serverID) { host in
                    Text(host.name ?? "Unnamed Server")
                        .tag(host as Host?)
                }
            }
        } label: {
            Label("Server", systemImage: "arrow.triangle.2.circlepath")
        }
    }

    var filterMenu: some View {
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
                    filterBySelection = TorrentStatusCalc.allCases.filter { $0 != .complete }
                }
            }
        } label: {
            Text("Filter By")
            Image(systemName: "slider.horizontal.3")
        }
        .environment(\.menuOrder, .fixed)
    }

    var sortMenu: some View {
        Menu {
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
        }
        .environment(\.menuOrder, .fixed)
    }

    func pauseAllTorrents() {
        performTransmissionDebugAction(
            .pauseAllTorrents,
            store: store,
            operation: { try await store.pauseAllTorrents() }
        )
    }

    func resumeAllTorrents() {
        performTransmissionDebugAction(
            .resumeAllTorrents,
            store: store,
            operation: { try await store.resumeAllTorrents() }
        )
    }
}
#endif
