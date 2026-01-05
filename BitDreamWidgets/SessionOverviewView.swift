import SwiftUI
import WidgetKit

// MARK: - Widget Components

struct WidgetRatioChip: View {
    let ratio: Double

    init(ratio: Double) {
        self.ratio = ratio
    }

    private var progressRingSize: CGFloat = 12

    var body: some View {
        HStack(spacing: 3) {
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1.5)
                    .frame(width: progressRingSize, height: progressRingSize)

                Circle()
                    .trim(from: 0, to: min(ratio, 1.0))
                    .stroke(ratio >= 1.0 ? .green : .orange, lineWidth: 1.5)
                    .frame(width: progressRingSize, height: progressRingSize)
                    .rotationEffect(.degrees(-90))
            }

            Text(String(format: "%.2f", ratio))
                .monospacedDigit()
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.gray.opacity(0.1))
        .clipShape(Capsule())
    }
}

// MARK: - Placeholder View

struct PlaceholderView: View {
    private var headerHeight: CGFloat { 32 }

    var body: some View {
        ZStack {
            // Main content below banner (banner is drawn in container background)
            VStack(spacing: 16) {
                // Torrent counts - 3 column layout with placeholder shapes
                HStack(spacing: 0) {
                    // Total placeholder
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.primary.opacity(0.3))
                            .frame(width: 28, height: 24)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(.secondary.opacity(0.3))
                            .frame(width: 32, height: 11)
                    }
                    .frame(maxWidth: .infinity)

                    // Downloading placeholder
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.primary.opacity(0.3))
                            .frame(width: 20, height: 24)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(.secondary.opacity(0.3))
                            .frame(width: 64, height: 11)
                    }
                    .frame(maxWidth: .infinity)

                    // Completed placeholder
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.primary.opacity(0.3))
                            .frame(width: 20, height: 24)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(.secondary.opacity(0.3))
                            .frame(width: 28, height: 11)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 20)

                Spacer(minLength: 0)
            }
            .padding(.top, headerHeight)
            .padding(.vertical, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Session Overview Widget View

// Small family layout: icons-only (Downloading, Seeding, Done)
struct SessionOverviewSmallView: View {
    let snap: SessionOverviewSnapshot
    private var headerHeight: CGFloat { 32 }

    var body: some View {
        ZStack {
            VStack(spacing: 12) {
                HStack(spacing: 0) {
                    VStack(spacing: 3) {
                        Text("\(snap.totalCount)")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                            .minimumScaleFactor(0.8)
                        Image(systemName: "tray.full")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)

                    VStack(spacing: 3) {
                        Text("\(snap.downloadingCount)")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                            .minimumScaleFactor(0.8)
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)

                    VStack(spacing: 3) {
                        Text("\(snap.completedCount)")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                            .minimumScaleFactor(0.8)
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 20)

                Spacer(minLength: 0)
            }
            .padding(.top, headerHeight)
            .padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Session Overview Widget View

struct SessionOverviewView: View {
    let entry: SessionOverviewEntry
    @Environment(\.widgetFamily) var family

    // Byte formatter for speeds
    private var byteCountFormatter: ByteCountFormatter {
        let formatter = ByteCountFormatter()
        formatter.allowsNonnumericFormatting = false
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        return formatter
    }

    var body: some View {
        if entry.isPlaceholder {
            PlaceholderView()
        } else if let snap = entry.snapshot {
            if family == .systemSmall {
                SessionOverviewSmallView(snap: snap)
            } else {
                let headerHeight: CGFloat = 32 // medium header
                ZStack {
                    VStack(spacing: 16) {
                        HStack(spacing: 0) {
                            VStack(spacing: 4) {
                                Text("\(snap.totalCount)")
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                                    .foregroundStyle(.primary)
                                Text("Total")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            VStack(spacing: 4) {
                                Text("\(snap.downloadingCount)")
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                                    .foregroundStyle(.primary)
                                Text("Downloading")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            VStack(spacing: 4) {
                                Text("\(snap.completedCount)")
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                                    .foregroundStyle(.primary)
                                Text("Done")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .padding(.horizontal, 20)
                        Spacer(minLength: 0)
                    }
                    .padding(.top, headerHeight)
                    .padding(.vertical, 16)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            let headerHeight: CGFloat = 32
            ZStack {
                VStack(spacing: family == .systemSmall ? 6 : 12) {
                    Image(systemName: "server.rack")
                        .font(.system(size: family == .systemSmall ? 20 : 28))
                        .foregroundStyle(.secondary)
                    Text("Select Server")
                        .font(.system(size: family == .systemSmall ? 13 : 15, weight: .medium))
                        .foregroundStyle(.primary)
                    Text("Edit this widget to select a server.")
                        .font(.system(size: family == .systemSmall ? 11 : 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, headerHeight)
                .padding(.horizontal, family == .systemSmall ? 12 : 20)
                .padding(.bottom, family == .systemSmall ? 12 : 20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // Helper to format time ago
    private func timeAgoString(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        let minutes = Int(interval / 60)

        if minutes < 1 {
            return "just now"
        } else if minutes < 60 {
            return "\(minutes)m ago"
        } else {
            let hours = minutes / 60
            return "\(hours)h ago"
        }
    }
}

#if DEBUG
struct SessionOverviewView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // High activity with fast speeds
            SessionOverviewView(entry: .init(
                date: .now,
                snapshot: .init(
                    serverId: "1",
                    serverName: "Home NAS",
                    active: 8,
                    paused: 2,
                    total: 25,
                    totalCount: 25,
                    downloadingCount: 8,
                    completedCount: 15,
                    downloadSpeed: 12_800_000, // 12.8 MB/s
                    uploadSpeed: 3_200_000,   // 3.2 MB/s
                    ratio: 2.15,
                    timestamp: .now
                ),
                isStale: false,
                isPlaceholder: false
            ))
            .previewContext(WidgetPreviewContext(family: .systemMedium))
            .previewDisplayName("High Activity")

            // Idle state - all completed
            SessionOverviewView(entry: .init(
                date: .now,
                snapshot: .init(
                    serverId: "2",
                    serverName: "Seedbox Pro",
                    active: 0,
                    paused: 0,
                    total: 42,
                    totalCount: 42,
                    downloadingCount: 0,
                    completedCount: 42,
                    downloadSpeed: 0,
                    uploadSpeed: 1_250_000, // Still seeding
                    ratio: 4.73,
                    timestamp: .now
                ),
                isStale: false,
                isPlaceholder: false
            ))
            .previewContext(WidgetPreviewContext(family: .systemMedium))
            .previewDisplayName("Idle/Seeding")

            // Long server name test
            SessionOverviewView(entry: .init(
                date: .now,
                snapshot: .init(
                    serverId: "3",
                    serverName: "My Very Long Server Name That Should Truncate",
                    active: 3,
                    paused: 1,
                    total: 8,
                    totalCount: 8,
                    downloadingCount: 3,
                    completedCount: 4,
                    downloadSpeed: 5_600_000,
                    uploadSpeed: 850_000,
                    ratio: 0.67,
                    timestamp: .now
                ),
                isStale: false,
                isPlaceholder: false
            ))
            .previewContext(WidgetPreviewContext(family: .systemMedium))
            .previewDisplayName("Long Name")

            // Low ratio scenario
            SessionOverviewView(entry: .init(
                date: .now,
                snapshot: .init(
                    serverId: "4",
                    serverName: "Remote Server",
                    active: 2,
                    paused: 6,
                    total: 18,
                    totalCount: 18,
                    downloadingCount: 2,
                    completedCount: 10,
                    downloadSpeed: 450_000,
                    uploadSpeed: 125_000,
                    ratio: 0.23, // Low ratio
                    timestamp: .now
                ),
                isStale: false,
                isPlaceholder: false
            ))
            .previewContext(WidgetPreviewContext(family: .systemMedium))
            .previewDisplayName("Low Ratio")

            // Placeholder state
            SessionOverviewView(entry: .init(
                date: .now,
                snapshot: nil,
                isStale: false,
                isPlaceholder: true
            ))
            .previewContext(WidgetPreviewContext(family: .systemMedium))
            .previewDisplayName("Loading Placeholder")

            // No server selected
            SessionOverviewView(entry: .init(
                date: .now,
                snapshot: nil,
                isStale: false,
                isPlaceholder: false
            ))
            .previewContext(WidgetPreviewContext(family: .systemMedium))
            .previewDisplayName("No Server Selected")

            // Small: Active
            SessionOverviewView(entry: .init(
                date: .now,
                snapshot: .init(
                    serverId: "1",
                    serverName: "Home NAS",
                    active: 8,
                    paused: 2,
                    total: 25,
                    totalCount: 25,
                    downloadingCount: 5,
                    completedCount: 15,
                    downloadSpeed: 12_800_000,
                    uploadSpeed: 3_200_000,
                    ratio: 2.15,
                    timestamp: .now
                ),
                isStale: false,
                isPlaceholder: false
            ))
            .previewContext(WidgetPreviewContext(family: .systemSmall))
            .previewDisplayName("Small • Active")

            // Small: Idle
            SessionOverviewView(entry: .init(
                date: .now,
                snapshot: .init(
                    serverId: "2",
                    serverName: "Seedbox",
                    active: 0,
                    paused: 0,
                    total: 42,
                    totalCount: 42,
                    downloadingCount: 0,
                    completedCount: 42,
                    downloadSpeed: 0,
                    uploadSpeed: 1_250_000,
                    ratio: 4.73,
                    timestamp: .now
                ),
                isStale: false,
                isPlaceholder: false
            ))
            .previewContext(WidgetPreviewContext(family: .systemSmall))
            .previewDisplayName("Small • Idle")

            // Small: Placeholder
            SessionOverviewView(entry: .init(
                date: .now,
                snapshot: nil,
                isStale: false,
                isPlaceholder: true
            ))
            .previewContext(WidgetPreviewContext(family: .systemSmall))
            .previewDisplayName("Small • Placeholder")

            // Small: No Server Selected
            SessionOverviewView(entry: .init(
                date: .now,
                snapshot: nil,
                isStale: false,
                isPlaceholder: false
            ))
            .previewContext(WidgetPreviewContext(family: .systemSmall))
            .previewDisplayName("Small • No Server")
        }
    }
}
#endif
