import SwiftUI
import Foundation

#if os(macOS)
struct macOSTorrentPeerDetail: View {
    let torrentName: String
    let torrentId: Int
    let store: Store
    let peers: [Peer]
    let peersFrom: PeersFrom?
    let onRefresh: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Peers")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("\(torrentName) • \(peers.count) peers")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    HStack(spacing: 8) {
                        Button(action: onRefresh) {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        Button("Done", action: onDone)
                    }
                }
                if let from = peersFrom {
                    Text(peersFromSummary(from))
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Divider()

            if peers.isEmpty {
                VStack(spacing: 12) {
                    Text("No peers yet")
                        .foregroundColor(.secondary)
                    Button(action: onRefresh) { Label("Refresh", systemImage: "arrow.clockwise") }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(peers) {
                    TableColumn("IP") { peer in
                        Text("\(peer.address):\(peer.port)")
                            .font(.system(.caption, design: .monospaced))
                    }
                    TableColumn("Client") { peer in
                        Text(peer.clientName)
                    }
                    TableColumn("Progress") { peer in
                        FileProgressView(percentDone: peer.progress)
                    }
                    TableColumn("Download") { peer in
                        Text(formatSpeed(peer.rateToClient ?? 0))
                            .font(.system(.caption, design: .monospaced))
                    }
                    TableColumn("Upload") { peer in
                        Text(formatSpeed(peer.rateToPeer ?? 0))
                            .font(.system(.caption, design: .monospaced))
                    }
                    // Place Flags at far right with stable tooltip (no backend terms)
                    TableColumn("Encrypted") { peer in
                        BoolCheckIcon(value: peer.isEncrypted, label: "Encrypted")
                    }
                    TableColumn("Protocol") { peer in
                        ProtocolBadge(text: peer.isUTP ? "uTP" : "TCP")
                    }
                    TableColumn("Flags") { peer in
                        Text(peer.flagStr)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .help(peerFlagsHelp(peer))
                    }
                    // Removed Incoming and State columns per request
                }
            }
        }
    }
}

#else
struct macOSTorrentPeerDetail: View {
    let torrentName: String
    let torrentId: Int
    let store: Store
    let peers: [Peer]
    let peersFrom: PeersFrom?
    let onRefresh: () -> Void
    let onDone: () -> Void
    var body: some View { EmptyView() }
}
#endif
