import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Platform-agnostic wrapper for AddTorrent view
/// This view simply delegates to the appropriate platform-specific implementation
struct AddTorrent: View {
    @ObservedObject var store: TransmissionStore

    var body: some View {
        #if os(iOS)
        iOSAddTorrent(store: store)
        #else
        macOSAddTorrent(store: store)
        #endif
    }
}

// MARK: - Shared Helper Functions

/// Function to handle errors in the torrent adding process
@MainActor
func handleAddTorrentError(_ message: String, errorMessage: Binding<String?>, showingError: Binding<Bool>) {
    errorMessage.wrappedValue = message
    showingError.wrappedValue = true
}

let addTorrentNoServerConfiguredMessage =
    "No server configured. Please add or select a server in Settings."

@MainActor
func presentAddTorrentSheetError(
    detail: String,
    errorMessage: Binding<String?>,
    showingError: Binding<Bool>
) {
    handleAddTorrentError(
        TransmissionActionFailureContext.addTorrent.inlineMessage(detail: detail),
        errorMessage: errorMessage,
        showingError: showingError
    )
}

@MainActor
func presentAddTorrentStoreError(
    detail: String,
    store: TransmissionStore
) {
    #if os(macOS)
    store.globalAlertTitle = TransmissionActionFailureContext.addTorrent.globalAlertTitle
    store.globalAlertMessage = TransmissionActionFailureContext.addTorrent.globalAlertMessage(detail: detail)
    store.showGlobalAlert = true
    #else
    store.debugBrief = TransmissionActionFailureContext.addTorrent.debugBrief
    store.debugMessage = detail
    store.isError = true
    #endif
}

@MainActor
func addTorrentFromFileData(_ data: Data, store: TransmissionStore) {
    performTransmissionAction(
        operation: {
            try await store.addTorrent(
                fileData: data,
                saveLocation: store.defaultDownloadDir
            )
        },
        onSuccess: { (_: TransmissionTorrentAddOutcome) in },
        onError: { message in
            presentAddTorrentStoreError(detail: message, store: store)
        }
    )
}

// MARK: - Extensions
extension UTType {
    /// Convenience UTType for .torrent used by file importer; prefers extension, then MIME type, then .data
    static var torrent: UTType {
        UTType(filenameExtension: "torrent")
        ?? UTType(mimeType: "application/x-bittorrent")
        ?? .data
    }
}
