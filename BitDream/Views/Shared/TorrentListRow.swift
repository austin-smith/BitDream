//
//  TorrentListRow.swift
//  BitDream
//
//  Created by Austin Smith on 12/29/22.
//

import Foundation
import SwiftUI
import KeychainAccess

struct TorrentListRow: View {
    @Binding var torrent: Torrent
    var store: Store
    @Binding var selectedTorrents: Set<Torrent>
    
    var body: some View {
        #if os(iOS)
        iOSTorrentListRow(torrent: $torrent, store: store, selectedTorrents: $selectedTorrents)
        #elseif os(macOS)
        macOSTorrentListRow(torrent: $torrent, store: store, selectedTorrents: $selectedTorrents)
        #endif
    }
}

// MARK: - Shared Helpers

// Shared function to determine progress color
func progressColorForTorrent(_ torrent: Torrent) -> Color {
    switch torrent.statusCalc {
    case .complete, .seeding:
        return .green.opacity(0.75)
    case .paused:
        return .gray
    case .retrievingMetadata:
        return .red.opacity(0.75)
    case .stalled:
        return .yellow.opacity(0.7)
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