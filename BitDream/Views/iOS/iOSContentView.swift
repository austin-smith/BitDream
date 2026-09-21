import SwiftUI
import Foundation

#if os(iOS)
struct iOSContentView: View {
    @Environment(\.hapticFeedback) private var hapticFeedback
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let hosts: [Host]
    @ObservedObject var store: TransmissionStore
    private let userDefaults: UserDefaults

    @State private var navigation = iOSNavigationState()
    @State private var detailState = iOSTorrentDetailState()
    @State private var isSidebarOpen = false

    @State private var sortProperty: SortProperty
    @State private var sortOrder: SortOrder
    @State private var labelFilter = TorrentLabelFilter()
    @AppStorage(UserDefaultsKeys.showContentTypeIcons) private var showContentTypeIcons = AppDefaults.showContentTypeIcons
    @State private var searchText: String = ""
    @State private var isStatisticsPresented = false
    @State private var showPrefs: Bool = false
    @State private var serverToEdit: Host?

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
        iOSSidebarTray(isOpen: $isSidebarOpen, allowsOpeningGesture: navigation.stackPath.isEmpty) {
            sidebar
        } content: {
            NavigationStack(path: Binding(
                get: { navigation.stackPath },
                set: { navigation.setStackPath($0) }
            )) {
                torrentListScreen
                    .navigationDestination(for: iOSTorrentDetailRoute.self) { route in
                        torrentDestination(route)
                    }
            }
            .inspector(isPresented: Binding(
                get: { navigation.isInspectorPresented },
                set: { navigation.setInspectorPresented($0) }
            )) {
                torrentInspector
            }
        }
        .modifier(IOSTorrentDetailPresentation(store: store, torrent: selectedTorrent, state: detailState))
        .onChange(of: horizontalSizeClass, initial: true) { _, sizeClass in
            navigation.presentation = sizeClass == .regular ? .inspector : .stack
        }
        .onChange(of: store.availableLabels) { _, availableLabels in
            reconcileSelectedLabels(with: availableLabels)
        }
        .onChange(of: store.host?.serverID) { _, _ in
            labelFilter.clear()
            navigation.clearTorrentSelection()
        }
        .onChange(of: store.torrents.map(\.id)) { _, torrentIDs in
            navigation.reconcileTorrentSelection(availableIDs: torrentIDs)
        }
        .onChange(of: navigation.selectedTorrentID) { _, selectedID in
            if selectedID != nil {
                hapticFeedback.play(.selectionChanged)
            } else {
                detailState = iOSTorrentDetailState()
            }
        }
        .onChange(of: navigation.sidebarSelection) { _, _ in
            navigation.clearTorrentSelection()
            isSidebarOpen = false
            hapticFeedback.play(.selectionChanged)
        }
        .onChange(of: isSidebarOpen) {
            hapticFeedback.play(.actionTriggered)
        }
        .sheet(isPresented: $store.setup, content: {
            iOSServerEditor(store: store, hosts: hosts, host: nil)
        })
        .sheet(isPresented: $store.editServers, content: {
            iOSServerList(hosts: hosts, store: store)
        })
        .sheet(item: $serverToEdit) { host in
            iOSServerEditor(store: store, hosts: hosts, host: host)
        }
        .sheet(isPresented: $store.isShowingAddAlert, content: {
            AddTorrent(store: store)
        })
        .sheet(isPresented: $store.isError, content: {
            ErrorDialog(store: store)
                .presentationDetents([.medium, .large])
        })
        .sheet(isPresented: $store.showSettings, content: {
            SettingsView(store: store)
        })
        .sheet(isPresented: $isStatisticsPresented) {
            NavigationStack {
                iOSStatisticsView(store: store)
            }
            .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - Tray and Inspector

private extension iOSContentView {
    var sidebarSelection: SidebarSelection {
        navigation.sidebarSelection
    }

    var selectedTorrent: Torrent? {
        store.torrents.first { $0.id == navigation.selectedTorrentID }
    }

    var sidebar: some View {
        iOSSidebarView(
            hosts: hosts,
            sidebarSelection: Binding(
                get: { navigation.sidebarSelection },
                set: {
                    navigation.sidebarSelection = $0
                    isSidebarOpen = false
                }
            ),
            selectedHostID: store.host?.serverID,
            torrentCount: { torrentCount(for: $0) },
            onSelectHost: { host in
                store.setHost(host: host)
                navigation.clearTorrentSelection()
                isSidebarOpen = false
            },
            onEditServer: { host in
                hapticFeedback.play(.actionTriggered)
                serverToEdit = host
            },
            onAddServer: {
                hapticFeedback.play(.actionTriggered)
                store.setup = true
            },
            onManageServers: {
                hapticFeedback.play(.actionTriggered)
                store.editServers = true
            },
            onOpenSettings: {
                hapticFeedback.play(.actionTriggered)
                store.showSettings = true
            }
        )
    }

    var torrentInspector: some View {
        NavigationStack(path: Binding(
            get: { navigation.detailPath },
            set: { navigation.setInspectorPath($0) }
        )) {
            torrentDestination(.overview)
                .navigationDestination(for: iOSTorrentDetailRoute.self) { route in
                    torrentDestination(route)
                }
        }
        .inspectorColumnWidth(min: 300, ideal: 380, max: 500)
        .presentationDetents([.large])
    }

    @ViewBuilder
    func torrentDestination(_ route: iOSTorrentDetailRoute) -> some View {
        if let torrent = selectedTorrent {
            iOSTorrentDetail(store: store, torrent: torrent, state: detailState, route: route)
                .id(torrent.id)
                .toolbar {
                    if navigation.presentation == .inspector {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close Details", systemImage: "xmark") {
                                navigation.hideDetails()
                                hapticFeedback.play(.actionTriggered)
                            }
                        }
                    }
                }
        }
    }

    func selectTorrent(_ id: Int) {
        if navigation.selectedTorrentID != id {
            detailState = iOSTorrentDetailState()
        }
        navigation.selectTorrent(id)
    }
}

// MARK: - Torrent List Screen

private extension iOSContentView {
    var torrentListScreen: some View {
        torrentList
            .listStyle(PlainListStyle())
            .refreshable {
                hapticFeedback.play(.actionTriggered)
                let outcome = await store.refreshNow()
                if let feedback = outcome.appHapticFeedback {
                    hapticFeedback.play(feedback)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    statisticsButton

                    if store.host != nil, store.connectionStatus != .connected {
                        iOSConnectionBannerView(store: store)
                    }
                }
                .background(Color(.systemBackground))
            }
            .navigationTitle(sidebarSelection.rawValue)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search torrents")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isSidebarOpen.toggle()
                    } label: {
                        SidebarToggleGlyph()
                    }
                    .accessibilityLabel("Menu")
                }
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

    var statisticsButton: some View {
        StatsHeaderView(
            store: store,
            onShowStatistics: {
                hapticFeedback.play(.actionTriggered)
                isStatisticsPresented = true
            }
        )
    }

    var displayedTorrents: [Torrent] {
        filterAndSortTorrents(
            store.torrents,
            options: TorrentDisplayOptions(
                statusFilter: sidebarSelection.filter,
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
                if store.hasLoadedSnapshot { emptyTorrentList }
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
            showContentTypeIcons: showContentTypeIcons,
            isSelected: navigation.isInspectorPresented && navigation.selectedTorrentID == torrent.id,
            onInspect: { selectTorrent(torrent.id) }
        )
    }

    @ToolbarContentBuilder
    var actionToolbarItems: some ToolbarContent {
        if #available(iOS 27, *) {
            ToolbarOverflowMenu {
                allTorrentActions
            }
        } else {
            ToolbarItem(placement: .topBarTrailing) {
                Menu("Torrent Actions", systemImage: "ellipsis") {
                    allTorrentActions
                }
                .iOSHapticControlActivation()
            }
        }
    }

    var allTorrentActions: some View {
        Group {
            Button("Pause All", systemImage: "pause", action: pauseAllTorrents)
            Button("Resume All", systemImage: "play", action: resumeAllTorrents)
        }
    }

    var bottomToolbarItems: some ToolbarContent {
        Group {
            ToolbarItem(placement: .bottomBar) {
                // Keep the popover's navigation state stable when the button style changes.
                ZStack {
                    Button {
                        hapticFeedback.play(.actionTriggered)
                        showPrefs.toggle()
                    } label: {
                        Label("Filter and Sort", systemImage: "line.3.horizontal.decrease")
                    }
                    .if(hasActiveFilters) { button in
                        button.buttonStyle(.borderedProminent)
                    }
                    .tint(hasActiveFilters ? Color.accentColor : Color.primary)
                    .accessibilityValue(hasActiveFilters ? "Active" : "Inactive")
                }
                .popover(isPresented: $showPrefs) {
                    iOSFilterAndSortView(
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
                    hapticFeedback.play(.actionTriggered)
                    store.isShowingAddAlert.toggle()
                }, label: {
                    Label("Add Torrent", systemImage: "plus")
                })
            }
        }
    }

    func pauseAllTorrents() {
        performAllTorrentsAction(
            .pauseAllTorrents,
            operation: { try await store.pauseAllTorrents() }
        )
    }

    func resumeAllTorrents() {
        performAllTorrentsAction(
            .resumeAllTorrents,
            operation: { try await store.resumeAllTorrents() }
        )
    }

    func performAllTorrentsAction(
        _ context: TransmissionActionFailureContext,
        operation: @escaping @MainActor @Sendable () async throws -> Void
    ) {
        hapticFeedback.play(.actionTriggered)
        let errorHandler = makeTransmissionDebugErrorHandler(
            store: store,
            context: context
        )

        performTransmissionAction(
            operation: operation,
            onSuccess: {
                hapticFeedback.play(.operationSucceeded)
            },
            onError: { message in
                hapticFeedback.play(.operationFailed)
                errorHandler(message)
            }
        )
    }

    func reconcileSelectedLabels(with availableLabels: [String]) {
        var reconciledFilter = labelFilter
        reconciledFilter.reconcile(with: availableLabels)

        if reconciledFilter != labelFilter {
            labelFilter = reconciledFilter
        }
    }

    var hasActiveFilters: Bool {
        labelFilter.isActive
    }

    func torrentCount(for category: SidebarSelection) -> Int {
        store.torrents.filtered(by: category.filter).count
    }

    var availableLabelCounts: [String: Int] {
        Dictionary(
            uniqueKeysWithValues: store.availableLabels.map { label in
                (label, store.torrentCount(for: label))
            }
        )
    }
}

#if DEBUG
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

#endif
