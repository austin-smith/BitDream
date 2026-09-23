import SwiftUI

#if os(iOS)
/// Slide-out drawer content mirroring the macOS sidebar: status filters, servers, and settings.
struct iOSSidebarView: View {
    let hosts: [Host]
    @Binding var sidebarSelection: SidebarSelection
    let selectedHostID: String?
    let connectionState: TransmissionConnectionState
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
            Text(AppIdentity.displayName)
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
                            showsCheckmark: host.serverID == selectedHostID,
                            connectionState: host.serverID == selectedHostID ? connectionState : nil
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
                        systemImage: "plus",
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
    // Center the badge on the visible corner of the 17-point server.rack symbol.
    @ScaledMetric(relativeTo: .body) private var connectionBadgeOffsetX: CGFloat = 5.0 / 3.0
    @ScaledMetric(relativeTo: .body) private var connectionBadgeOffsetY: CGFloat = -8.0 / 3.0
    let title: String
    let systemImage: String
    var badge: Int?
    var isSelected = false
    var showsCheckmark = false
    var connectionState: TransmissionConnectionState?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .overlay(alignment: .topTrailing) {
                        if let connectionState {
                            ServerConnectionIndicator(state: connectionState, size: 8)
                                .offset(x: connectionBadgeOffsetX, y: connectionBadgeOffsetY)
                        }
                    }
                    .frame(width: 24)
                    .foregroundStyle(isSelected ? Color.white : Color.accentColor)

                Text(title)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                    .lineLimit(1)

                Spacer()

                if showsCheckmark {
                    Image(systemName: "checkmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                } else if let badge {
                    Text("\(badge)")
                        .font(.subheadline)
                        .foregroundStyle(isSelected ? Color.white : Color.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.accentColor : Color.clear)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityValue(connectionState?.serverStatusLabel ?? "")
        .accessibilityAddTraits(isSelected || showsCheckmark ? .isSelected : [])
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
            connectionState: .connected,
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
