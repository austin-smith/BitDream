//
//  TorrentDetail.swift
//  BitDream
//
//  Created by Austin Smith on 12/29/22.
//

import Foundation
import SwiftUI
import KeychainAccess
import CoreData

struct TorrentDetail: View {
    @ObservedObject var store: Store
    var viewContext: NSManagedObjectContext
    @Binding var torrent: Torrent
    
    var body: some View {
        #if os(iOS)
        iOSTorrentDetail(store: store, viewContext: viewContext, torrent: $torrent)
        #elseif os(macOS)
        macOSTorrentDetail(store: store, viewContext: viewContext, torrent: $torrent)
        #endif
    }
}

// MARK: - Shared Helpers

// Shared function to determine torrent status color
func statusColor(for torrent: Torrent) -> Color {
    if torrent.statusCalc == TorrentStatusCalc.complete || torrent.statusCalc == TorrentStatusCalc.seeding {
        return .green.opacity(0.9)
    }
    else if torrent.statusCalc == TorrentStatusCalc.paused {
        return .gray
    }
    else if torrent.statusCalc == TorrentStatusCalc.retrievingMetadata {
        return .red.opacity(0.9)
    }
    else if torrent.statusCalc == TorrentStatusCalc.stalled {
        return .orange.opacity(0.9)
    }
    else {
        return .blue.opacity(0.9)
    }
}

// Shared function to fetch torrent files
func fetchTorrentFiles(transferId: Int, store: Store, completion: @escaping ([TorrentFile], [TorrentFileStats]) -> Void) {
    let info = makeConfig(store: store)
    
    getTorrentFiles(transferId: transferId, info: info, onReceived: { files, fileStats in
        completion(files, fileStats)
    })
}

// Shared function to fetch torrent peers
func fetchTorrentPeers(transferId: Int, store: Store, completion: @escaping ([Peer], PeersFrom?) -> Void) {
    let info = makeConfig(store: store)
    
    getTorrentPeers(transferId: transferId, info: info, onReceived: { peers, peersFrom in
        completion(peers, peersFrom)
    })
}

// Shared function to play/pause a torrent
func toggleTorrentPlayPause(torrent: Torrent, store: Store, completion: @escaping () -> Void = {}) {
    let info = makeConfig(store: store)
    playPauseTorrent(torrent: torrent, config: info.config, auth: info.auth, onResponse: { response in
        handleTransmissionResponse(response,
            onSuccess: {
                completion()
            },
            onError: { _ in
                // For play/pause operations, we'll silently fail and still call completion
                // since the UI should update regardless to reflect current state
                completion()
            }
        )
    })
}

// Shared function to format torrent details
func formatTorrentDetails(torrent: Torrent) -> (percentComplete: String, percentAvailable: String, downloadedFormatted: String, sizeWhenDoneFormatted: String, uploadedFormatted: String, uploadRatio: String, activityDate: String, addedDate: String) {
    
    let percentComplete = String(format: "%.1f%%", torrent.percentDone * 100)
    let percentAvailable = String(format: "%.1f%%", ((Double(torrent.haveUnchecked + torrent.haveValid + torrent.desiredAvailable) / Double(torrent.sizeWhenDone))) * 100)
    let downloadedFormatted = byteCountFormatter.string(fromByteCount: (torrent.downloadedCalc))
    let sizeWhenDoneFormatted = byteCountFormatter.string(fromByteCount: torrent.sizeWhenDone)
    let uploadedFormatted = byteCountFormatter.string(fromByteCount: torrent.uploadedEver)
    let uploadRatio = String(format: "%.2f", torrent.uploadRatio)
    
    let activityDate = dateFormatter.string(from: Date(timeIntervalSince1970: Double(torrent.activityDate)))
    let addedDate = dateFormatter.string(from: Date(timeIntervalSince1970: Double(torrent.addedDate)))
    
    return (percentComplete, percentAvailable, downloadedFormatted, sizeWhenDoneFormatted, uploadedFormatted, uploadRatio, activityDate, addedDate)
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
    var store: Store
    
    var body: some ToolbarContent {
        #if os(macOS)
        ToolbarItem {
            TorrentActionsToolbarMenu(
                store: store,
                selectedTorrents: store.selectedTorrents
            )
        }
        #else
        ToolbarItem {
            Menu {
                Button(action: {
                    toggleTorrentPlayPause(torrent: torrent, store: store)
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

// Date Formatter
let dateFormatter: DateFormatter = {
    var formatter = DateFormatter()
    formatter.dateFormat = "MM/dd/YYYY"
    
    return formatter
}()
