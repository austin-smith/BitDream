import WidgetKit
import SwiftUI
import AppIntents

struct SessionOverviewEntry: TimelineEntry {
    let date: Date
    let snapshot: SessionOverviewSnapshot?
    let isStale: Bool
    let isPlaceholder: Bool
    
    init(date: Date, snapshot: SessionOverviewSnapshot?, isStale: Bool, isPlaceholder: Bool = false) {
        self.date = date
        self.snapshot = snapshot
        self.isStale = isStale
        self.isPlaceholder = isPlaceholder
    }
}

struct SessionOverviewProvider: AppIntentTimelineProvider {
    typealias Entry = SessionOverviewEntry
    typealias Intent = SessionOverviewIntent
    private static let refreshInterval: TimeInterval = 600

    // MARK: - Preview helpers
    private func shouldUseGalleryPreview(_ configuration: Intent, _ context: Context) -> Bool {
        configuration.server?.id == nil && context.isPreview
    }

    private func makeGalleryPreviewSnapshot() -> SessionOverviewSnapshot {
        SessionOverviewSnapshot(
            serverId: "preview",
            serverName: "Home Server",
            active: 3,
            paused: 2,
            total: 15,
            totalCount: 15,
            downloadingCount: 3,
            completedCount: 10,
            downloadSpeed: Int64(2_400_000),
            uploadSpeed: Int64(850_000),
            ratio: 1.25,
            timestamp: .now
        )
    }

    private func makeGalleryPreviewEntry() -> Entry {
        Entry(date: .now, snapshot: makeGalleryPreviewSnapshot(), isStale: false, isPlaceholder: false)
    }

    func placeholder(in context: Context) -> Entry {
        // Show realistic preview data so users understand what the widget does
        return Entry(date: .now, snapshot: makeGalleryPreviewSnapshot(), isStale: false, isPlaceholder: true)
    }

    func snapshot(for configuration: Intent, in context: Context) async -> Entry {
        // Only show fake data for widget gallery preview, not for actual widgets
        if shouldUseGalleryPreview(configuration, context) { return makeGalleryPreviewEntry() }
        
        return await loadEntry(for: configuration.server?.id)
    }

    func timeline(for configuration: Intent, in context: Context) async -> Timeline<Entry> {
        // Only show fake data for widget gallery preview, not for actual widgets
        let entry: Entry
        if shouldUseGalleryPreview(configuration, context) {
            entry = makeGalleryPreviewEntry()
        } else {
            entry = await loadEntry(for: configuration.server?.id)
        }
        
        let next = Date().addingTimeInterval(Self.refreshInterval)
        return Timeline(entries: [entry], policy: .after(next))
    }

    private func loadEntry(for serverId: String?) async -> Entry {
        guard let serverId = serverId,
              let url = AppGroup.Files.sessionURL(for: serverId),
              let snap: SessionOverviewSnapshot = AppGroupJSON.read(SessionOverviewSnapshot.self, from: url) else {
            return Entry(date: .now, snapshot: nil, isStale: true, isPlaceholder: false)
        }
        let isStale = (Date().timeIntervalSince(snap.timestamp) > Self.refreshInterval)
        return Entry(date: .now, snapshot: snap, isStale: isStale, isPlaceholder: false)
    }
}

@main
struct SessionOverviewWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetKind.sessionOverview, intent: SessionOverviewIntent.self, provider: SessionOverviewProvider()) { entry in
            let deepLink: URL? = entry.snapshot.flatMap { snap in
                DeepLinkBuilder.serverURL(serverId: snap.serverId)
            }
            SessionOverviewView(entry: entry)
                .containerBackground(for: .widget) {
                    SessionOverviewBackground(entry: entry)
                }
                .widgetURL(deepLink)
        }
        .configurationDisplayName("Server Monitor")
        .description("Monitor torrent counts and transfer speeds for your server.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}



// MARK: - Background overlay with banner and bottom speed chips
private struct SessionOverviewBackground: View {
    let entry: SessionOverviewEntry
    @Environment(\.widgetFamily) var family

    private var headerHeight: CGFloat { 32 }
    private static let speedFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.allowsNonnumericFormatting = false
        f.countStyle = .file
        f.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        return f
    }()

    var body: some View {
        ZStack(alignment: .topLeading) {
            ContainerRelativeShape().fill(.background)
            // Banner layer
            Color(red: 0x67/255.0, green: 0xa3/255.0, blue: 0xd9/255.0)
                .frame(height: headerHeight)
                .frame(maxWidth: .infinity, alignment: .top)

            // Header content inside the banner - server name or placeholder
            HStack {
                if entry.isPlaceholder {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.white.opacity(0.5))
                        .frame(width: family == .systemSmall ? 70 : 80, height: 11)
                } else {
                    Text(entry.snapshot?.serverName ?? "")
                        .font(.system(size: 12, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(.white.opacity(0.9))
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(height: headerHeight, alignment: .center)

            // Bottom performance metrics: ALL CENTERED
            if entry.isPlaceholder {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        // For small, two chips; medium had three including ratio
                        if family != .systemSmall {
                            Capsule()
                                .fill(.gray.opacity(0.2))
                                .frame(width: 48, height: 20)
                        }
                        Capsule()
                            .fill(.gray.opacity(0.2))
                            .frame(width: 65, height: 18)
                        Capsule()
                            .fill(.gray.opacity(0.2))
                            .frame(width: 60, height: 18)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.bottom, 8)
            } else if let snap = entry.snapshot {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        let speedFont = Font.system(size: 10, weight: .regular, design: .monospaced)

                        // Only show ratio on medium
                        if family != .systemSmall {
                            WidgetRatioChip(ratio: snap.ratio)
                        }

                        // Download speed
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.down")
                                .foregroundColor(.blue)
                            Text("\(Self.speedFormatter.string(fromByteCount: snap.downloadSpeed))/s")
                        }
                        .font(speedFont)
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.gray.opacity(0.1))
                        .clipShape(Capsule())

                        // Upload speed
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.up")
                                .foregroundColor(.green)
                            Text("\(Self.speedFormatter.string(fromByteCount: snap.uploadSpeed))/s")
                        }
                        .font(speedFont)
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.gray.opacity(0.1))
                        .clipShape(Capsule())
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.bottom, 8)
            }
        }
    }
}