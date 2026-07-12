import SwiftUI

#if os(iOS)
/// Slide-out drawer content mirroring the macOS sidebar: status filters, servers, and settings.
struct iOSSidebarView: View {
    let hosts: [Host]
    @Binding var sidebarSelection: SidebarSelection
    let selectedHostID: String?
    let torrentCount: (SidebarSelection) -> Int
    let onSelectHost: (Host) -> Void
    let onEditServer: (Host) -> Void
    let onAddServer: () -> Void
    let onManageServers: () -> Void
    let onOpenSettings: () -> Void

    private var sortedHosts: [Host] {
        hosts.sortedByDisplayName()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("BitDream")
                .font(.title2.bold())
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 4)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    sectionHeader("Dreams")
                    ForEach(SidebarSelection.allCases) { item in
                        SidebarRow(
                            title: item.rawValue,
                            systemImage: item.icon,
                            badge: torrentCount(item),
                            isSelected: item == sidebarSelection
                        ) {
                            sidebarSelection = item
                        }
                    }

                    sectionHeader("Servers")
                    ForEach(sortedHosts, id: \.serverID) { host in
                        SidebarRow(
                            title: host.displayName,
                            systemImage: "server.rack",
                            showsCheckmark: host.serverID == selectedHostID
                        ) {
                            onSelectHost(host)
                        }
                        .contextMenu {
                            Button("Edit Server", systemImage: "square.and.pencil") {
                                onEditServer(host)
                            }
                        }
                        .accessibilityAction(named: "Edit Server") {
                            onEditServer(host)
                        }
                    }
                    SidebarRow(
                        title: "Add Server",
                        systemImage: "plus.circle.fill",
                        isAction: true,
                        action: onAddServer
                    )
                }
                .padding(.horizontal, 8)
            }
            .contentMargins(.bottom, 60, for: .scrollContent)
            .overlay(alignment: .bottom) {
                GlassEffectContainer {
                    HStack {
                        FooterCircleButton(systemImage: "server.rack", label: "Manage Servers", action: onManageServers)

                        Spacer()

                        FooterCircleButton(systemImage: "gear", label: "Settings", action: onOpenSettings)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(.systemBackground))
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.top, 16)
            .padding(.bottom, 4)
    }
}

private struct FooterCircleButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title3)
                .frame(width: 44, height: 44)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(label)
    }
}

private struct SidebarRow: View {
    let title: String
    let systemImage: String
    var badge: Int?
    var isSelected = false
    var showsCheckmark = false
    var isAction = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .frame(width: 24)
                    .foregroundStyle((isSelected || isAction) ? Color.accentColor : Color.primary)

                Text(title)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()

                if showsCheckmark {
                    Image(systemName: "checkmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                } else if let badge {
                    Text("\(badge)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#if DEBUG
#Preview("iOS Sidebar") {
    @Previewable @State var selection = SidebarSelection.allDreams
    PreviewContainer { environment in
        iOSSidebarView(
            hosts: environment.hosts,
            sidebarSelection: $selection,
            selectedHostID: environment.hosts.first?.serverID,
            torrentCount: { _ in 5 },
            onSelectHost: { _ in },
            onEditServer: { _ in },
            onAddServer: {},
            onManageServers: {},
            onOpenSettings: {}
        )
        .frame(maxWidth: 300)
    }
}
#endif

#endif
