//
//  iOSTorrentListRow.swift
//  BitDream
//
//  Created by Austin Smith on 12/29/22.
//

import Foundation
import SwiftUI
import KeychainAccess

#if os(iOS)
struct iOSTorrentListRow: View {
    @Binding var torrent: Torrent
    var store: Store
    @Binding var selectedTorrents: Set<Torrent>  // Added for API compatibility
    
    @State var deleteDialog: Bool = false
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack {
            Text(torrent.name)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.bottom, 1)
                .lineLimit(1)
            
            createStatusView(for: torrent)
                .font(.custom("sub", size: 10))
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .foregroundColor(.secondary)
            
            // Logic here is kind of funky, but we are going to fill up the entire progress bar if the
            // torrent is still retrieving metadata (as the bar will be colored red)
            ProgressView(value: torrent.metadataPercentComplete < 1 ? 1 : torrent.percentDone)
                .tint(progressColorForTorrent(torrent))
            
            Text(formatTorrentSubtext(torrent))
                .font(.custom("sub", size: 10))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .foregroundColor(.secondary)
        }
        .contentShape(Rectangle())
        .padding([.top, .bottom, .leading, .trailing], 10)
        .contextMenu {
            // Play/Pause Button
            Button(action: {
                let info = makeConfig(store: store)
                playPauseTorrent(torrent: torrent, config: info.config, auth: info.auth, onResponse: { response in
                    // TODO: Handle response
                })
            }) {
                Label(torrent.status == TorrentStatus.stopped.rawValue ? "Resume Dream" : "Pause Dream", 
                      systemImage: torrent.status == TorrentStatus.stopped.rawValue ? "play" : "pause")
            }
            
            // Priority Menu
            Menu {
                Button(action: {
                    updateTorrentPriority(torrent: torrent, priority: TorrentPriority.high, info: makeConfig(store: store), onComplete: { r in })
                }) {
                    Label("High", systemImage: "arrow.up")
                }
                Button(action: {
                    updateTorrentPriority(torrent: torrent, priority: TorrentPriority.normal, info: makeConfig(store: store), onComplete: { r in })
                }) {
                    Label("Normal", systemImage: "minus")
                }
                Button(action: {
                    updateTorrentPriority(torrent: torrent, priority: TorrentPriority.low, info: makeConfig(store: store), onComplete: { r in })
                }) {
                    Label("Low", systemImage: "arrow.down")
                }
            } label: {
                Label("Update Priority", systemImage: "flag.badge.ellipsis")
            }
            
            Divider()
            
            // Copy Magnet Link Button
            Button(action: {
                copyMagnetLinkToClipboard(torrent.magnetLink)
            }) {
                Label("Copy Magnet Link", systemImage: "document.on.document")
            }
            
            Divider()
            
            // Delete Button
            Button(role: .destructive, action: {
                deleteDialog.toggle()
            }) {
                Label("Delete", systemImage: "trash")
            }
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
}
#else
// Empty struct for macOS to reference - this won't be compiled on macOS but provides the type
struct iOSTorrentListRow: View {
    @Binding var torrent: Torrent
    var store: Store
    @Binding var selectedTorrents: Set<Torrent>
    
    var body: some View {
        EmptyView()
    }
}
#endif 