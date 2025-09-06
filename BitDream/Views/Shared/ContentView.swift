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
        static let sortProperty = "sortProperty"
        static let sortOrder = "sortOrder"
    }
    
    static let viewStateDefaults: [String: Any] = [
        Keys.sidebarVisibility: true, // true = show sidebar (.all), false = hide sidebar (.detailOnly)
        Keys.inspectorVisibility: true,
        Keys.sortProperty: "Name", // Default sort property as "Name"
        Keys.sortOrder: true // true = ascending, false = descending
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
    
    var sortProperty: SortProperty {
        get {
            let rawValue = string(forKey: Keys.sortProperty) ?? "Name"
            return SortProperty(rawValue: rawValue) ?? .name
        }
        set {
            set(newValue.rawValue, forKey: Keys.sortProperty)
        }
    }
    
    var sortOrder: SortOrder {
        get { bool(forKey: Keys.sortOrder) ? .ascending : .descending }
        set { set(newValue == .ascending, forKey: Keys.sortOrder) }
    }
}

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        entity: Host.entity(),
        sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)]
    ) var hosts: FetchedResults<Host>

    // Use the store passed from the environment
    @EnvironmentObject var store: Store

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
    @ObservedObject var store: Store
    
    var body: some View {
        VStack(spacing: 0) {
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
            .padding(.vertical, 4)
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
    
    func filtered(by selectedLabels: Set<String>, enabled: Bool) -> [Torrent] {
        guard enabled else { return self }
        guard !selectedLabels.isEmpty else { return self }
        
        return self.filter { torrent in
            // Show torrents that have at least one of the selected labels
            torrent.labels.contains { torrentLabel in
                selectedLabels.contains { selectedLabel in
                    torrentLabel.lowercased() == selectedLabel.lowercased()
                }
            }
        }
    }
    
    func filtered(by statusFilter: [TorrentStatusCalc], labelFilter: Set<String>, labelFilterEnabled: Bool) -> [Torrent] {
        return self.filtered(by: statusFilter).filtered(by: labelFilter, enabled: labelFilterEnabled)
    }
    
    func sorted(by property: SortProperty, order: SortOrder) -> [Torrent] {
        return sortTorrents(self, by: property, order: order)
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