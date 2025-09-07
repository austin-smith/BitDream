import Foundation
import CoreData
import KeychainAccess
import SwiftUI

#if os(macOS)
struct macOSTorrentDetail: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    @ObservedObject var store: Store
    var viewContext: NSManagedObjectContext
    @Binding var torrent: Torrent
    
    @State public var files: [TorrentFile] = []
    @State private var fileStats: [TorrentFileStats] = []
    @State private var isShowingFilesSheet = false
    
    var body: some View {
        // Use shared formatting function
        let details = formatTorrentDetails(torrent: torrent)
        
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header with transfer rates
                HStack(spacing: 12) {
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.down")
                        Text("\(byteCountFormatter.string(fromByteCount: torrent.rateDownload))/s")
                    }
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.up")
                        Text("\(byteCountFormatter.string(fromByteCount: torrent.rateUpload))/s")
                    }
                    Spacer()
                }
                .font(.system(size: 13))
                .padding(.bottom, 4)
                
                // General section
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        // Section header with proper spacing
                        Label("General", systemImage: "info.circle")
                            .font(.headline)
                            .padding(.bottom, 10)
                        
                        DetailRow(label: "Name", value: torrent.name)
                        
                        DetailRow(label: "Status") {
                            HStack {
                                Circle()
                                    .fill(statusColor(for: torrent))
                                    .frame(width: 8, height: 8)
                                Text(torrent.statusCalc.rawValue)
                            }
                        }
                        
                        DetailRow(label: "Date Added", value: details.addedDate)
                        
                        DetailRow(label: "Files") {
                            Button {
                                isShowingFilesSheet = true
                            } label: {
                                HStack(spacing: 4) {
                                    Text("\(files.count)")
                                        .foregroundColor(.accentColor)
                                    
                                    Image(systemName: "text.magnifyingglass")
                                        .font(.system(size: 11))
                                        .foregroundColor(.accentColor)
                                }
                                .padding(.vertical, 2)
                                .padding(.horizontal, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1)
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                            .help("View files")
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                }
                .padding(.bottom, 4)
                
                // Stats section
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        // Section header with proper spacing
                        Label("Stats", systemImage: "chart.bar")
                            .font(.headline)
                            .padding(.bottom, 10)
                        
                        DetailRow(label: "Downloaded", value: details.downloadedFormatted)
                        DetailRow(label: "Size When Done", value: details.sizeWhenDoneFormatted)
                        DetailRow(label: "Progress", value: details.percentComplete)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                }
                .padding(.bottom, 4)
                
                // Additional Info section
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        // Section header with proper spacing
                        Label("Additional Info", systemImage: "doc.text")
                            .font(.headline)
                            .padding(.bottom, 10)
                        
                        DetailRow(label: "Availability", value: details.percentAvailable)
                        DetailRow(label: "Last Activity", value: details.activityDate)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                }
                .padding(.bottom, 4)
                
                // Actions
                HStack {
                    Spacer()
                    Button(role: .destructive, action: {
                        //viewContext.delete(torrent.self)
                        //try? viewContext.save()
                        //dismiss()
                    }) {
                        Label("Delete Dream", systemImage: "trash")
                    }
                    .buttonStyle(.borderless)
                    .padding(.vertical, 4)
                }
                .padding(.top, 4)
            }
            .padding(20)
        }
        .sheet(isPresented: $isShowingFilesSheet) {
            let totalSizeFormatted = byteCountFormatter.string(fromByteCount: files.reduce(0) { $0 + $1.length })
            
            VStack(spacing: 0) {
                // Header with proper hierarchy
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Files")
                                .font(.title2)
                                .fontWeight(.semibold)
                            
                            Text("\(torrent.name) • \(files.count) files • \(totalSizeFormatted)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        
                        Spacer()
                        
                        Button("Done") {
                            isShowingFilesSheet = false
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                
                Divider()
                
                macOSTorrentFileDetail(files: files, fileStats: fileStats, torrentId: torrent.id, store: store)
            }
            .frame(width: 1000, height: 700)
        }
        .onAppear{
            // Use shared function to fetch files
            fetchTorrentFiles(transferId: torrent.id, store: store) { fetchedFiles, fetchedStats in
                files = fetchedFiles
                fileStats = fetchedStats
            }
        }
        .toolbar {
            // Use shared toolbar
            TorrentDetailToolbar(torrent: torrent, store: store)
        }
    }
}

// Helper view for consistent detail rows
struct DetailRow<Content: View>: View {
    var label: String
    var content: Content
    
    init(label: String, value: String) where Content == Text {
        self.label = label
        self.content = Text(value).foregroundColor(.secondary)
    }
    
    init(label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }
    
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .frame(width: 120, alignment: .leading)
                .foregroundColor(.primary)
            
            content
            
            Spacer()
        }
        .padding(.vertical, 2)
    }
}
#else
// Empty struct for iOS to reference - this won't be compiled on iOS but provides the type
struct macOSTorrentDetail: View {
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
