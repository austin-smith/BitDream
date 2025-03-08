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
    @Environment(\.dismiss) private var dismiss
    
    @ObservedObject var store: Store
    var viewContext: NSManagedObjectContext
    @Binding var torrent: Torrent
    
    @State public var files: [TorrentFile] = []
    @State var isNameFullText = false
    
    var body: some View {
        
        let percentComplete = String(format: "%.1f%%", torrent.percentDone * 100)
        let percentAvailable = String(format: "%.1f%%", ((Double(torrent.haveUnchecked + torrent.haveValid + torrent.desiredAvailable) / Double(torrent.sizeWhenDone))) * 100)
        let downloadedSizeFormatted = byteCountFormatter.string(fromByteCount: (torrent.downloadedCalc))
        let sizeWhenDoneFormatted = byteCountFormatter.string(fromByteCount: torrent.sizeWhenDone)
        
        let activityDate = dateFormatter.string(from: Date(timeIntervalSince1970: Double(torrent.activityDate)))
        let addedDate = dateFormatter.string(from: Date(timeIntervalSince1970: Double(torrent.addedDate)))
        
        NavigationStack {
            VStack {
                Divider()
                HStack {
                    Text(String("▼ \(byteCountFormatter.string(fromByteCount: torrent.rateDownload))/s"))
                    Text(String("▲ \(byteCountFormatter.string(fromByteCount: torrent.rateUpload))/s"))
                    
                }
                .foregroundColor(.secondary)
                .font(.subheadline)
                #if os(macOS)
                Form {
                    VStack {
                        HStack {
                            Text("General")
                                .font(.title2)
                                .bold()
                        }.padding(.bottom)
                        HStack(alignment: .top) {
                            Text("Name")
                            Spacer(minLength: 50)
                            Text(torrent.name)
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.trailing)
                                .lineLimit(5)
                        }
                        Divider()
                        HStack {
                            Text("Status")
                            Spacer()
                            Image(systemName: "circle.fill")
                                .foregroundColor(statusColor)
                                .font(.system(size: 12))
                            Text(torrent.statusCalc.rawValue)
                                .foregroundColor(.gray)
                        }
                        Divider()
                        HStack {
                            Text("Date Added")
                            Spacer()
                            Text(addedDate)
                                .foregroundColor(.gray)
                        }
                        Divider()
                        NavigationLink(destination: TorrentFileDetail(files: files)) {
                            HStack {
                                Text("Files")
                                Spacer()
                                Text("\(files.count)")
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                    .padding(.horizontal).padding(.vertical)
                    
                    VStack {
                        HStack {
                            Text("Stats")
                                .font(.title2)
                                .bold()
                        }.padding(.bottom)
                        HStack {
                            Text("Downloaded")
                            Spacer()
                            Text(downloadedSizeFormatted)
                                .foregroundColor(.gray)
                        }
                        Divider()
                        HStack {
                            Text("Size When Done")
                            Spacer()
                            Text(sizeWhenDoneFormatted)
                                .foregroundColor(.gray)
                        }
                        Divider()
                        HStack {
                            Text("Progress")
                            Spacer()
                            Text(String(percentComplete))
                                .foregroundColor(.gray)
                        }
                    }
                    .padding(.horizontal).padding(.vertical)
                        
                    VStack {
                        HStack {
                            Text("Availability")
                            Spacer()
                            Text(String(percentAvailable))
                                .foregroundColor(.gray)
                        }
                        Divider()
                        HStack {
                            Text("Last Activity")
                            Spacer()
                            Text(String(activityDate))
                                .foregroundColor(.gray)
                        }
                    }
                    .padding(.horizontal).padding(.vertical)
                    
                    Button(role: .destructive, action: {
                        //                    viewContext.delete(torrent.self)
                        //                    try? viewContext.save()
                        //                    dismiss()
                    }, label: {
                        HStack{
                            Image(systemName: "trash")
                            Text("Delete Dream")
                            Spacer()
                        }
                    })
                    .padding(.horizontal).padding(.vertical)
                }
                .padding()
                Spacer()
                #else
                Form {
                    Section(header: Text("General")) {
                        HStack(alignment: .top) {
                            Text("Name")
                            Spacer(minLength: 50)
                            Text(torrent.name)
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.trailing)
                                .lineLimit(5)
                        }
                        HStack {
                            Text("Status")
                            Spacer()
                            Image(systemName: "circle.fill")
                                .foregroundColor(statusColor)
                                .font(.system(size: 12))
                            Text(torrent.statusCalc.rawValue)
                                .foregroundColor(.gray)
                        }
                        HStack {
                            Text("Date Added")
                            Spacer()
                            Text(addedDate)
                                .foregroundColor(.gray)
                        }
                        NavigationLink(destination: TorrentFileDetail(files: files)) {
                            HStack {
                                Text("Files")
                                Spacer()
                                Text("\(files.count)")
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                    
                    Section(header: Text("Stats")) {
                        HStack {
                            Text("Downloaded")
                            Spacer()
                            Text(downloadedSizeFormatted)
                                .foregroundColor(.gray)
                        }
                        HStack {
                            Text("Size When Done")
                            Spacer()
                            Text(sizeWhenDoneFormatted)
                                .foregroundColor(.gray)
                        }
                        HStack {
                            Text("Progress")
                            Spacer()
                            Text(String(percentComplete))
                                .foregroundColor(.gray)
                        }
                    }
                    
                    Section {
                        HStack {
                            Text("Availability")
                            Spacer()
                            Text(String(percentAvailable))
                                .foregroundColor(.gray)
                        }
                        HStack {
                            Text("Last Activity")
                            Spacer()
                            Text(String(activityDate))
                                .foregroundColor(.gray)
                        }
                    }
                    
                    Button(role: .destructive, action: {
                        //                    viewContext.delete(torrent.self)
                        //                    try? viewContext.save()
                        //                    dismiss()
                    }, label: {
                        HStack {
                            HStack{
                                Image(systemName: "trash")
                                Text("Delete Dream")
                                Spacer()
                            }
                        }
                    })
                }
                #endif
            }
            .onAppear{
                self.getFiles(transferId: torrent.id, store: store)
            }
            .toolbar {
                ToolbarItem {
                    Menu {
                        Button(action: {
                            let info = makeConfig(store: store)
                            playPauseTorrent(torrent: torrent, config: info.config, auth: info.auth, onResponse: { response in
                                // TODO: Handle response
                            })
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
    }
    
    private func getFiles (transferId: Int, store: Store) {
        let info = makeConfig(store: store)
        
        getTorrentFiles(transferId: transferId, info: info, onReceived: { file in
           files = file
        })
    }
    
    private var statusColor: Color {
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
                        .foregroundColor(.gray)
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
