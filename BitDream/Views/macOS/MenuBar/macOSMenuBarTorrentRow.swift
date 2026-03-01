import SwiftUI

#if os(macOS)

struct macOSMenuBarTorrentRow: View {
    let torrent: Torrent
    let onOpen: () -> Void

    private var progressValue: Double {
        torrent.metadataPercentComplete < 1 ? 1 : torrent.percentDone
    }

    private var progressPercentText: String {
        String(format: "%.1f%%", torrent.percentDone * 100)
    }

    private var etaText: String? {
        guard torrent.eta >= 0 else {
            return nil
        }

        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2

        guard let formatted = formatter.string(from: TimeInterval(torrent.eta)) else {
            return nil
        }
        return "ETA \(formatted)"
    }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: torrentStatusSymbol(for: torrent))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(torrentStatusTint(for: torrent))

                    Text(torrent.name)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 0)
                }

                HStack(spacing: 8) {
                    ProgressView(value: progressValue)
                        .progressViewStyle(.linear)
                        .tint(progressColorForTorrent(torrent))

                    Text(progressPercentText)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
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

                    if let etaText {
                        Text(etaText)
                            .foregroundStyle(.secondary)
                    }
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
}

#endif
