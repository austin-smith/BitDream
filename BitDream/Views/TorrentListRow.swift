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
    
    @State var deleteDialog: Bool = false
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack {
            Text(torrent.name)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.bottom, 1)
                .lineLimit(1)
//                    .foregroundColor(fontColor)
            
            statusView
                .font(.custom("sub", size: 10))
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .foregroundColor(.secondary)
            
            // Logic here is kind of funky, but we are going to fill up the entire progress bar if the
            // torrent is still retrieving metadata (as the bar will be colored red)
            ProgressView(value: torrent.metadataPercentComplete < 1 ? 1 : torrent.percentDone)
                .tint(progressColor)
            
            Text(subtext)
                .font(.custom("sub", size: 10))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .foregroundColor(.secondary)
        }
        .contentShape(Rectangle())
        .padding([.top, .bottom, .leading, .trailing], 10)
        .contextMenu {
            Button(action: {
                let info = makeConfig(store: store)
                playPauseTorrent(torrent: torrent, config: info.config, auth: info.auth, onResponse: { response in
                    // TODO: Handle response
                })
            }) {
                Label(torrent.status == TorrentStatus.stopped.rawValue ? "Resume Dream" : "Pause Dream", systemImage: torrent.status == TorrentStatus.stopped.rawValue ? "play" : "pause")
            }
            
            Menu {
                Button(action: {
                    updateTorrentPriority(torrent: torrent, priority: TorrentPriority.high, info: makeConfig(store: store), onComplete: { r in })
                }) {
                    Label("High", systemImage: "hand.point.up")
                }
                Button(action: {
                    updateTorrentPriority(torrent: torrent, priority: TorrentPriority.normal, info: makeConfig(store: store), onComplete: { r in })
                }) {
                    Label("Medium", systemImage: "hand.raised")
                }
                Button(action: {
                    updateTorrentPriority(torrent: torrent, priority: TorrentPriority.low, info: makeConfig(store: store), onComplete: { r in })
                }) {
                    Label("Low", systemImage: "hand.point.down")
                }
            } label: {
                Label("Update Priority", systemImage: "flag.badge.ellipsis")
            }
            
            Divider()
            
            Button(role: .destructive, action: {
                deleteDialog.toggle()
            }) {
                Label("Delete", systemImage: "trash")
            }
            
            // Button("Download", action: {
            // TODO: Download the destination folder using sftp library
            // })
        }
        .id(torrent.id)
        // Ask to delete files on disk when removing transfer
        .alert(
            "Delete Torrent",
            isPresented: $deleteDialog) {
                Button(role: .destructive) {
                    let info = makeConfig(store: store)
                    deleteTorrent(torrent: torrent, erase: true, config: info.config, auth: info.auth, onDel: { response in
                        // TODO: Handle response
                    })
                    deleteDialog.toggle()
                } label: {
                    Text("Delete file(s)")
                }
                Button("Remove from list only") {
                    let info = makeConfig(store: store)
                    deleteTorrent(torrent: torrent, erase: false, config: info.config, auth: info.auth, onDel: { response in
                        // TODO: Handle response
                    })
                    deleteDialog.toggle()
                }
            } message: {
                Text("Do you want to delete the file(s) from the disk?")
            }
            .interactiveDismissDisabled(false)
        .listRowBackground(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.white)
        )
    }
    
    // New computed property for the status view with SF Symbols
    private var statusView: some View {
        let rateDownloadFormatted = byteCountFormatter.string(fromByteCount: torrent.rateDownload)
        let rateUploadFormatted = byteCountFormatter.string(fromByteCount: torrent.rateUpload)
        
        return Group {
            switch torrent.statusCalc {
            case TorrentStatusCalc.downloading, TorrentStatusCalc.retrievingMetadata:
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
            case TorrentStatusCalc.seeding:
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
    
    private var subtext: String {
        let percentComplete = String(format: "%.1f%%", torrent.percentDone * 100)
        let downloadedSizeFormatted = byteCountFormatter.string(fromByteCount: (torrent.downloadedCalc))
        let sizeWhenDoneFormatted = byteCountFormatter.string(fromByteCount: torrent.sizeWhenDone)
        
        // formatter for eta remaining time
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute, .second]
        formatter.unitsStyle = .full
        formatter.includesTimeRemainingPhrase = true
        formatter.maximumUnitCount = 2
        
        let progressText = "\(downloadedSizeFormatted) of \(sizeWhenDoneFormatted) (\(percentComplete))"
        
        let etaFormatted = {
            switch torrent.eta {
            case -1, -2:
                return "remaining time unknown"
            default:
                return formatter.string(from: TimeInterval(torrent.eta))!
            }
        }()

        if torrent.statusCalc == TorrentStatusCalc.downloading {
            return "\(progressText) - \(etaFormatted)"
        }
        else {
            return progressText
        }
    }        

//    private var fontColor : Color {
//        if torrent.statusCalc == TorrentStatusCalc.complete {
//            return .green.opacity(0.75)
//        }
//        if torrent.statusCalc == TorrentStatusCalc.paused {
//            return .gray
//        }
//        else if colorScheme == .dark {
//            return .white
//        }
//        else {
//            return .black
//        }
//    }
    
    private var progressColor: Color {
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
}
