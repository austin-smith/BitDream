import SwiftUI

#if os(macOS)

struct macOSContentSidebar: View {
    let hosts: [Host]
    @Binding var sidebarSelection: SidebarSelection
    let selectedHostID: String?
    let accentColor: Color
    let torrentCount: (SidebarSelection) -> Int
    let onSelectHost: (Host) -> Void
    let onEditServer: (Host) -> Void
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
                    .contextMenu {
                        Button {
                            onEditServer(host)
                        } label: {
                            Label {
                                Text("Edit Server…")
                            } icon: {
                                Image(systemName: "square.and.pencil")
                                    .symbolRenderingMode(.monochrome)
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                    .accessibilityAction(named: "Edit Server") {
                        onEditServer(host)
                    }
                }

                Button(action: onAddServer) {
                    Label {
                        Text("Add Server")
                    } icon: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(accentColor)
                    }
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

#if os(macOS) && DEBUG
#Preview("macOS Sidebar", traits: .fixedLayout(width: 300, height: 620)) {
    @Previewable @State var selection = SidebarSelection.allDreams
    let hosts = PreviewFixtures.makeHosts()
    macOSContentSidebar(
        hosts: hosts,
        sidebarSelection: $selection,
        selectedHostID: hosts[0].serverID,
        accentColor: .blue,
        torrentCount: { _ in 5 },
        onSelectHost: { _ in },
        onEditServer: { _ in },
        onAddServer: {},
        onManageServers: {},
        onOpenSettings: {}
    )
}
#endif
