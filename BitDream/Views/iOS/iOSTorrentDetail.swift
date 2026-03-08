import Foundation
import SwiftUI

#if os(iOS)
struct iOSTorrentDetail: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var store: TransmissionStore
    var torrent: Torrent

    @State public var files: [TorrentFile] = []
    @State public var fileStats: [TorrentFileStats] = []
    @State private var isShowingFilesSheet = false
    @State private var peers: [Peer] = []
    @State private var peersFrom: PeersFrom?
    @State private var isShowingPeersSheet = false
    @State private var pieceCount: Int = 0
    @State private var pieceSize: Int64 = 0
    @State private var piecesBitfield: String = ""
    @State private var piecesHaveCount: Int = 0
    @State private var showingDeleteConfirmation = false
    @State private var showingDeleteError = false
    @State private var deleteErrorMessage = ""

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
                            TorrentStatusBadge(torrent: torrent)
                        }
                        HStack {
                            Text("Date Added")
                            Spacer()
                            Text(details.addedDate)
                                .foregroundColor(.gray)
                        }

                        NavigationLink {
                            iOSTorrentFileDetail(files: files, fileStats: fileStats, torrentId: torrent.id, store: store)
                                .navigationBarTitleDisplayMode(.inline)
                        } label: {
                            LabeledContent("Files", value: NumberFormatter.localizedString(from: NSNumber(value: files.count), number: .decimal))
                        }

                        NavigationLink {
                            iOSTorrentPeerDetail(
                                torrentName: torrent.name,
                                torrentId: torrent.id,
                                store: store,
                                peers: peers,
                                peersFrom: peersFrom,
                                onRefresh: { await loadSupplementalData(for: torrent.id) },
                                onDone: { /* no-op in push */ }
                            )
                            .navigationBarTitleDisplayMode(.inline)
                        } label: {
                            LabeledContent("Peers", value: "\(peers.count)")
                        }
                    }

                    Section(header: Text("Stats")) {
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
                        HStack {
                            Text("Downloaded")
                            Spacer()
                            Text(details.downloadedFormatted)
                                .foregroundColor(.gray)
                        }
                        HStack {
                            Text("Uploaded")
                            Spacer()
                            Text(details.uploadedFormatted)
                                .foregroundColor(.gray)
                        }
                        HStack {
                            Text("Upload Ratio")
                            Spacer()
                            Text(details.uploadRatio)
                                .foregroundColor(.gray)
                        }
                    }

                    // Pieces section
                    if pieceCount > 0 && !piecesBitfield.isEmpty {
                        Section(header: Text("Pieces")) {
                            VStack(alignment: .leading, spacing: 6) {
                                PiecesGridView(pieceCount: pieceCount, piecesBitfieldBase64: piecesBitfield)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text("\(piecesHaveCount) of \(pieceCount) pieces • \(formatByteCount(pieceSize)) each")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        }
                    }

                    Section(header: Text("Additional Info")) {
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

                    // Beautiful Dedicated Labels Section (Display Only)
                    if !torrent.labels.isEmpty {
                        Section(header: Text("Labels")) {
                            FlowLayout(spacing: 6) {
                                ForEach(torrent.labels.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }, id: \.self) { label in
                                    DetailViewLabelTag(label: label, isLarge: false)
                                }
                            }
                            .padding(.vertical, 8)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        }
                    }

                    Button(role: .destructive, action: {
                        showingDeleteConfirmation = true
                    }, label: {
                        HStack {
                            HStack {
                                Image(systemName: "trash")
                                Text("Delete…")
                                Spacer()
                            }
                        }
                    })
                }
            }
            .task(id: torrent.id) {
                await loadSupplementalData(for: torrent.id)
            }
            .toolbar {
                // Use shared toolbar
                TorrentDetailToolbar(torrent: torrent, store: store)
            }
            .alert("Delete Torrent", isPresented: $showingDeleteConfirmation) {
                Button(role: .destructive) {
                    performDelete(deleteLocalData: true)
                } label: {
                    Text("Delete file(s)")
                }
                Button("Remove from list only") {
                    performDelete(deleteLocalData: false)
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Do you want to delete the file(s) from the disk?")
            }
            .transmissionErrorAlert(isPresented: $showingDeleteError, message: deleteErrorMessage)
        }

    }

    private func performDelete(deleteLocalData: Bool) {
        performTransmissionAction(
            operation: {
                try await store.removeTorrents(
                    ids: [torrent.id],
                    deleteLocalData: deleteLocalData
                )
            },
            onSuccess: {
                dismiss()
            },
            onError: makeTransmissionBindingErrorHandler(
                isPresented: $showingDeleteError,
                message: $deleteErrorMessage
            )
        )
    }

    @MainActor
    private func loadSupplementalData(for torrentID: Int) async {
        guard let snapshot = await performStructuredTransmissionOperation(
            operation: { try await store.loadTorrentDetail(id: torrentID) },
            onError: { message in
                deleteErrorMessage = message
                showingDeleteError = true
            }
        ) else {
            return
        }

        apply(snapshot: snapshot)
    }

    private func apply(snapshot: TransmissionTorrentDetailSnapshot) {
        files = snapshot.files
        fileStats = snapshot.fileStats
        peers = snapshot.peers
        peersFrom = snapshot.peersFrom
        pieceCount = snapshot.pieceCount
        pieceSize = snapshot.pieceSize
        piecesBitfield = snapshot.piecesBitfieldBase64

        let haveSet = decodePiecesBitfield(
            base64String: snapshot.piecesBitfieldBase64,
            pieceCount: snapshot.pieceCount
        )
        piecesHaveCount = haveSet.reduce(0) { $0 + ($1 ? 1 : 0) }
    }
}

// Enhanced LabelTag component for detail views
struct DetailViewLabelTag: View {
    let label: String
    var isLarge: Bool = false

    var body: some View {
        Text(label)
            .font(isLarge ? .subheadline : .caption)
            .fontWeight(.medium)
            .padding(.horizontal, isLarge ? 8 : 6)
            .padding(.vertical, isLarge ? 4 : 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.accentColor.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
            )
            .foregroundColor(.primary)
    }
}
#endif
