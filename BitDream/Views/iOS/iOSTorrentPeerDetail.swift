import SwiftUI
import Foundation

#if os(iOS)
struct iOSTorrentPeerDetail: View {
    let torrentName: String
    let torrentId: Int
    let store: Store
    let peers: [Peer]
    let peersFrom: PeersFrom?
    let onRefresh: () -> Void
    let onDone: () -> Void

    @State private var searchText: String = ""

    private var filteredPeers: [Peer] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return peers }
        return peers.filter { peer in
            peer.address.localizedCaseInsensitiveContains(trimmed)
            || peer.clientName.localizedCaseInsensitiveContains(trimmed)
            || peer.flagStr.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        NavigationStack {
            if filteredPeers.isEmpty {
                VStack(spacing: 12) {
                    Text(peers.isEmpty ? "No peers yet" : "No results")
                        .foregroundColor(.secondary)
                    Button(action: onRefresh) { Label("Refresh", systemImage: "arrow.clockwise") }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle("Peers")
                .navigationBarTitleDisplayMode(.inline)
                .searchable(text: $searchText, prompt: "Search peers")
                .toolbar {
                    ToolbarItemGroup(placement: .navigationBarTrailing) {
                        Button(action: onRefresh) {
                            Image(systemName: "arrow.clockwise")
                        }
                        Button("Done", action: onDone)
                    }
                }
            } else {
                List {
                    ForEach(filteredPeers, id: \.id) { peer in
                        PeerRowCard(peer: peer)
                    }

                    // Peer count footer as a List section
                    Section {
                        EmptyView()
                    } footer: {
                        HStack {
                            if filteredPeers.count < peers.count {
                                Text("Showing \(filteredPeers.count) of \(peers.count) peers")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                Text("\(peers.count) peers")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .refreshable { onRefresh() }
                .navigationTitle("Peers")
                .navigationBarTitleDisplayMode(.inline)
                .searchable(text: $searchText, prompt: "Search peers")
                .toolbar {
                    ToolbarItemGroup(placement: .navigationBarTrailing) {
                        Button(action: onRefresh) {
                            Image(systemName: "arrow.clockwise")
                        }
                        Button("Done", action: onDone)
                    }
                }
            }
        }
    }
}

private struct PeerRowCard: View {
    let peer: Peer

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Primary Identity: IP + Client Name
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(peer.address):\(peer.port)")
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundColor(.primary)
                    Text(peer.clientName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                // Connection Details: Protocol + Encryption
                HStack(spacing: 6) {
                    Text(peer.isUTP ? "uTP" : "TCP")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.gray.opacity(0.1))
                        .foregroundColor(.secondary)
                        .cornerRadius(4)

                    Text(peer.isEncrypted ? "Encrypted" : "Unencrypted")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(peer.isEncrypted ? Color.green.opacity(0.1) : Color.gray.opacity(0.1))
                        .foregroundColor(peer.isEncrypted ? .green : .secondary)
                        .cornerRadius(4)
                }
            }

            // Performance Metrics: Progress + Speeds
            VStack(alignment: .leading, spacing: 4) {
                FileProgressView(percentDone: peer.progress)

                HStack {
                    SpeedChip(
                        speed: peer.rateToClient ?? 0,
                        direction: .download,
                        style: .plain,
                        size: .compact
                    )

                    SpeedChip(
                        speed: peer.rateToPeer ?? 0,
                        direction: .upload,
                        style: .plain,
                        size: .compact
                    )

                    Spacer()
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#else
struct iOSTorrentPeerDetail: View {
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
