import SwiftUI

#if os(macOS)

struct macOSContentSidebar: View {
    let hosts: [Host]
    @Binding var sidebarSelection: SidebarSelection
    let selectedHostID: String?
    let accentColor: Color
    let torrentCount: (SidebarSelection) -> Int
    let onSelectHost: (Host) -> Void
    let onAddServer: () -> Void
    let onManageServers: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        List(selection: $sidebarSelection) {
            Section("Dreams") {
                ForEach(SidebarSelection.allCases) { item in
                    Label(item.rawValue, systemImage: item.icon)
                        .badge(torrentCount(item))
                        .tag(item)
                }
            }

            Section("Servers") {
                ForEach(hosts, id: \.serverID) { host in
                    Button {
                        onSelectHost(host)
                    } label: {
                        HStack {
                            Label(host.name ?? "Unnamed Server", systemImage: "server.rack")
                            Spacer()
                            if host.serverID == selectedHostID {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                Button(action: onAddServer) {
                    Label("Add Server", systemImage: "plus")
                }
                .buttonStyle(.plain)
            }

            Section("Settings") {
                Button(action: onManageServers) {
                    Label("Manage Servers", systemImage: "gearshape")
                }
                .buttonStyle(.plain)

                Button(action: onOpenSettings) {
                    Label("Settings", systemImage: "gear")
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(SidebarListStyle())
        .tint(accentColor)
    }
}

#endif
