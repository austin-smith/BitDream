import SwiftUI
import Foundation

#if os(iOS)
struct iOSContentView: View {
    let hosts: [Host]
    @ObservedObject var store: TransmissionStore
    private let userDefaults: UserDefaults

    @State private var torrentPath: [Int] = []

    @State private var sortProperty: SortProperty
    @State private var sortOrder: SortOrder
    @State private var filterBySelection: [TorrentStatusCalc] = TorrentStatusCalc.allCases
    @State private var labelFilter = TorrentLabelFilter()
    @AppStorage(UserDefaultsKeys.showContentTypeIcons) private var showContentTypeIcons = AppDefaults.showContentTypeIcons
    @State private var searchText: String = ""
    @State private var showPrefs: Bool = false

    init(hosts: [Host], store: TransmissionStore, userDefaults: UserDefaults = .standard) {
        self.hosts = hosts
        self.store = store
        self.userDefaults = userDefaults
        _sortProperty = State(initialValue: userDefaults.sortProperty)
        _sortOrder = State(initialValue: userDefaults.sortOrder)
        _showContentTypeIcons = AppStorage(
            wrappedValue: AppDefaults.showContentTypeIcons,
            UserDefaultsKeys.showContentTypeIcons,
            store: userDefaults
        )
    }

    var body: some View {
        NavigationStack(path: $torrentPath) {
            torrentListScreen
                .navigationDestination(for: Int.self) { torrentID in
                    if let torrent = store.torrents.first(where: { $0.id == torrentID }) {
                        TorrentDetail(store: store, torrent: torrent)
                    }
                }
        }
        .onChange(of: store.availableLabels) { _, availableLabels in
            reconcileSelectedLabels(with: availableLabels)
        }
        .onChange(of: store.host?.serverID) { _, _ in
            labelFilter.clear()
            torrentPath.removeAll()
        }
        .onChange(of: store.torrents.map(\.id)) { _, torrentIDs in
            reconcileNavigationPath(with: torrentIDs)
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
    var torrentListScreen: some View {
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
            torrentList
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
            userDefaults.sortProperty = newValue
        }
        .onChange(of: sortOrder) { _, newValue in
            userDefaults.sortOrder = newValue
        }
    }

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

    var torrentList: some View {
        List {
            torrentRows
        }
    }

    var torrentRows: some View {
        Group {
            if store.torrents.isEmpty {
                emptyTorrentList
            } else {
                ForEach(displayedTorrents, id: \.id) { torrent in
                    torrentRow(for: torrent)
                        .listRowSeparator(.visible)
                }
            }
        }
    }

    var emptyTorrentList: some View {
        Text("No dreams available")
            .foregroundColor(.gray)
            .padding()
    }

    func torrentRow(for torrent: Torrent) -> some View {
        iOSTorrentListRow(
            torrent: torrent,
            store: store,
            showContentTypeIcons: showContentTypeIcons
        )
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
            Button {
                store.editServers = true
            } label: {
                Image(systemName: "server.rack")
            }
            .accessibilityLabel("Servers")

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
                    Label(
                        "Filter and Sort",
                        systemImage: hasActiveFilters
                            ? "line.3.horizontal.decrease.circle.fill"
                            : "line.3.horizontal.decrease.circle"
                    )
                }
                .accessibilityValue(hasActiveFilters ? "Active" : "Inactive")
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
                    Label("Add Torrent", systemImage: "plus")
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

    func reconcileNavigationPath(with torrentIDs: [Int]) {
        let availableTorrentIDs = Set(torrentIDs)
        torrentPath.removeAll { !availableTorrentIDs.contains($0) }
    }

    var hasActiveFilters: Bool {
        filterBySelection != TorrentStatusCalc.allCases || labelFilter.isActive
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

#if os(iOS) && DEBUG
#Preview("iOS Content") {
    PreviewContainer { environment in
        iOSContentView(
            hosts: environment.hosts,
            store: environment.store,
            userDefaults: environment.userDefaults
        )
    }
}
#endif
