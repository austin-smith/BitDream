enum iOSTorrentDetailRoute: Hashable {
    case overview
    case files
    case peers
}

enum iOSTorrentPresentation {
    case stack
    case inspector
}

/// One selection and child path, independent of where SwiftUI presents them.
struct iOSNavigationState {
    var sidebarSelection: SidebarSelection = .allDreams
    private(set) var selectedTorrentID: Int?
    private(set) var isDetailPresented = false
    var presentation: iOSTorrentPresentation = .stack
    var detailPath: [iOSTorrentDetailRoute] = []

    var isInspectorPresented: Bool {
        presentation == .inspector && isDetailPresented && selectedTorrentID != nil
    }

    var stackPath: [iOSTorrentDetailRoute] {
        guard presentation == .stack, isDetailPresented, selectedTorrentID != nil else { return [] }
        return [.overview] + detailPath
    }

    mutating func selectTorrent(_ id: Int) {
        if selectedTorrentID != id {
            detailPath.removeAll()
        }
        selectedTorrentID = id
        isDetailPresented = true
    }

    mutating func hideDetails() {
        isDetailPresented = false
    }

    mutating func setStackPath(_ path: [iOSTorrentDetailRoute]) {
        // The outgoing container can write back during adaptation. Only the active
        // presentation owns navigation; resizing is not a Back or Close action.
        guard presentation == .stack else { return }
        if path.isEmpty {
            hideDetails()
            detailPath.removeAll()
        } else if selectedTorrentID != nil, path.first == .overview {
            detailPath = Array(path.dropFirst())
        }
    }

    mutating func setInspectorPresented(_ isPresented: Bool) {
        guard presentation == .inspector, selectedTorrentID != nil else { return }
        isDetailPresented = isPresented
    }

    mutating func setInspectorPath(_ path: [iOSTorrentDetailRoute]) {
        guard presentation == .inspector else { return }
        detailPath = path
    }

    mutating func clearTorrentSelection() {
        selectedTorrentID = nil
        detailPath.removeAll()
        isDetailPresented = false
    }

    mutating func reconcileTorrentSelection(availableIDs: [Int]) {
        guard let selectedTorrentID, !availableIDs.contains(selectedTorrentID) else { return }
        clearTorrentSelection()
    }
}
