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

    func placeholder(in context: Context) -> Entry {
        // DEBUG: Test if this method is being called at all
        // Show realistic preview data so users understand what the widget does
        let placeholderSnapshot = SessionOverviewSnapshot(
            serverId: "PLACEHOLDER_TEST", 
            serverName: "PREVIEW SERVER", 
            active: 99, 
            paused: 88, 
            total: 77, 
            totalCount: 77, 
            downloadingCount: 99, 
            completedCount: 66, 
            downloadSpeed: Int64(9_999_999), // Should be obvious
            uploadSpeed: Int64(8_888_888),   // Should be obvious
            ratio: 9.99, 
            timestamp: .now
        )
        return Entry(date: .now, snapshot: placeholderSnapshot, isStale: false, isPlaceholder: false)
    }

    func snapshot(for configuration: Intent, in context: Context) async -> Entry {
        // Only show fake data for widget gallery preview, not for actual widgets
        if configuration.server?.id == nil && context.isPreview {
            let placeholderSnapshot = SessionOverviewSnapshot(
                serverId: "preview", 
                serverName: "Home Server", 
                active: 3, 
                paused: 2, 
                total: 15, 
                totalCount: 15, 
                downloadingCount: 3, 
                completedCount: 10, 
                downloadSpeed: Int64(2_400_000), // 2.4 MB/s
                uploadSpeed: Int64(850_000),     // 850 KB/s
                ratio: 1.25, 
                timestamp: .now
            )
            return Entry(date: .now, snapshot: placeholderSnapshot, isStale: false, isPlaceholder: false)
        }
        
        return await loadEntry(for: configuration.server?.id)
    }

    func timeline(for configuration: Intent, in context: Context) async -> Timeline<Entry> {
        // Only show fake data for widget gallery preview, not for actual widgets
        let entry: Entry
        if configuration.server?.id == nil && context.isPreview {
            let placeholderSnapshot = SessionOverviewSnapshot(
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
            entry = Entry(date: .now, snapshot: placeholderSnapshot, isStale: false, isPlaceholder: false)
        } else {
            entry = await loadEntry(for: configuration.server?.id)
        }
        
        let next = Calendar.current.date(byAdding: .minute, value: 10, to: Date()) ?? Date().addingTimeInterval(600)
        return Timeline(entries: [entry], policy: .after(next))
    }

    private func loadEntry(for serverId: String?) async -> Entry {
        guard let serverId = serverId,
              let url = AppGroup.Files.sessionURL(for: serverId),
              let snap: SessionOverviewSnapshot = AppGroupJSON.read(SessionOverviewSnapshot.self, from: url) else {
            return Entry(date: .now, snapshot: nil, isStale: true, isPlaceholder: false)
        }
        let isStale = (Date().timeIntervalSince(snap.timestamp) > 600)
        return Entry(date: .now, snapshot: snap, isStale: isStale, isPlaceholder: false)
    }
}

@main
struct SessionOverviewWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "SessionOverviewWidget", intent: SessionOverviewIntent.self, provider: SessionOverviewProvider()) { entry in
            SessionOverviewView(entry: entry)
                .containerBackground(for: .widget) {
                    // Full-bleed background with banner and header content
                    let headerHeight: CGFloat = 32
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
                                    .frame(width: 80, height: 11)
                            } else {
                                Text(entry.snapshot?.serverName ?? "")
                                    .font(.system(size: 11, weight: .medium))
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
                                    // Ratio chip placeholder
                                    Capsule()
                                        .fill(.gray.opacity(0.2))
                                        .frame(width: 48, height: 20)
                                    
                                    // Download speed placeholder
                                    Capsule()
                                        .fill(.gray.opacity(0.2))
                                        .frame(width: 65, height: 18)
                                    
                                    // Upload speed placeholder
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
                                    let formatter: ByteCountFormatter = {
                                        var f = ByteCountFormatter()
                                        f.allowsNonnumericFormatting = false
                                        f.countStyle = .file
                                        f.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
                                        return f
                                    }()
                                    let speedFont = Font.system(size: 10, weight: .regular, design: .monospaced)

                                    // Ratio chip
                                    WidgetRatioChip(ratio: snap.ratio)
                                    
                                    // Download speed
                                    HStack(spacing: 2) {
                                        Image(systemName: "arrow.down")
                                            .foregroundColor(.blue)
                                        Text("\(formatter.string(fromByteCount: snap.downloadSpeed))/s")
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
                                        Text("\(formatter.string(fromByteCount: snap.uploadSpeed))/s")
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
        .configurationDisplayName("Server Monitor")
        .description("Monitor torrent counts and transfer speeds for your server.")
        .supportedFamilies([.systemMedium])
    }
}


