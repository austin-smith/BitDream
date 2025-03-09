import Foundation
import SwiftUI
import KeychainAccess
import CoreData

#if os(iOS)
struct iOSTorrentDetail: View {
    @Environment(\.dismiss) private var dismiss
    
    @ObservedObject var store: Store
    var viewContext: NSManagedObjectContext
    @Binding var torrent: Torrent
    
    @State public var files: [TorrentFile] = []
    
    var body: some View {
        // Use shared formatting function
        let details = formatTorrentDetails(torrent: torrent)
        
        NavigationStack {
            VStack {
                // Use shared header view
                TorrentDetailHeaderView(torrent: torrent)
                
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
                                .foregroundColor(statusColor(for: torrent))
                                .font(.system(size: 12))
                            Text(torrent.statusCalc.rawValue)
                                .foregroundColor(.gray)
                        }
                        HStack {
                            Text("Date Added")
                            Spacer()
                            Text(details.addedDate)
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
                            Text(details.downloadedFormatted)
                                .foregroundColor(.gray)
                        }
                        HStack {
                            Text("Size When Done")
                            Spacer()
                            Text(details.sizeWhenDoneFormatted)
                                .foregroundColor(.gray)
                        }
                        HStack {
                            Text("Progress")
                            Spacer()
                            Text(details.percentComplete)
                                .foregroundColor(.gray)
                        }
                    }
                    
                    Section {
                        HStack {
                            Text("Availability")
                            Spacer()
                            Text(details.percentAvailable)
                                .foregroundColor(.gray)
                        }
                        HStack {
                            Text("Last Activity")
                            Spacer()
                            Text(details.activityDate)
                                .foregroundColor(.gray)
                        }
                    }
                    
                    Button(role: .destructive, action: {
                        //viewContext.delete(torrent.self)
                        //try? viewContext.save()
                        //dismiss()
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
            }
            .onAppear{
                // Use shared function to fetch files
                fetchTorrentFiles(transferId: torrent.id, store: store) { fetchedFiles in
                    self.files = fetchedFiles
                }
            }
            .toolbar {
                // Use shared toolbar
                TorrentDetailToolbar(torrent: torrent, store: store)
            }
        }
    }
}
#else
// Empty struct for macOS to reference - this won't be compiled on iOS but provides the type
struct iOSTorrentDetail: View {
    @ObservedObject var store: Store
    var viewContext: NSManagedObjectContext
    @Binding var torrent: Torrent
    
    init(store: Store, viewContext: NSManagedObjectContext, torrent: Binding<Torrent>) {
        self.store = store
        self.viewContext = viewContext
        self._torrent = torrent
    }
    
    var body: some View {
        EmptyView()
    }
}
#endif