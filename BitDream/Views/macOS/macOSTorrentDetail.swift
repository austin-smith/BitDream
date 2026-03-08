import Foundation
import SwiftUI

#if os(macOS)
struct macOSTorrentDetail: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var store: TransmissionStore
    var torrent: Torrent

    @State public var files: [TorrentFile] = []
    @State private var fileStats: [TorrentFileStats] = []
    @State private var isShowingFilesSheet = false
    @State private var peers: [Peer] = []
    @State private var peersFrom: PeersFrom?
    @State private var isShowingPeersSheet = false
    @State private var showingDeleteConfirmation = false
    @State private var showingDeleteError = false
    @State private var deleteErrorMessage = ""
    @State private var pieceCount: Int = 0
    @State private var pieceSize: Int64 = 0
    @State private var piecesBitfield: String = ""
    @State private var piecesHaveCount: Int = 0

    var body: some View {
        // Use shared formatting function
        let details = formatTorrentDetails(torrent: torrent)

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TorrentDetailHeaderView(torrent: torrent)
                    .padding(.bottom, 4)

                // General section
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        // Native macOS section header
                        macOSSectionHeader("General", icon: "info.circle")

                        DetailRow(label: "Name", value: torrent.name)

                        DetailRow(label: "Status") {
                            TorrentStatusBadge(torrent: torrent)
                        }

                        DetailRow(label: "Date Added", value: details.addedDate)

                        DetailRow(label: "Files") {
                            Button {
                                isShowingFilesSheet = true
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "document")
                                        .font(.system(size: 12))
                                        .foregroundColor(.accentColor)
                                    Text("\(files.count)")
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .buttonStyle(.bordered)
                            .help("View files in this torrent")
                        }

                        DetailRow(label: "Peers") {
                            Button {
                                isShowingPeersSheet = true
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "person.2")
                                        .font(.system(size: 12))
                                        .foregroundColor(.accentColor)
                                    Text("\(peers.count)")
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .buttonStyle(.bordered)
                            .help("View peers for this torrent")
                        }
                    }
                    .padding(.vertical, 16)
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 8)

                // Stats section
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        // Native macOS section header
                        macOSSectionHeader("Stats", icon: "chart.bar")

                        DetailRow(label: "Size When Done", value: details.sizeWhenDoneFormatted)
                        DetailRow(label: "Progress", value: details.percentComplete)
                        DetailRow(label: "Downloaded", value: details.downloadedFormatted)
                        DetailRow(label: "Uploaded", value: details.uploadedFormatted)
                        DetailRow(label: "Upload Ratio", value: details.uploadRatio)
                    }
                    .padding(.vertical, 16)
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 8)

                // Pieces section
                if pieceCount > 0 && !piecesBitfield.isEmpty {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            macOSSectionHeader("Pieces", icon: "square.grid.2x2")

                            VStack(alignment: .leading, spacing: 8) {
                                PiecesGridView(pieceCount: pieceCount, piecesBitfieldBase64: piecesBitfield)
                                    .frame(maxWidth: .infinity)
                                Text("\(piecesHaveCount) of \(pieceCount) pieces • \(formatByteCount(pieceSize)) each")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 16)
                        .padding(.horizontal, 20)
                    }
                    .padding(.bottom, 8)
                }

                // Additional Info section
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        // Native macOS section header
                        macOSSectionHeader("Additional Info", icon: "doc.text")

                        DetailRow(label: "Availability", value: details.percentAvailable)
                        DetailRow(label: "Last Activity", value: details.activityDate)
                    }
                    .padding(.vertical, 16)
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 8)

                // Beautiful Dedicated Labels Section (Display Only)
                if !torrent.labels.isEmpty {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 16) {
                            // Native macOS section header
                            macOSSectionHeader("Labels", icon: "tag")

                            // Labels display
                            FlowLayout(spacing: 6) {
                                ForEach(torrent.labels.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }, id: \.self) { label in
                                    DetailViewLabelTag(label: label, isLarge: false)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 16)
                        .padding(.horizontal, 20)
                    }
                    .padding(.bottom, 8)
                }

                // Actions
                HStack {
                    Spacer()
                    Button(role: .destructive, action: {
                        showingDeleteConfirmation = true
                    }, label: {
                        Label("Delete…", systemImage: "trash")
                    })
                }
                .padding(.top, 8)
            }
            .padding(20)
        }
        .sheet(isPresented: $isShowingFilesSheet) {
            let totalSizeFormatted = formatByteCount(files.reduce(0) { $0 + $1.length })

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
            .frame(minWidth: 1000, minHeight: 800)
        }
        .sheet(isPresented: $isShowingPeersSheet) {
            macOSTorrentPeerDetail(
                torrentName: torrent.name,
                torrentId: torrent.id,
                store: store,
                peers: peers,
                peersFrom: peersFrom,
                onRefresh: { await loadSupplementalData(for: torrent.id) },
                onDone: { isShowingPeersSheet = false }
            )
            .frame(minWidth: 1000, minHeight: 700)
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

// Native macOS-style section header component
struct macOSSectionHeader: View {
    let title: String
    let icon: String

    init(_ title: String, icon: String) {
        self.title = title
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)

            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)

            Spacer()
        }
        .padding(.bottom, 8)
    }
}
#endif
