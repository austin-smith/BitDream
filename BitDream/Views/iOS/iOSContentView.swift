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
    @State private var sidebarSelection: SidebarSelection = .allDreams
    @State private var labelFilter = TorrentLabelFilter()
    @AppStorage(UserDefaultsKeys.showContentTypeIcons) private var showContentTypeIcons = AppDefaults.showContentTypeIcons
    @State private var searchText: String = ""
    @State private var showPrefs: Bool = false

    @State private var isSidebarOpen = false
    @State private var sidebarDragOffset: CGFloat = 0

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
        GeometryReader { proxy in
            let drawerWidth = proxy.size.width * 0.75
            let progress = sidebarProgress(drawerWidth: drawerWidth)

            ZStack(alignment: .leading) {
                Color(.systemBackground)

                sidebar(drawerWidth: drawerWidth, progress: progress, safeAreaInsets: proxy.safeAreaInsets)

                mainContent(drawerWidth: drawerWidth, progress: progress)
            }
            .ignoresSafeArea()
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

// MARK: - Drawer Container

private extension iOSContentView {
    func sidebarProgress(drawerWidth: CGFloat) -> CGFloat {
        let base: CGFloat = isSidebarOpen ? drawerWidth : 0
        return min(max((base + sidebarDragOffset) / drawerWidth, 0), 1)
    }

    func sidebar(drawerWidth: CGFloat, progress: CGFloat, safeAreaInsets: EdgeInsets) -> some View {
        iOSSidebarView(
            hosts: hosts,
            sidebarSelection: $sidebarSelection,
            selectedHostID: store.host?.serverID,
            torrentCount: { torrentCount(for: $0) },
            onSelectHost: { host in
                store.setHost(host: host)
                closeSidebar()
            },
            onAddServer: {
                store.setup = true
            },
            onManageServers: {
                store.editServers = true
            },
            onOpenSettings: {
                store.showSettings = true
            }
        )
        .padding(.top, safeAreaInsets.top)
        .padding(.bottom, max(0, safeAreaInsets.bottom - 6))
        .frame(width: drawerWidth)
        .offset(x: -drawerWidth * 0.3 * (1 - progress))
        .accessibilityHidden(progress == 0)
    }

    func mainContent(drawerWidth: CGFloat, progress: CGFloat) -> some View {
        NavigationStack(path: $torrentPath) {
            torrentListScreen
                .navigationDestination(for: Int.self) { torrentID in
                    if let torrent = store.torrents.first(where: { $0.id == torrentID }) {
                        TorrentDetail(store: store, torrent: torrent)
                    }
                }
        }
        .onChange(of: sidebarSelection) { _, _ in
            closeSidebar()
        }
        .overlay {
            if progress > 0 {
                // Invisible tap/drag catcher; the pushed card intentionally stays undimmed
                Color.clear
                    .contentShape(.rect)
                    .onTapGesture {
                        closeSidebar()
                    }
                    .gesture(closeDragGesture(drawerWidth: drawerWidth))
            }
        }
        .overlay(alignment: .leading) {
            if !isSidebarOpen && torrentPath.isEmpty {
                Color.clear
                    .frame(width: 20)
                    .contentShape(.rect)
                    .gesture(openDragGesture(drawerWidth: drawerWidth))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 32 * progress, style: .continuous))
        .shadow(color: .black.opacity(0.12 * progress), radius: 12)
        .offset(x: drawerWidth * progress)
    }

    func openDragGesture(drawerWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                sidebarDragOffset = max(0, value.translation.width)
            }
            .onEnded { value in
                let shouldOpen = value.translation.width > drawerWidth * 0.25
                    || value.predictedEndTranslation.width > drawerWidth * 0.5
                withAnimation(drawerAnimation) {
                    isSidebarOpen = shouldOpen
                    sidebarDragOffset = 0
                }
            }
    }

    func closeDragGesture(drawerWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                sidebarDragOffset = min(0, value.translation.width)
            }
            .onEnded { value in
                let shouldClose = value.translation.width < -drawerWidth * 0.25
                    || value.predictedEndTranslation.width < -drawerWidth * 0.5
                withAnimation(drawerAnimation) {
                    isSidebarOpen = !shouldClose
                    sidebarDragOffset = 0
                }
            }
    }

    var drawerAnimation: Animation {
        .snappy(duration: 0.32, extraBounce: 0)
    }

    func toggleSidebar() {
        withAnimation(drawerAnimation) {
            isSidebarOpen.toggle()
        }
    }

    func closeSidebar() {
        guard isSidebarOpen else { return }
        withAnimation(drawerAnimation) {
            isSidebarOpen = false
        }
    }
}

// MARK: - Torrent List Screen

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
        .navigationTitle(sidebarSelection.rawValue)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await store.refreshNow()
        }
        .searchable(text: $searchText, prompt: "Search torrents")
        .toolbar {
            sidebarToolbarItem
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

    var sidebarToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                toggleSidebar()
            } label: {
                SidebarToggleGlyph()
            }
            .accessibilityLabel("Menu")
        }
    }

    var actionToolbarItems: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
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

/// Sidebar toggle glyph: a long line over a shorter line.
/// Template image so the toolbar tints it like an SF Symbol.
struct SidebarToggleGlyph: View {
    var body: some View {
        Image(uiImage: Self.glyph)
    }

    private static let glyph: UIImage = {
        let lineHeight: CGFloat = 2.5
        let spacing: CGFloat = 4.5
        let size = CGSize(width: 17, height: lineHeight * 2 + spacing)
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            UIColor.black.setFill()
            UIBezierPath(
                roundedRect: CGRect(x: 0, y: 0, width: 17, height: lineHeight),
                cornerRadius: lineHeight / 2
            ).fill()
            UIBezierPath(
                roundedRect: CGRect(x: 0, y: lineHeight + spacing, width: 11, height: lineHeight),
                cornerRadius: lineHeight / 2
            ).fill()
        }
        return image.withRenderingMode(.alwaysTemplate)
    }()
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
