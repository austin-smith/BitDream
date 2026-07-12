import SwiftUI

#if os(iOS)
struct iOSStatisticsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.hapticFeedback) private var hapticFeedback
    @ObservedObject var store: TransmissionStore

    var body: some View {
        Group {
            if let statistics = store.sessionStats {
                Form {
                    iOSStatisticsLiveSection(statistics: statistics)
                    iOSStatisticsPeriodSection(
                        title: "Current Session",
                        statistics: statistics.currentStats,
                        showsSessionCount: false
                    )
                    iOSStatisticsPeriodSection(
                        title: "Total",
                        statistics: statistics.cumulativeStats,
                        showsSessionCount: true
                    )
                }
                .formStyle(.grouped)
            } else {
                ContentUnavailableView(
                    "No Data",
                    systemImage: "chart.xyaxis.line",
                    description: Text("Session statistics will appear once a server is connected.")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Statistics")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    hapticFeedback.play(.actionTriggered)
                    dismiss()
                }
            }
        }
    }
}

private struct iOSStatisticsLiveSection: View {
    let statistics: SessionStats

    var body: some View {
        Section("Live") {
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text("Torrents")
                        .fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 16)
                    horizontalTorrentCounts
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Torrents")

                    ViewThatFits(in: .horizontal) {
                        horizontalTorrentCounts
                        verticalTorrentCounts
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "Torrents, \(statistics.activeTorrentCount.formatted()) active, "
                    + "\(statistics.pausedTorrentCount.formatted()) paused, "
                    + "\(statistics.torrentCount.formatted()) total"
            )

            ViewThatFits(in: .horizontal) {
                HStack {
                    Text("Speed")
                    Spacer(minLength: 16)
                    speedChips
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Speed")
                    speedChips
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
    }

    private var horizontalTorrentCounts: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            iOSTorrentCountValue(count: statistics.activeTorrentCount, label: "Active")
            iOSTorrentCountSeparator()
            iOSTorrentCountValue(count: statistics.pausedTorrentCount, label: "Paused")
            iOSTorrentCountSeparator()
            iOSTorrentCountValue(count: statistics.torrentCount, label: "Total")
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var verticalTorrentCounts: some View {
        VStack(spacing: 8) {
            iOSStatisticsMetricRow(label: "Active", value: statistics.activeTorrentCount.formatted())
            iOSStatisticsMetricRow(label: "Paused", value: statistics.pausedTorrentCount.formatted())
            iOSStatisticsMetricRow(label: "Total", value: statistics.torrentCount.formatted())
        }
    }

    private var speedChips: some View {
        HStack(spacing: 8) {
            SpeedChip(
                speed: statistics.downloadSpeed,
                direction: .download,
                style: .plain,
                size: .regular
            )
            SpeedChip(
                speed: statistics.uploadSpeed,
                direction: .upload,
                style: .plain,
                size: .regular
            )
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

private struct iOSTorrentCountValue: View {
    let count: Int
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(count.formatted())
                .font(.system(.body, design: .monospaced))
                .monospacedDigit()
            Text(label)
                .font(.caption)
        }
        .foregroundStyle(.secondary)
    }
}

private struct iOSTorrentCountSeparator: View {
    var body: some View {
        Text("•")
            .foregroundStyle(.secondary.opacity(0.6))
            .accessibilityHidden(true)
    }
}

private struct iOSStatisticsPeriodSection: View {
    let title: String
    let statistics: TransmissionCumulativeStats?
    let showsSessionCount: Bool

    var body: some View {
        Section(title) {
            if let statistics {
                iOSStatisticsMetricRow(
                    label: "Downloaded",
                    value: formatByteCount(statistics.downloadedBytes)
                )
                iOSStatisticsMetricRow(
                    label: "Uploaded",
                    value: formatByteCount(statistics.uploadedBytes)
                )
                iOSStatisticsMetricRow(
                    label: "Upload Ratio",
                    value: formatTransferRatio(
                        uploadedBytes: statistics.uploadedBytes,
                        downloadedBytes: statistics.downloadedBytes
                    )
                )
                iOSStatisticsMetricRow(
                    label: "Files Added",
                    value: statistics.filesAdded.formatted()
                )
                iOSStatisticsMetricRow(
                    label: "Active Time",
                    value: formatActiveDuration(statistics.secondsActive)
                )

                if showsSessionCount {
                    iOSStatisticsMetricRow(
                        label: "Session Count",
                        value: statistics.sessionCount.formatted()
                    )
                }
            } else {
                iOSStatisticsMetricRow(label: "Unavailable", value: "—")
            }
        }
    }
}

private struct iOSStatisticsMetricRow: View {
    let label: String
    let value: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                Text(label)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 16)
                valueText
                    .fixedSize(horizontal: true, vertical: false)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                valueText
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private var valueText: some View {
        Text(value)
            .font(.system(.body, design: .monospaced))
            .foregroundStyle(.secondary)
    }
}

#if DEBUG
#Preview("iOS Statistics — Connected") {
    PreviewContainer { environment in
        NavigationStack {
            iOSStatisticsView(store: environment.store)
        }
    }
}

#Preview("iOS Statistics — Accessibility Text") {
    PreviewContainer { environment in
        NavigationStack {
            iOSStatisticsView(store: environment.store)
        }
        .environment(\.dynamicTypeSize, .accessibility3)
    }
}
#endif
#endif
