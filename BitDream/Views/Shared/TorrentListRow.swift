import Foundation
import SwiftUI

struct TorrentListRow: View {
    var torrent: Torrent
    var store: TransmissionStore
    var selectedTorrents: Set<Torrent>
    var showContentTypeIcons: Bool

    var body: some View {
        #if os(iOS)
        iOSTorrentListRow(torrent: torrent, store: store, showContentTypeIcons: showContentTypeIcons)
        #elseif os(macOS)
        macOSTorrentListExpanded(torrent: torrent, store: store, selectedTorrents: selectedTorrents, showContentTypeIcons: showContentTypeIcons)
        #endif
    }
}

// MARK: - Shared Helpers

extension Collection where Element == Torrent {
    var shouldDisablePause: Bool {
        return isEmpty || (count == 1 && first?.status == TorrentStatus.stopped.rawValue)
    }

    var shouldDisableResume: Bool {
        return isEmpty || (count == 1 && first?.status != TorrentStatus.stopped.rawValue)
    }
}

enum TorrentStatusPresentationStyle {
    case standard
}

func torrentStatusSymbol(for torrent: Torrent, style: TorrentStatusPresentationStyle = .standard) -> String {
    switch style {
    case .standard:
        if torrent.error != TorrentError.none.rawValue {
            return "exclamationmark.triangle.fill"
        }

        switch torrent.statusCalc {
        case .downloading, .retrievingMetadata:
            return "arrow.down.circle.fill"
        case .seeding:
            return "arrow.up.circle.fill"
        case .paused:
            return "pause.circle.fill"
        case .complete:
            return "checkmark.circle.fill"
        case .queued:
            return "clock.fill"
        case .verifyingLocalData:
            return "checkmark.arrow.trianglehead.counterclockwise"
        case .stalled:
            return "exclamationmark.circle.fill"
        case .unknown:
            return "questionmark.circle.fill"
        }
    }
}

func torrentStatusTint(for torrent: Torrent) -> Color {
    if torrent.error != TorrentError.none.rawValue {
        return .red
    }

    switch torrent.statusCalc {
    case .downloading, .retrievingMetadata:
        return .blue
    case .seeding, .complete:
        return .green
    case .paused, .unknown:
        return .gray
    case .queued, .stalled:
        return .orange
    case .verifyingLocalData:
        return .purple
    }
}

// Shared function to determine progress color
func progressColorForTorrent(_ torrent: Torrent) -> Color {
    switch torrent.statusCalc {
    case .complete, .seeding:
        return .green.opacity(0.75)
    case .paused, .stalled:
        return .gray
    case .retrievingMetadata:
        return .red.opacity(0.75)
    default:
        return .blue.opacity(0.75)
    }
}

// Shared function to format subtext
func formatTorrentSubtext(_ torrent: Torrent) -> String {
    let percentComplete = String(format: "%.1f%%", torrent.percentDone * 100)
    let downloadedSizeFormatted = formatByteCount(torrent.downloadedCalc)
    let sizeWhenDoneFormatted = formatByteCount(torrent.sizeWhenDone)

    let progressText = "\(downloadedSizeFormatted) of \(sizeWhenDoneFormatted) (\(percentComplete))"

    // Only add ETA for downloading torrents
    if torrent.statusCalc == .downloading {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute, .second]
        formatter.unitsStyle = .full
        formatter.includesTimeRemainingPhrase = true
        formatter.maximumUnitCount = 2

        let etaText = torrent.eta < 0 ? "remaining time unknown" :
            formatter.string(from: TimeInterval(torrent.eta))!

        return "\(progressText) - \(etaText)"
    }

    return progressText
}

// Shared function to create status view content
func createStatusView(for torrent: Torrent) -> some View {
    let rateDownloadFormatted = formatByteCount(torrent.rateDownload)
    let rateUploadFormatted = formatByteCount(torrent.rateUpload)

    return Group {
        if torrent.error != TorrentError.none.rawValue {
            Text("Tracker returned error: \(torrent.errorString)")
                .foregroundColor(.red)
        } else {
            switch torrent.statusCalc {
            case .downloading, .retrievingMetadata:
                HStack(spacing: 4) {
                    Text("\(torrent.statusCalc.rawValue) from \(torrent.peersSendingToUs) of \(torrent.peersConnected) peers")
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 8))
                        Text("\(rateDownloadFormatted)/s")
                    }
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 8))
                        Text("\(rateUploadFormatted)/s")
                    }
                }
            case .seeding:
                HStack(spacing: 4) {
                    Text("\(torrent.statusCalc.rawValue) to \(torrent.peersGettingFromUs) of \(torrent.peersConnected) peers")
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 8))
                        Text("\(rateUploadFormatted)/s")
                    }
                }
            default:
                Text(torrent.statusCalc.rawValue)
            }
        }
    }
}

// Shared function to copy magnet link to clipboard
func copyMagnetLinkToClipboard(_ magnetLink: String) {
    #if os(macOS)
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(magnetLink, forType: .string)
    #elseif os(iOS)
    UIPasteboard.general.string = magnetLink
    #endif
}

// MARK: - Shared Label Components

// Shared function to save labels and refresh torrent data
@MainActor
func saveTorrentLabels(torrentId: Int, labels: Set<String>, store: TransmissionStore, onComplete: @escaping () -> Void = {}) {
    let info = makeConfig(store: store)
    let sortedLabels = Array(labels).sorted()

    // First update the labels
    updateTorrent(
        args: TorrentSetRequestArgs(ids: [torrentId], labels: sortedLabels),
        info: info,
        onComplete: { _ in
            // Trigger an immediate refresh
            store.requestRefresh()
            onComplete()
        }
    )
}

// Shared function to handle adding new tags from input field
@MainActor
func addNewTag(from input: inout String, to workingLabels: inout Set<String>) -> Bool {
    let trimmed = input.trimmingCharacters(in: .whitespaces)
    if !trimmed.isEmpty {
        if !LabelTag.containsLabel(workingLabels, trimmed) {
            workingLabels.insert(trimmed)
            input = ""
            return true
        }
    }
    input = ""
    return false
}

struct LabelTag: View {
    let label: String
    var onRemove: (() -> Void)?

    // Static helper for case-insensitive label comparison
    static func containsLabel(_ labels: Set<String>, _ newLabel: String) -> Bool {
        labels.contains { $0.localizedCaseInsensitiveCompare(newLabel) == .orderedSame }
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)

            if let onRemove = onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.accentColor.opacity(0.15))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.accentColor.opacity(0.4), lineWidth: 1)
        )
    }
}

// Shared function to create label tags view
@MainActor
func createLabelTagsView(for torrent: Torrent) -> some View {
    ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 4) {
            ForEach(torrent.labels.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }, id: \.self) { label in
                LabelTag(label: label)
            }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        var height: CGFloat = 0
        var width: CGFloat = 0
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var maxHeight: CGFloat = 0

        for size in sizes {
            if currentX + size.width > (proposal.width ?? .infinity) {
                currentY += maxHeight + spacing
                currentX = 0
                maxHeight = 0
            }

            currentX += size.width + spacing
            width = max(width, currentX)
            maxHeight = max(maxHeight, size.height)
            height = currentY + maxHeight
        }

        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        var currentX = bounds.minX
        var currentY = bounds.minY
        var maxHeight: CGFloat = 0

        for (index, size) in sizes.enumerated() {
            if currentX + size.width > bounds.maxX {
                currentY += maxHeight + spacing
                currentX = bounds.minX
                maxHeight = 0
            }

            subviews[index].place(
                at: CGPoint(x: currentX, y: currentY),
                proposal: ProposedViewSize(size)
            )

            currentX += size.width + spacing
            maxHeight = max(maxHeight, size.height)
        }
    }
}

// MARK: - Shared Rename Helpers

/// Validate a proposed new name for a torrent root (or file/folder component)
/// - Returns: nil if valid, or a short human-readable error message if invalid
func validateNewName(_ name: String, current: String) -> String? {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
        return "Name cannot be empty."
    }
    if trimmed.contains("/") || trimmed.contains(":") { // avoid path separators and colon (often illegal)
        return "Name cannot contain path separators."
    }
    if trimmed.rangeOfCharacter(from: .controlCharacters) != nil {
        return "Name contains invalid characters."
    }
    return nil
}

/// Rename the torrent root folder/name using Transmission's torrent-rename-path
/// - Parameters:
///   - torrent: The torrent whose root should be renamed
///   - newName: The new root name
///   - store: App store for config/auth and refresh
///   - onComplete: Called with nil on success, or an error message on failure
@MainActor
func renameTorrentRoot(torrent: Torrent, to newName: String, store: TransmissionStore, onComplete: @escaping (String?) -> Void) {
    let info = makeConfig(store: store)
    // For root rename, Transmission expects the current root path (the torrent's name)
    renameTorrentPath(
        torrentId: torrent.id,
        path: torrent.name,
        newName: newName,
        config: info.config,
        auth: info.auth
    ) { result in
        switch result {
        case .success:
            // Refresh to pick up updated name and files
            store.requestRefresh()
            onComplete(nil)
        case .failure(let error):
            onComplete(error.localizedDescription)
        }
    }
}
