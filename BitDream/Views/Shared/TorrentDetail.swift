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
    if torrent.statusCalc == TorrentStatusCalc.complete {
        return .green.opacity(0.75)
    }
    else if torrent.statusCalc == TorrentStatusCalc.paused {
        return .gray
    }
    else if torrent.statusCalc == TorrentStatusCalc.retrievingMetadata {
        return .red.opacity(0.75)
    }
    else if torrent.statusCalc == TorrentStatusCalc.stalled {
        return .yellow.opacity(0.7)
    }
    else {
        return .blue.opacity(0.75)
    }
}

// Shared function to fetch torrent files
func fetchTorrentFiles(transferId: Int, store: Store, completion: @escaping ([TorrentFile]) -> Void) {
    let info = makeConfig(store: store)
    
    getTorrentFiles(transferId: transferId, info: info, onReceived: { files in
        completion(files)
    })
}

// Shared function to play/pause a torrent
func toggleTorrentPlayPause(torrent: Torrent, store: Store, completion: @escaping () -> Void = {}) {
    let info = makeConfig(store: store)
    playPauseTorrent(torrent: torrent, config: info.config, auth: info.auth, onResponse: { response in
        // TODO: Handle response
        completion()
    })
}

// Shared function to format torrent details
func formatTorrentDetails(torrent: Torrent) -> (percentComplete: String, percentAvailable: String, downloadedFormatted: String, sizeWhenDoneFormatted: String, activityDate: String, addedDate: String) {
    
    let percentComplete = String(format: "%.1f%%", torrent.percentDone * 100)
    let percentAvailable = String(format: "%.1f%%", ((Double(torrent.haveUnchecked + torrent.haveValid + torrent.desiredAvailable) / Double(torrent.sizeWhenDone))) * 100)
    let downloadedFormatted = byteCountFormatter.string(fromByteCount: (torrent.downloadedCalc))
    let sizeWhenDoneFormatted = byteCountFormatter.string(fromByteCount: torrent.sizeWhenDone)
    
    let activityDate = dateFormatter.string(from: Date(timeIntervalSince1970: Double(torrent.activityDate)))
    let addedDate = dateFormatter.string(from: Date(timeIntervalSince1970: Double(torrent.addedDate)))
    
    return (percentComplete, percentAvailable, downloadedFormatted, sizeWhenDoneFormatted, activityDate, addedDate)
}

// Shared header view for both platforms
struct TorrentDetailHeaderView: View {
    var torrent: Torrent
    
    var body: some View {
        VStack {
            Divider()
            HStack {
                HStack(spacing: 2) {
                    Image(systemName: "arrow.down")
                    Text("\(byteCountFormatter.string(fromByteCount: torrent.rateDownload))/s")
                }
                HStack(spacing: 2) {
                    Image(systemName: "arrow.up")
                    Text("\(byteCountFormatter.string(fromByteCount: torrent.rateUpload))/s")
                }
            }
            .foregroundColor(.secondary)
            .font(.subheadline)
        }
    }
}

// Shared toolbar menu for both platforms
struct TorrentDetailToolbar: ToolbarContent {
    var torrent: Torrent
    var store: Store
    
    var body: some ToolbarContent {
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
    }
}

// Keep the TorrentFileDetail here since it's shared between platforms
struct TorrentFileDetail: View {
    var files: [TorrentFile]
    
    var body: some View {
        List(files) { file in
            VStack {
                let percentComplete = String(format: "%.1f%%", file.percentDone * 100)
                let completedFormatted = byteCountFormatter.string(fromByteCount: (file.bytesCompleted))
                let lengthFormatted = byteCountFormatter.string(fromByteCount: file.length)
                
                let progressText = "\(completedFormatted) of \(lengthFormatted) (\(percentComplete))"
                
                HStack {
                    Text(file.name)
                    Spacer()
                }
                .padding(.bottom, 1)
                HStack {
                    Text(progressText)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
            .listRowInsets(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
            #if os(macOS)
            .listRowSeparator(.visible)
            #endif
        }
    }
}

// Date Formatter
let dateFormatter: DateFormatter = {
    var formatter = DateFormatter()
    formatter.dateFormat = "MM/dd/YYYY"
    
    return formatter
}()
