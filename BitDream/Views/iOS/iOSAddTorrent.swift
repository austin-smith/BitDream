//
//  iOSAddTorrent.swift
//  BitDream
//
//  Created by Austin Smith on 3/10/24.
//

import Foundation
import SwiftUI
import KeychainAccess
import UniformTypeIdentifiers
import CoreData

#if os(iOS)
struct iOSAddTorrent: View {
    // MARK: - Properties
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: Store
    
    @State private var alertInput: String = ""
    @State private var downloadDir: String = ""
    @State private var errorMessage: String? = nil
    @State private var showingError = false
    
    // MARK: - Body
    var body: some View {
        NavigationView {
            addTorrentForm
                .navigationBarTitle(Text("Add Torrent"), displayMode: .inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(action: {
                            dismiss()
                        }, label: {
                            Text("Cancel")
                        })
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Add") {
                            addTorrentAction(
                                alertInput: alertInput,
                                downloadDir: downloadDir,
                                store: store,
                                errorMessage: $errorMessage,
                                showingError: $showingError
                            )
                        }
                        .disabled(alertInput.isEmpty)
                    }
                }
        }
        .alert("Error", isPresented: $showingError, actions: {
            Button("OK", role: .cancel) {}
        }, message: {
            Text(errorMessage ?? "An unknown error occurred")
        })
    }
    
    // MARK: - Form View
    var addTorrentForm: some View {
        Form {
            // Torrent Source Section
            Section(header: Text("Torrent Source")) {
                TextField("Magnet link or URL", text: $alertInput)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
            }
            
            // Download Location Section
            Section(header: Text("Download Location")) {
                TextField("Download path", text: $downloadDir)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
            }
        }
        .onAppear {
            downloadDir = store.defaultDownloadDir
        }
    }
    
    // MARK: - Actions
    // Using shared implementations from AddTorrent.swift
}
#else
// Empty struct for macOS to reference - this won't be compiled on macOS but provides the type
struct iOSAddTorrent: View {
    @ObservedObject var store: Store
    
    init(store: Store) {
        self.store = store
    }
    
    var body: some View {
        EmptyView()
    }
}
#endif 