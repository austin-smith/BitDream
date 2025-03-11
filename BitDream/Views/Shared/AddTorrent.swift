//
//  AddTorrent.swift
//  BitDream
//
//  Created by Austin Smith on 12/29/22.
//

import Foundation
import SwiftUI
import KeychainAccess
import UniformTypeIdentifiers
import CoreData

/// Platform-agnostic wrapper for AddTorrent view
/// This view simply delegates to the appropriate platform-specific implementation
struct AddTorrent: View {
    @ObservedObject var store: Store
    
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
func handleAddTorrentError(_ message: String, errorMessage: Binding<String?>, showingError: Binding<Bool>) {
    // Ensure UI updates happen on the main thread
    DispatchQueue.main.async {
        errorMessage.wrappedValue = message
        showingError.wrappedValue = true
        print(message)
    }
}

/// Function to add a torrent to the server
func addTorrentAction(
    alertInput: String,
    downloadDir: String,
    store: Store,
    errorMessage: Binding<String?>,
    showingError: Binding<Bool>
) {
    // Only proceed if we have a magnet link
    guard !alertInput.isEmpty else { return }
    
    // Send the magnet link to the server
    let info = makeConfig(store: store)
    addTorrent(
        fileUrl: alertInput,
        saveLocation: downloadDir,
        auth: info.auth,
        file: false,
        config: info.config,
        onAdd: { response in
            // Ensure UI updates happen on the main thread
            DispatchQueue.main.async {
                if response.response == TransmissionResponse.success {
                    store.isShowingAddAlert.toggle()
                    // Just close the add torrent dialog
                } else {
                    handleAddTorrentError("Failed to add torrent: \(response.response)", errorMessage: errorMessage, showingError: showingError)
                }
            }
        }
    )
}

// MARK: - Extensions
extension UTType {
    /// This is needed to silence buildtime warnings related to the filepicker.
    /// `.allowedFileTypes` was deprecated in favor of this approach.
    static var torrent: UTType {
        UTType.types(tag: "torrent", tagClass: .filenameExtension, conformingTo: nil).first!
    }
}
