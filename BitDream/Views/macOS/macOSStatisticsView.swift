//
//  macOSStatisticsView.swift
//  BitDream
//
//  Displays Transmission session-stats in a simple macOS window.
//

import SwiftUI

#if os(macOS)
struct macOSStatisticsView: View {
    @EnvironmentObject var store: Store

    private let durationFormatter: DateComponentsFormatter = {
        let f = DateComponentsFormatter()
        f.allowedUnits = [.day, .hour, .minute, .second]
        f.unitsStyle = .abbreviated
        f.zeroFormattingBehavior = .dropLeading
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let stats = store.sessionStats {
                Form {
                    Section("Live") {
                        HStack {
                            Text("Torrents")
                            Spacer(minLength: 16)
                            HStack(spacing: 8) {
                                Text("\(stats.activeTorrentCount) Active")
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.secondary)
                                Text("•")
                                    .foregroundColor(.secondary.opacity(0.6))
                                Text("\(stats.pausedTorrentCount) Paused")
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.secondary)
                                Text("•")
                                    .foregroundColor(.secondary.opacity(0.6))
                                Text("\(stats.torrentCount) Total")
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }

                        HStack {
                            Text("Speed")
                            Spacer(minLength: 16)
                            HStack(spacing: 8) {
                                SpeedChip(speed: stats.downloadSpeed, direction: .download, style: .plain, size: .regular)
                                SpeedChip(speed: stats.uploadSpeed, direction: .upload, style: .plain, size: .regular)
                            }
                        }
                    }

                    Section("Current Session") {
                        if let current = stats.currentStats {
                            keyValueRow("Downloaded", byteCountFormatter.string(fromByteCount: current.downloadedBytes))
                            keyValueRow("Uploaded", byteCountFormatter.string(fromByteCount: current.uploadedBytes))
                            keyValueRow("Upload Ratio", String(format: "%.2f", current.downloadedBytes > 0 ? Double(current.uploadedBytes) / Double(current.downloadedBytes) : 0.0))
                            keyValueRow("Files Added", current.filesAdded.formatted())
                            keyValueRow("Active Time", formatDuration(current.secondsActive))
                        } else {
                            placeholderRow()
                        }
                    }

                    Section("Total") {
                        if let cumul = stats.cumulativeStats {
                            keyValueRow("Downloaded", byteCountFormatter.string(fromByteCount: cumul.downloadedBytes))
                            keyValueRow("Uploaded", byteCountFormatter.string(fromByteCount: cumul.uploadedBytes))
                            keyValueRow("Upload Ratio", String(format: "%.2f", cumul.downloadedBytes > 0 ? Double(cumul.uploadedBytes) / Double(cumul.downloadedBytes) : 0.0))
                            keyValueRow("Files Added", cumul.filesAdded.formatted())
                            keyValueRow("Active Time", formatDuration(cumul.secondsActive))
                            keyValueRow("Session Count", String(cumul.sessionCount))
                        } else {
                            placeholderRow()
                        }
                    }
                }
                .formStyle(.grouped)
            } else {
                ContentUnavailableView(
                    "No Data",
                    systemImage: "chart.xyaxis.line",
                    description: Text("Session statistics will appear once a server is connected.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .padding(16)
        .frame(minWidth: 420, minHeight: 320)
    }

    @ViewBuilder
    private func keyValueRow(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key)
            Spacer(minLength: 16)
            Text(value)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private func placeholderRow() -> some View {
        HStack {
            Text("Unavailable")
            Spacer()
            Text("—")
                .foregroundColor(.secondary)
        }
    }

    private func formatDuration(_ seconds: Int64) -> String {
        let clamped = max(0, seconds)
        return durationFormatter.string(from: TimeInterval(clamped)) ?? "0s"
    }
}
#endif
