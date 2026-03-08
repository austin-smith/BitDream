import Foundation
import SwiftUI

struct TorrentDetail: View {
    @ObservedObject var store: TransmissionStore
    var torrent: Torrent

    var body: some View {
        #if os(iOS)
        iOSTorrentDetail(store: store, torrent: torrent)
        #elseif os(macOS)
        macOSTorrentDetail(store: store, torrent: torrent)
        #endif
    }
}

// MARK: - Shared Helpers

// Shared function to determine torrent status color
func statusColor(for torrent: Torrent) -> Color {
    if torrent.statusCalc == TorrentStatusCalc.complete || torrent.statusCalc == TorrentStatusCalc.seeding {
        return .green.opacity(0.9)
    } else if torrent.statusCalc == TorrentStatusCalc.paused {
        return .gray
    } else if torrent.statusCalc == TorrentStatusCalc.retrievingMetadata {
        return .red.opacity(0.9)
    } else if torrent.statusCalc == TorrentStatusCalc.stalled {
        return .orange.opacity(0.9)
    } else {
        return .blue.opacity(0.9)
    }
}

struct TorrentDetailsDisplay {
    let percentComplete: String
    let percentAvailable: String
    let downloadedFormatted: String
    let sizeWhenDoneFormatted: String
    let uploadedFormatted: String
    let uploadRatio: String
    let activityDate: String
    let addedDate: String
}

// Shared function to format torrent details
func formatTorrentDetails(torrent: Torrent) -> TorrentDetailsDisplay {

    let percentComplete = String(format: "%.1f%%", torrent.percentDone * 100)
    let percentAvailable = String(format: "%.1f%%", ((Double(torrent.haveUnchecked + torrent.haveValid + torrent.desiredAvailable) / Double(torrent.sizeWhenDone))) * 100)
    let downloadedFormatted = formatByteCount(torrent.downloadedCalc)
    let sizeWhenDoneFormatted = formatByteCount(torrent.sizeWhenDone)
    let uploadedFormatted = formatByteCount(torrent.uploadedEver)
    let uploadRatio = String(format: "%.2f", torrent.uploadRatio)

    let activityDate = formatTorrentDetailDate(torrent.activityDate)
    let addedDate = formatTorrentDetailDate(torrent.addedDate)

    return TorrentDetailsDisplay(
        percentComplete: percentComplete,
        percentAvailable: percentAvailable,
        downloadedFormatted: downloadedFormatted,
        sizeWhenDoneFormatted: sizeWhenDoneFormatted,
        uploadedFormatted: uploadedFormatted,
        uploadRatio: uploadRatio,
        activityDate: activityDate,
        addedDate: addedDate
    )
}

// Shared header view for both platforms
struct TorrentDetailHeaderView: View {
    var torrent: Torrent

    var body: some View {
        HStack {
            Spacer()

            HStack(spacing: 8) {
                RatioChip(
                    ratio: torrent.uploadRatio,
                    size: .compact
                )

                SpeedChip(
                    speed: torrent.rateDownload,
                    direction: .download,
                    style: .chip,
                    size: .compact
                )

                SpeedChip(
                    speed: torrent.rateUpload,
                    direction: .upload,
                    style: .chip,
                    size: .compact
                )
            }

            Spacer()
        }
    }
}

// Shared toolbar menu for both platforms
struct TorrentDetailToolbar: ToolbarContent {
    var torrent: Torrent
    var store: TransmissionStore

    var body: some ToolbarContent {
        #if os(macOS)
        ToolbarItem {
            // In detail view, actions apply to the displayed torrent
            TorrentActionsToolbarMenu(
                store: store,
                selectedTorrents: Set([torrent])
            )
        }
        #else
        ToolbarItem {
            Menu {
                Button(action: {
                    performTransmissionAction(
                        operation: { try await store.toggleTorrentPlayback(torrent) },
                        onError: makeTransmissionDebugErrorHandler(
                            store: store,
                            context: torrent.status == TorrentStatus.stopped.rawValue
                                ? .resumeTorrents
                                : .pauseTorrents
                        )
                    )
                }, label: {
                    HStack {
                        Text(torrent.status == TorrentStatus.stopped.rawValue ? "Resume Dream" : "Pause Dream")
                    }
                })
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
        #endif
    }
}

// Shared status badge component for torrent status
struct TorrentStatusBadge: View {
    let torrent: Torrent

    var body: some View {
        Text(torrent.statusCalc.rawValue)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundColor(statusColor(for: torrent))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(statusColor(for: torrent).opacity(0.15))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(statusColor(for: torrent).opacity(0.3), lineWidth: 0.5)
            )
            .cornerRadius(6)
    }
}

private func formatTorrentDetailDate(_ timestamp: Int) -> String {
    let date = Date(timeIntervalSince1970: Double(timestamp))
    return date.formatted(
        Date.FormatStyle()
            .locale(Locale(identifier: "en_US_POSIX"))
            .month(.twoDigits)
            .day(.twoDigits)
            .year(.defaultDigits)
    )
}
