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
    @State private var showPrefs: Bool = false

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                StatsHeaderView(store: store)

                Group {
                    if store.host != nil, store.connectionStatus != .connected {
                        iOSConnectionBannerView(store: store)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .animation(.default, value: store.connectionStatus)

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
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                Button(action: pauseAllTorrents, label: {
                    Label("Pause All", systemImage: "pause")
                })
                Button(action: resumeAllTorrents, label: {
                    Label("Resume All", systemImage: "play")
                })
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    var actionToolbarItems: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
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

            Button(action: {
                store.showSettings.toggle()
            }, label: {
                Image(systemName: "gear")
            })
        }
    }

    var bottomToolbarItems: some ToolbarContent {
        Group {
            ToolbarItem(placement: .bottomBar) {
                Button {
                    showPrefs.toggle()
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .popover(isPresented: $showPrefs) {
                    prefsPopoverContent
                }
            }

            ToolbarSpacer(.flexible, placement: .bottomBar)
            DefaultToolbarItem(kind: .search, placement: .bottomBar)
            ToolbarSpacer(.flexible, placement: .bottomBar)

            ToolbarItem(placement: .bottomBar) {
                Button(action: {
                    store.isShowingAddAlert.toggle()
                }, label: {
                    Image(systemName: "plus")
                })
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

    var prefsPopoverContent: some View {
        NavigationStack {
            List {
                Section {
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
                    Button("Exclude Complete") {
                        filterBySelection = TorrentStatusCalc.allCases.filter { $0 != .complete }
                    }
                } header: {
                    Text("Filter")
                }

                Section {
                    ForEach(SortProperty.allCases, id: \.self) { property in
                        Button {
                            sortProperty = property
                        } label: {
                            HStack {
                                Text(property.rawValue)
                                Spacer()
                                if sortProperty == property {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.accent)
                                }
                            }
                        }
                    }
                    Picker("Order", selection: $sortOrder) {
                        Text("Ascending").tag(SortOrder.ascending)
                        Text("Descending").tag(SortOrder.descending)
                    }
                    .pickerStyle(.segmented)
                    .listRowSeparator(.hidden)
                } header: {
                    Text("Sort")
                }
            }
            .buttonStyle(.plain)
            .listStyle(.insetGrouped)
            .navigationTitle("Filter & Sort")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showPrefs = false
                    }
                }
            }
        }
        .presentationDragIndicator(.visible)
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
