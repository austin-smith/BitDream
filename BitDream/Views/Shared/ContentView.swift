//
//  ContentView.swift
//  BitDream
//
//  Created by Austin Smith on 12/29/22.
//

import Foundation
import CoreData
import KeychainAccess
import SwiftUI

// MARK: - UserDefaults Extension for View State
extension UserDefaults {
    private enum Keys {
        static let sidebarVisibility = "sidebarVisibility"
        static let inspectorVisibility = "inspectorVisibility"
        static let sortBySelection = "sortBySelection"
    }
    
    static let viewStateDefaults: [String: Any] = [
        Keys.sidebarVisibility: true, // true = show sidebar (.all), false = hide sidebar (.detailOnly)
        Keys.inspectorVisibility: true,
        Keys.sortBySelection: "name" // Default sort by name
    ]
    
    static func registerViewStateDefaults() {
        UserDefaults.standard.register(defaults: viewStateDefaults)
    }
    
    var sidebarVisibility: NavigationSplitViewVisibility {
        get {
            return bool(forKey: Keys.sidebarVisibility) ? .all : .detailOnly
        }
        set {
            set(newValue == .all, forKey: Keys.sidebarVisibility)
        }
    }
    
    var inspectorVisibility: Bool {
        get { bool(forKey: Keys.inspectorVisibility) }
        set { set(newValue, forKey: Keys.inspectorVisibility) }
    }
    
    var sortBySelection: sortBy {
        get {
            let rawValue = string(forKey: Keys.sortBySelection) ?? "name"
            return sortBy(rawValue: rawValue) ?? .name
        }
        set {
            set(newValue.rawValue, forKey: Keys.sortBySelection)
        }
    }
}

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        entity: Host.entity(),
        sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)]
    ) var hosts: FetchedResults<Host>

    @ObservedObject var store: Store = Store()

    var body: some View {
        #if os(iOS)
        iOSContentView(viewContext: viewContext, hosts: hosts, store: store)
        #elseif os(macOS)
        macOSContentView(viewContext: viewContext, hosts: hosts, store: store)
        #endif
    }
}

// Helper function to create binding for a torrent
func binding(for torrent: Torrent, in store: Store) -> Binding<Torrent> {
    return Binding<Torrent>(
        get: {
            if let index = store.torrents.firstIndex(where: { $0.id == torrent.id }) {
                return store.torrents[index]
            }
            return torrent
        },
        set: { newValue in
            if let index = store.torrents.firstIndex(where: { $0.id == torrent.id }) {
                store.torrents[index] = newValue
            }
        }
    )
}

// Helper function to create an ID-based selection binding
func createTorrentSelectionBinding(selectedId: Binding<Int?>, in store: Store) -> Binding<Torrent?> {
    return Binding<Torrent?>(
        get: {
            if let id = selectedId.wrappedValue {
                return store.torrents.first { $0.id == id }
            }
            return nil
        },
        set: { newValue in
            selectedId.wrappedValue = newValue?.id
        }
    )
}

// Helper function to set up the host
func setupHost(hosts: FetchedResults<Host>, store: Store) {
    hosts.forEach { h in
        if (h.isDefault) {
            store.setHost(host: h)
        }
    }
    if (store.host != nil) {
        store.startTimer()
    } else {
        // Create a new host
        store.setup = true
    }
}

// MARK: - Shared Views

// Stats header view used on both platforms
struct StatsHeaderView: View {
    var store: Store
    
    var body: some View {
        VStack {
            Divider()
            HStack {
                Text(String("\(store.sessionStats?.activeTorrentCount ?? 0) active dreams"))
                Spacer()
                HStack(spacing: 2) {
                    Image(systemName: "arrow.down")
                    Text("\(byteCountFormatter.string(fromByteCount: store.sessionStats?.downloadSpeed ?? 0))/s")
                }
                HStack(spacing: 2) {
                    Image(systemName: "arrow.up")
                    Text("\(byteCountFormatter.string(fromByteCount: store.sessionStats?.uploadSpeed ?? 0))/s")
                }
            }
            .font(.subheadline)
            .padding([.leading, .trailing])
            Divider()
        }
    }
}

// MARK: - Shared Enums

// Sidebar selection options (used primarily on macOS but defined here for sharing)
enum SidebarSelection: String, CaseIterable, Identifiable {
    case allDreams = "All Dreams"
    case downloading = "Downloading"
    case seeding = "Seeding"
    case completed = "Completed"
    case paused = "Paused"
    case stalled = "Stalled"
    
    var id: String { self.rawValue }
    
    var icon: String {
        switch self {
        case .allDreams: return "tray.full"
        case .downloading: return "arrow.down.circle"
        case .seeding: return "arrow.up.circle"
        case .completed: return "checkmark.circle"
        case .paused: return "pause.circle"
        case .stalled: return "exclamationmark.circle"
        }
    }
    
    var filter: [TorrentStatusCalc] {
        switch self {
        case .allDreams: return TorrentStatusCalc.allCases
        case .downloading: return [.downloading]
        case .seeding: return [.seeding]
        case .completed: return [.complete]
        case .paused: return [.paused]
        case .stalled: return [.stalled]
        }
    }
}

// MARK: - Shared Extensions

// Extension to filter and sort torrents
extension Array where Element == Torrent {
    func filtered(by filterSelection: [TorrentStatusCalc]) -> [Torrent] {
        if filterSelection == TorrentStatusCalc.allCases {
            return self
        }
        return self.filter { torrent in
            filterSelection.contains { $0 == torrent.statusCalc }
        }
    }
    
    func sorted(by sortSelection: sortBy) -> [Torrent] {
        return sortTorrents(self, sortBy: sortSelection)
    }
}

#if os(macOS)
// Helper function to update the app badge on macOS
func updateMacOSAppBadge(count: Int) {
    NSApplication.shared.dockTile.badgeLabel = count > 0 ? "\(count)" : ""
}

// Helper function to get completed torrents count
func getCompletedTorrentsCount(in store: Store) -> Int {
    return store.torrents.filter { $0.statusCalc == .complete }.count
}
#endif 