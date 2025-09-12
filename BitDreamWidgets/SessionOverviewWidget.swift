import WidgetKit
import SwiftUI
import AppIntents

struct SessionOverviewEntry: TimelineEntry {
    let date: Date
    let snapshot: SessionOverviewSnapshot?
    let isStale: Bool
}

struct SessionOverviewProvider: AppIntentTimelineProvider {
    typealias Entry = SessionOverviewEntry
    typealias Intent = SessionOverviewIntent

    func placeholder(in context: Context) -> Entry {
        Entry(date: .now, snapshot: SessionOverviewSnapshot(serverId: "placeholder", serverName: "Server", active: 2, paused: 5, total: 12, downloadSpeed: 1_200_000, uploadSpeed: 140_000, ratio: 1.42, timestamp: .now), isStale: false)
    }

    func snapshot(for configuration: Intent, in context: Context) async -> Entry {
        await loadEntry(for: configuration.server?.id)
    }

    func timeline(for configuration: Intent, in context: Context) async -> Timeline<Entry> {
        let entry = await loadEntry(for: configuration.server?.id)
        let next = Calendar.current.date(byAdding: .minute, value: 10, to: Date()) ?? Date().addingTimeInterval(600)
        return Timeline(entries: [entry], policy: .after(next))
    }

    private func loadEntry(for serverId: String?) async -> Entry {
        guard let serverId = serverId,
              let url = AppGroup.Files.sessionURL(for: serverId),
              let snap: SessionOverviewSnapshot = AppGroupJSON.read(SessionOverviewSnapshot.self, from: url) else {
            return Entry(date: .now, snapshot: nil, isStale: true)
        }
        let isStale = (Date().timeIntervalSince(snap.timestamp) > 600)
        return Entry(date: .now, snapshot: snap, isStale: isStale)
    }
}

@main
struct SessionOverviewWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "SessionOverviewWidget", intent: SessionOverviewIntent.self, provider: SessionOverviewProvider()) { entry in
            SessionOverviewView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Session Overview")
        .description("Active, paused, total, and speeds for a server.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}


