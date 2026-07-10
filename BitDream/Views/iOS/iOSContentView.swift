import SwiftUI
import Foundation

#if os(iOS)
struct iOSContentView: View {
    let hosts: [Host]
    @ObservedObject var store: TransmissionStore

    // Store the selected torrent IDs
    @State private var selectedTorrentIds: Set<Int> = []

    @State private var sortProperty: SortProperty = UserDefaults.standard.sortProperty
    @State private var sortOrder: SortOrder = UserDefaults.standard.sortOrder
    @State private var filterBySelection: [TorrentStatusCalc] = TorrentStatusCalc.allCases
    @State private var labelFilter = TorrentLabelFilter()
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
        .onChange(of: store.availableLabels) { _, availableLabels in
            reconcileSelectedLabels(with: availableLabels)
        }
        .onChange(of: store.host?.serverID) { _, _ in
            labelFilter.clear()
            selectedTorrentIds.removeAll()
        }
        .sheet(isPresented: $store.setup, content: {
            iOSServerEditor(store: store, hosts: hosts, host: nil)
        })
        .sheet(isPresented: $store.editServers, content: {
            iOSServerList(hosts: hosts, store: store)
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
    var displayedTorrents: [Torrent] {
        filterAndSortTorrents(
            store.torrents,
            options: TorrentDisplayOptions(
                statusFilter: filterBySelection,
                labelFilter: labelFilter,
                searchText: searchText,
                sortProperty: sortProperty,
                sortOrder: sortOrder
            )
        )
    }

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
                ForEach(displayedTorrents, id: \.id) { torrent in
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
                Button(action: { store.setup.toggle() }, label: {
                    Label("Add Server", systemImage: "plus")
                })
                Button(action: { store.editServers.toggle() }, label: {
                    Label("Edit Servers", systemImage: "square.and.pencil")
                })
                Section("Servers") {
                    ForEach(hosts, id: \.serverID) { host in
                        Button {
                            store.setHost(host: host)
                        } label: {
                            Label(
                                host.name ?? "Unnamed Server",
                                systemImage: store.host?.serverID == host.serverID
                                    ? "checkmark.circle.fill"
                                    : "circle"
                            )
                        }
                    }
                }
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
                    iOSFilterAndSortView(
                        statusFilter: $filterBySelection,
                        labelFilter: $labelFilter,
                        sortProperty: $sortProperty,
                        sortOrder: $sortOrder,
                        availableLabels: store.availableLabels,
                        labelCounts: availableLabelCounts,
                        noLabelCount: store.torrents.count(where: { $0.labels.isEmpty })
                    )
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

    func reconcileSelectedLabels(with availableLabels: [String]) {
        var reconciledFilter = labelFilter
        reconciledFilter.reconcile(with: availableLabels)

        if reconciledFilter != labelFilter {
            labelFilter = reconciledFilter
        }
    }

    var availableLabelCounts: [String: Int] {
        Dictionary(
            uniqueKeysWithValues: store.availableLabels.map { label in
                (label, store.torrentCount(for: label))
            }
        )
    }
}
#endif
