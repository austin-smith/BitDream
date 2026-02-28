import SwiftUI

#if os(macOS)

struct macOSMenuBarTransferRow: View {
    let torrent: Torrent
    let onOpen: () -> Void

    private var progressValue: Double {
        torrent.metadataPercentComplete < 1 ? 1 : torrent.percentDone
    }

    private var progressPercentText: String {
        String(format: "%.1f%%", torrent.percentDone * 100)
    }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: statusIcon)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(statusTint)

                    Text(torrent.name)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 0)

                    Text(torrent.statusCalc.rawValue)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                ProgressView(value: progressValue)
                    .progressViewStyle(.linear)
                    .tint(progressColorForTorrent(torrent))

                HStack(spacing: 10) {
                    Text(progressPercentText)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 3) {
                        Image(systemName: "arrow.down")
                        Text(formatSpeed(torrent.rateDownload))
                    }
                    .foregroundStyle(.blue)

                    HStack(spacing: 3) {
                        Image(systemName: "arrow.up")
                        Text(formatSpeed(torrent.rateUpload))
                    }
                    .foregroundStyle(.green)

                    Spacer(minLength: 0)
                }
                .font(.system(size: 10, design: .monospaced))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.secondary.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
    }

    private var statusIcon: String {
        switch torrent.statusCalc {
        case .downloading:
            return "arrow.down.circle.fill"
        case .retrievingMetadata:
            return "arrow.clockwise.circle.fill"
        case .seeding:
            return "arrow.up.circle.fill"
        case .verifyingLocalData:
            return "checkmark.arrow.trianglehead.counterclockwise"
        default:
            return "circle.fill"
        }
    }

    private var statusTint: Color {
        switch torrent.statusCalc {
        case .downloading, .retrievingMetadata:
            return .blue
        case .seeding:
            return .green
        case .verifyingLocalData:
            return .orange
        default:
            return .secondary
        }
    }
}

#endif
