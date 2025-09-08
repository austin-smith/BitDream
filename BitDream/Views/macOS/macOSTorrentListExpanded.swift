import Foundation
import SwiftUI
import KeychainAccess

#if os(macOS)
struct macOSTorrentListExpanded: View {
    @Binding var torrent: Torrent
    var store: Store
    @Binding var selectedTorrents: Set<Torrent>
    
    @State var deleteDialog: Bool = false
    @State var labelDialog: Bool = false
    @State var labelInput: String = ""
    @State private var shouldSave: Bool = false
    @State private var renameDialog: Bool = false
    @State private var renameInput: String = ""
    @State private var renameTargetId: Int? = nil
    @State private var showingError = false
    @State private var errorMessage = ""
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack {
            HStack(spacing: 8) {
                // Torrent type icon
                Image(systemName: ContentTypeIconMapper.symbolForTorrent(mimeType: torrent.primaryMimeType))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary.opacity(0.6))
                    .frame(width: 14)
                
                Text(torrent.name)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(alignment: .leading)
                
                // Display labels inline if present, but allow them to be truncated
                createLabelTagsView(for: torrent)
                    .layoutPriority(-1)  // Give lower priority than the name
            }
            
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
        .modifier(TorrentRowModifier(
            torrent: $torrent,
            selectedTorrents: $selectedTorrents,
            store: store,
            deleteDialog: $deleteDialog,
            labelDialog: $labelDialog,
            labelInput: $labelInput,
            shouldSave: $shouldSave,
            showingError: $showingError,
            errorMessage: $errorMessage,
            renameDialog: $renameDialog,
            renameInput: $renameInput,
            renameTargetId: $renameTargetId
        ))
    }
}

#else
// Empty struct for iOS to reference
struct macOSTorrentListExpanded: View {
    @Binding var torrent: Torrent
    var store: Store
    @Binding var selectedTorrents: Set<Torrent>
    
    var body: some View {
        EmptyView()
    }
}
#endif
