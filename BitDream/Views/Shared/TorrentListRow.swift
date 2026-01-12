import Foundation
import SwiftUI
import KeychainAccess

struct TorrentListRow: View {
    var torrent: Torrent
    var store: Store
    var selectedTorrents: Set<Torrent>
    var showContentTypeIcons: Bool

    var body: some View {
        #if os(iOS)
        iOSTorrentListRow(torrent: torrent, store: store, selectedTorrents: selectedTorrents, showContentTypeIcons: showContentTypeIcons)
        #elseif os(macOS)
        macOSTorrentListExpanded(torrent: torrent, store: store, selectedTorrents: selectedTorrents, showContentTypeIcons: showContentTypeIcons)
        #endif
    }
}

// MARK: - Shared Helpers

struct EtaSortKey: Comparable {
    let priority: Int
    let eta: Int

    static func < (lhs: EtaSortKey, rhs: EtaSortKey) -> Bool {
        if lhs.priority != rhs.priority {
            return lhs.priority < rhs.priority
        }
        return lhs.eta < rhs.eta
    }
}

func makeEtaSortKey(for torrent: Torrent) -> EtaSortKey {
    let priority: Int
    if torrent.statusCalc == .complete { priority = 5 }
    else if torrent.statusCalc == .seeding { priority = 4 }
    else if torrent.statusCalc == .paused { priority = 3 }
    else if torrent.statusCalc == .stalled { priority = 2 }
    else if torrent.eta <= 0 { priority = 1 }
    else { priority = 0 }
    return EtaSortKey(priority: priority, eta: torrent.eta)
}

// Shared function to handle re-announce action
func reAnnounceToTrackers(torrent: Torrent, store: Store, onResponse: @escaping (TransmissionResponse) -> Void = { _ in }) {
    let info = makeConfig(store: store)
    reAnnounceTorrent(torrent: torrent, config: info.config, auth: info.auth, onResponse: onResponse)
}

// Shared function to handle "Resume Now" action
func resumeTorrentNow(torrent: Torrent, store: Store, onResponse: @escaping (TransmissionResponse) -> Void = { _ in }) {
    let info = makeConfig(store: store)
    startTorrentNow(torrent: torrent, config: info.config, auth: info.auth, onResponse: onResponse)
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
    let downloadedSizeFormatted = byteCountFormatter.string(fromByteCount: torrent.downloadedCalc)
    let sizeWhenDoneFormatted = byteCountFormatter.string(fromByteCount: torrent.sizeWhenDone)

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
    let rateDownloadFormatted = byteCountFormatter.string(fromByteCount: torrent.rateDownload)
    let rateUploadFormatted = byteCountFormatter.string(fromByteCount: torrent.rateUpload)

    return Group {
        if (torrent.error != TorrentError.ok.rawValue) {
            Text("Tracker returned error: \(torrent.errorString)")
                .foregroundColor(.red)
        }
        else {
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
func saveTorrentLabels(torrentId: Int, labels: Set<String>, store: Store, onComplete: @escaping () -> Void = {}) {
    let info = makeConfig(store: store)
    let sortedLabels = Array(labels).sorted()

    // First update the labels
    updateTorrent(
        args: TorrentSetRequestArgs(ids: [torrentId], labels: sortedLabels),
        info: info,
        onComplete: { _ in
            // Trigger an immediate refresh
            refreshTransmissionData(store: store)
            onComplete()
        }
    )
}

// Shared function to handle adding new tags from input field
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
        var x: CGFloat = 0
        var y: CGFloat = 0
        var maxHeight: CGFloat = 0

        for size in sizes {
            if x + size.width > (proposal.width ?? .infinity) {
                y += maxHeight + spacing
                x = 0
                maxHeight = 0
            }

            x += size.width + spacing
            width = max(width, x)
            maxHeight = max(maxHeight, size.height)
            height = y + maxHeight
        }

        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        var x = bounds.minX
        var y = bounds.minY
        var maxHeight: CGFloat = 0

        for (index, size) in sizes.enumerated() {
            if x + size.width > bounds.maxX {
                y += maxHeight + spacing
                x = bounds.minX
                maxHeight = 0
            }

            subviews[index].place(
                at: CGPoint(x: x, y: y),
                proposal: ProposedViewSize(size)
            )

            x += size.width + spacing
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
func renameTorrentRoot(torrent: Torrent, to newName: String, store: Store, onComplete: @escaping (String?) -> Void) {
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
        case .success(_):
            // Refresh to pick up updated name and files
            refreshTransmissionData(store: store)
            onComplete(nil)
        case .failure(let error):
            onComplete(error.localizedDescription)
        }
    }
}
