import SwiftUI
import WidgetKit

struct StatRow: View {
    let label: LocalizedStringKey
    let value: String
    let sfSymbol: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: sfSymbol)
                .imageScale(.small)
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(value)
                .monospacedDigit()
        }
    }
}

struct SessionOverviewView: View {
    let entry: SessionOverviewEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        if let snap = entry.snapshot {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(snap.serverName)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    if entry.isStale {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .help("Data may be out of date. Open BitDream to refresh.")
                    }
                }

                if family == .systemSmall {
                    VStack(alignment: .leading, spacing: 6) {
                        StatRow(label: "Active", value: "\(snap.active)", sfSymbol: "arrow.down.circle")
                        StatRow(label: "DL", value: formatSpeed(snap.downloadSpeed), sfSymbol: "arrow.down")
                        StatRow(label: "UL", value: formatSpeed(snap.uploadSpeed), sfSymbol: "arrow.up")
                    }
                } else {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            StatRow(label: "Active", value: "\(snap.active)", sfSymbol: "arrow.down.circle")
                            StatRow(label: "Paused", value: "\(snap.paused)", sfSymbol: "pause.circle")
                            StatRow(label: "Total", value: "\(snap.total)", sfSymbol: "tray.full")
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            StatRow(label: "DL", value: formatSpeed(snap.downloadSpeed), sfSymbol: "arrow.down")
                            StatRow(label: "UL", value: formatSpeed(snap.uploadSpeed), sfSymbol: "arrow.up")
                            StatRow(label: "Ratio", value: formatRatio(snap.ratio), sfSymbol: "equal.circle")
                        }
                    }
                }
            }
            .padding(12)
        } else {
            VStack(spacing: 4) {
                Image(systemName: "server.rack")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text("Select Server")
                    .font(.caption)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.center)
                Text("Edit this widget to choose a server.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func formatSpeed(_ bytesPerSecond: Int64) -> String {
        let units: [(Double, String)] = [
            (1_000_000_000, "GB/s"),
            (1_000_000, "MB/s"),
            (1_000, "KB/s")
        ]
        let value = Double(bytesPerSecond)
        for (threshold, label) in units {
            if value >= threshold { return String(format: "%.1f %@", value / threshold, label) }
        }
        return "\(bytesPerSecond) B/s"
    }

    private func formatRatio(_ ratio: Double) -> String {
        String(format: "%.2f", ratio)
    }
}

#if DEBUG
struct SessionOverviewView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            SessionOverviewView(entry: .init(date: .now, snapshot: .init(serverId: "1", serverName: "Home Server", active: 2, paused: 5, total: 12, downloadSpeed: 1_200_000, uploadSpeed: 140_000, ratio: 1.42, timestamp: .now), isStale: false))
                .previewContext(WidgetPreviewContext(family: .systemSmall))

            SessionOverviewView(entry: .init(date: .now, snapshot: .init(serverId: "1", serverName: "Home Server", active: 2, paused: 5, total: 12, downloadSpeed: 1_200_000, uploadSpeed: 140_000, ratio: 1.42, timestamp: .now), isStale: false))
                .previewContext(WidgetPreviewContext(family: .systemMedium))
        }
    }
}
#endif


