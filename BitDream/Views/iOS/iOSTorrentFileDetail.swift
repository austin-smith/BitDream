import Foundation
import SwiftUI
import CoreData

#if os(iOS)
struct iOSTorrentFileDetail: View {
    let files: [TorrentFile]
    let fileStats: [TorrentFileStats]
    
    private var mergedFiles: [(file: TorrentFile, stats: TorrentFileStats)] {
        Array(zip(files, fileStats))
    }
    
    var body: some View {
        List {
            ForEach(mergedFiles, id: \.file.id) { pair in
                VStack {
                    HStack {
                        Text(pair.file.name)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Spacer()
                    }
                    .padding(.bottom, 1)
                    
                    HStack {
                        ProgressView(value: pair.file.percentDone)
                            .tint(pair.file.percentDone == 1.0 ? .green : .blue)
                        
                        Text("\(byteCountFormatter.string(fromByteCount: pair.file.bytesCompleted)) of \(byteCountFormatter.string(fromByteCount: pair.file.length)) (\(String(format: "%.1f%%", pair.file.percentDone * 100)))")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Priority:")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                        let priority = FilePriority(rawValue: pair.stats.priority) ?? .normal
                        Text(pair.stats.wanted ? priority.displayText : "Skip")
                            .font(.footnote)
                            .foregroundColor(pair.stats.wanted ? priority.color : .secondary)
                        Spacer()
                    }
                }
                .listRowInsets(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
                .listRowSeparator(.visible)
            }
        }
        .navigationTitle("Files")
    }
}

#else
// Empty struct for macOS to reference - this won't be compiled on macOS but provides the type
struct iOSTorrentFileDetail: View {
    let files: [TorrentFile]
    let fileStats: [TorrentFileStats]
    
    var body: some View {
        EmptyView()
    }
}
#endif 