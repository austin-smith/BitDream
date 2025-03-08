//
//  ContentView.swift
//  BitDream
//
//  Created by Austin Smith on 12/29/22.
//

import SwiftUI
import Foundation
import KeychainAccess

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        entity: Host.entity(),
        sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)]
    ) var hosts: FetchedResults<Host>

    @ObservedObject var store: Store = Store()

    private var keychain = Keychain(service: "crapshack.BitDream")

    @State var torrentSelection: Torrent?
    @State var sortBySelection: sortBy = .name
    @State var filterBySelection: [TorrentStatusCalc] = TorrentStatusCalc.allCases

    var body: some View {
        NavigationSplitView {
       // } content: {
            VStack {
                Divider()
                HStack {
                    Text(String("\(store.sessionStats?.activeTorrentCount ?? 0) active dreams"))
                    Spacer()
                    Text(String("▼ \(byteCountFormatter.string(fromByteCount: store.sessionStats?.downloadSpeed ?? 0))/s"))
                    Text(String("▲ \(byteCountFormatter.string(fromByteCount: store.sessionStats?.uploadSpeed ?? 0))/s"))

                }
                .font(.subheadline)
                .padding([.leading, .trailing])
                Divider()
            }
            VStack {
                List {
                    #if os(iOS)
                    ForEach(sortTorrents(store.torrents.filter() {filterBySelection.contains([$0.statusCalc])}, sortBy: sortBySelection), id:\.id) { torrent in
                        NavigationLink(destination: TorrentDetail(store: store, viewContext: viewContext, torrent: binding(for: torrent))) {
                            TorrentListRow(torrent: binding(for: torrent), store: store)
                        }
                    }
                    #else
                    ForEach(sortTorrents(store.torrents.filter() {filterBySelection.contains([$0.statusCalc])}, sortBy: sortBySelection), id:\.id) { torrent in
                        NavigationLink(destination: TorrentDetail(store: store, viewContext: viewContext, torrent: binding(for: torrent))) {
                            TorrentListRow(torrent: binding(for: torrent), store: store)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    torrentSelection = torrent
                                }
                                .listRowSeparator(.hidden)
                        }
                        .listRowSeparator(.visible)
                      //      .listRowBackground(torrent == torrentSelection ? Color.accentColor.opacity(0.5) : Color(.clear))
                        .listRowBackground(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(torrent == torrentSelection ? Color.accentColor.opacity(0.5) : Color(.clear))
                                .padding(.leading, 12)
                        )
                    }
                    #endif
                }
                .padding(.trailing, 12)
            }
            #if os(iOS)
            .listStyle(PlainListStyle())
            #endif
            .refreshable {
                updateList(store: store, update: {_ in})
            }
            .onAppear(perform: {
                hosts.forEach { h in
                    if (h.isDefault) {
                        store.setHost(host: h)
                    }
                }
                if (store.host != nil) {
                    store.startTimer()
                } else {
                    // Create a new host
                    store.setup = true
                }
            })
            #if os(iOS)
            .navigationBarTitle(Text("Dreams"), displayMode: .inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Menu {
                        Menu {
                            ForEach(hosts, id: \.self) { host in
                                Button(action: {
                                    store.setHost(host: host)
                                }) {
                                    Label(host.name!, systemImage: host == store.host ? "checkmark" : "")
                                }

                            }

                        } label: {
                            Label("Server", systemImage: "arrow.triangle.2.circlepath")
                        }

                        Divider()

                        Button(action: {store.setup.toggle()}) {
                            Label("Add", systemImage: "plus")
                        }
                        Button(action: {store.editServers.toggle()}) {
                            Label("Edit", systemImage: "square.and.pencil")
                        }
                    } label: {
                        Image(systemName: "server.rack")
                    }
                }
                ToolbarItemGroup (placement: .automatic) {
                    Menu {
                        Menu {
                            Section(header: Text("Include")) {
                                Button("All") {
                                    filterBySelection = TorrentStatusCalc.allCases
                                }
                                Button("Downloading") {
                                    filterBySelection = [.downloading]
                                }
                                Button("Complete") {
                                    filterBySelection = [.complete]
                                }
                                Button("Paused") {
                                    filterBySelection = [.paused]
                                }
                            }
                            Section(header: Text("Exclude")) {
                                Button("Complete") {
                                    filterBySelection = TorrentStatusCalc.allCases.filter {$0 != .complete}
                                }
                            }
                        } label: {
                            Text("Filter By")
                            Image(systemName: "slider.horizontal.3")
                        }.environment(\.menuOrder, .fixed)
                        
                        Menu {
                            Picker("Sort By", selection: $sortBySelection) {
                                ForEach(sortBy.allCases, id: \.self) { item in
                                    Text(item.rawValue)
                                }
                                .pickerStyle(.automatic)
                            }
                        } label: {
                            Text("Sort By")
                            Image(systemName: "arrow.up.arrow.down")
                        }.environment(\.menuOrder, .fixed)
                        
                        Divider()
                        
                        Button(action: {
                            playPauseAllTorrents(start: false, info: makeConfig(store: store), onResponse: { response in
                                updateList(store: store, update: {_ in})
                            })
                        }) {
                            Label("Pause All", systemImage: "pause")
                        }
                        
                        Button(action: {
                            playPauseAllTorrents(start: true, info: makeConfig(store: store), onResponse: { response in
                                updateList(store: store, update: {_ in})
                            })
                        }) {
                            Label("Resume All", systemImage: "play")
                        }
                        
                        Divider()
                        
                        Button(action: {
                            store.isShowingAddAlert.toggle()
                        }) {
                            Label("Add Torrent", systemImage: "plus")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            // Add/edit server sheet
            .sheet(isPresented: $store.setup, content: {
                ServerDetail(store: store, viewContext: viewContext, hosts: hosts, isAddNew: true)
                //                .onExitCommand(perform: {
                //                    store.setup.toggle()
                //                })
            })
            // Edit server sheet
            .sheet(isPresented: $store.editServers, content: {
                ServerList(viewContext: viewContext, store: store)
                //                .onExitCommand(perform: {
                //                    store.editServers.toggle()
                //                })
            })
            // Add torrent alert
            .sheet(isPresented: $store.isShowingAddAlert, content: {
                AddTorrent(store: store)
                //                .onExitCommand(perform: {
                //                    store.isShowingAddAlert.toggle()
                //                })
            })
            // Add transfer file picker
            .sheet(isPresented: $store.isShowingTransferFiles, content: {
                FileSelectDialog(store: store)
                    .frame(width: 400, height: 500)
                //                .onExitCommand(perform: {
                //                    store.isShowingTransferFiles.toggle()
                //                })
            })
            // Show an error message if we encounter an error
            .sheet(isPresented: $store.isError, content: {
                ErrorDialog(store: store)
                    .frame(width: 400, height: 400)
                //                .onExitCommand(perform: {
                //                    store.isError.toggle()
                //                })
            })
            
        } detail: {
            if let torrentSelection = torrentSelection {
                TorrentDetail(store: store, viewContext: viewContext, torrent: binding(for: torrentSelection))
            }
            else {
                Text("No Selection")
            }
        }
    }

    func binding(for torrent: Torrent) -> Binding<Torrent> {
        guard let scrumIndex = store.torrents.firstIndex(where: { $0.id == torrent.id }) else {
            fatalError("Can't find in array")
        }
        return $store.torrents[scrumIndex]
    }
}
