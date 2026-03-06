import Foundation
import SwiftUI

#if os(iOS)

struct iOSTorrentFileRow: View {
    let row: TorrentFileRow
    let setFileWanted: (TorrentFileRow, Bool) -> Void
    let setFilePriority: (TorrentFileRow, FilePriority) -> Void

    private var progressText: String {
        "\(formatByteCount(row.bytesCompleted)) / \(formatByteCount(row.size)) (\(String(format: "%.1f%%", row.percentDone * 100)))"
    }

    private var progressTint: Color {
        row.percentDone >= 1.0 ? .green : .blue
    }

    private var priority: FilePriority {
        FilePriority(rawValue: row.priority) ?? .normal
    }

    var body: some View {
        VStack {
            HStack {
                Text(row.displayName)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer()
            }
            .padding(.bottom, 4)

            ProgressView(value: row.percentDone)
                .progressViewStyle(.linear)
                .tint(progressTint)

            HStack {
                Text(progressText)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.secondary)

                Spacer()

                if row.wanted {
                    PriorityBadge(priority: priority)
                } else {
                    StatusBadge(wanted: false)
                }

                FileTypeChip(filename: row.name)
            }
        }
        .opacity(row.wanted ? 1.0 : 0.5)
        .swipeActions(edge: .trailing) {
            Menu {
                priorityActionSection
            } label: {
                Image(systemName: "flag")
            }
            .tint(.orange)

            Menu {
                fullActionSections
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
        .contextMenu {
            fullActionSections
        }
    }

    @ViewBuilder
    private var fullActionSections: some View {
        statusActionSection
        priorityActionSection
    }

    private var statusActionSection: some View {
        Section("Status") {
            statusButton("Download", wanted: true)
            statusButton("Don't Download", wanted: false)
        }
    }

    private var priorityActionSection: some View {
        Section("Priority") {
            priorityButton("High Priority", priority: .high)
            priorityButton("Normal Priority", priority: .normal)
            priorityButton("Low Priority", priority: .low)
        }
    }

    private func statusButton(_ title: String, wanted: Bool) -> some View {
        Button(title) {
            setFileWanted(row, wanted)
        }
    }

    private func priorityButton(_ title: String, priority: FilePriority) -> some View {
        Button(title) {
            setFilePriority(row, priority)
        }
    }
}

#endif
