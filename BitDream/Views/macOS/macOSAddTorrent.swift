//
//  macOSAddTorrent.swift
//  BitDream
//
//  Created by Austin Smith on 3/10/24.
//

import Foundation
import SwiftUI
import KeychainAccess
import UniformTypeIdentifiers
import CoreData

#if os(macOS)
struct macOSAddTorrent: View {
    // MARK: - Properties
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: Store
    
    @State private var inputMethod: TorrentInputMethod = .magnetLink
    @State private var alertInput: String = ""
    @State private var downloadDir: String = ""
    @State private var errorMessage: String? = nil
    @State private var showingError = false
    @State private var selectedTorrentFiles: [(name: String, data: Data)] = []
    
    enum TorrentInputMethod: String, CaseIterable, Identifiable {
        case magnetLink = "Magnet Link"
        case torrentFile = "Torrent File"
        
        var id: String { self.rawValue }
    }
    
    // MARK: - Body
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Add Torrent")
                    .font(.headline)
                Spacer()
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Form content
            ScrollView {
                addTorrentForm
            }
            
            Divider()
            
            // Footer with buttons
            HStack {
                Spacer()
                
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Button("Add") {
                    if inputMethod == .magnetLink {
                        addTorrentAction(
                            alertInput: alertInput,
                            downloadDir: downloadDir,
                            store: store,
                            errorMessage: $errorMessage,
                            showingError: $showingError
                        )
                    } else if inputMethod == .torrentFile && !selectedTorrentFiles.isEmpty {
                        // Add each selected torrent file
                        for torrentFile in selectedTorrentFiles {
                            addTorrentFile(fileData: torrentFile.data)
                        }
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(inputMethod == .magnetLink ? alertInput.isEmpty : selectedTorrentFiles.isEmpty)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 600, height: 400)
        .alert("Error", isPresented: $showingError, actions: {
            Button("OK", role: .cancel) {}
        }, message: {
            Text(errorMessage ?? "An unknown error occurred")
        })
    }
    
    // MARK: - Form View
    var addTorrentForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Torrent Source Section
            VStack(alignment: .leading, spacing: 8) {
                Text("Torrent Source")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                // Card-style selection buttons
                HStack(spacing: 16) {
                    // Magnet Link Card
                    Button(action: {
                        inputMethod = .magnetLink
                        selectedTorrentFiles = []
                    }) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "link")
                                    .font(.system(size: 14))
                                    .foregroundColor(inputMethod == .magnetLink ? .white : .accentColor)
                                    .frame(width: 28, height: 28)
                                    .background(
                                        Circle()
                                            .fill(inputMethod == .magnetLink ? Color.accentColor : Color.accentColor.opacity(0.1))
                                    )
                                Text("Magnet Link")
                                    .fontWeight(.medium)
                                Spacer()
                            }
                            
                            Text("Add torrent using a magnet link")
                                .font(.caption)
                                .foregroundColor(inputMethod == .magnetLink ? .secondary : .secondary.opacity(0.7))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(inputMethod == .magnetLink ? 
                                      Color.accentColor.opacity(0.2) : 
                                      Color(NSColor.controlBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(inputMethod == .magnetLink ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: 1)
                        )
                        .foregroundColor(inputMethod == .magnetLink ? .accentColor : .primary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .frame(maxWidth: .infinity)
                    
                    // Torrent File Card
                    Button(action: {
                        inputMethod = .torrentFile
                        alertInput = ""
                    }) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "doc")
                                    .font(.system(size: 14))
                                    .foregroundColor(inputMethod == .torrentFile ? .white : .accentColor)
                                    .frame(width: 28, height: 28)
                                    .background(
                                        Circle()
                                            .fill(inputMethod == .torrentFile ? Color.accentColor : Color.accentColor.opacity(0.1))
                                    )
                                Text("Torrent File")
                                    .fontWeight(.medium)
                                Spacer()
                            }
                            
                            Text("Add torrent using a .torrent file")
                                .font(.caption)
                                .foregroundColor(inputMethod == .torrentFile ? .secondary : .secondary.opacity(0.7))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(inputMethod == .torrentFile ? 
                                      Color.accentColor.opacity(0.2) : 
                                      Color(NSColor.controlBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(inputMethod == .torrentFile ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: 1)
                        )
                        .foregroundColor(inputMethod == .torrentFile ? .accentColor : .primary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity)
            }
            
            // Conditional input section - only show one at a time
            Group {
                if inputMethod == .magnetLink {
                    // Magnet link input
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Enter magnet link:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        TextField("magnet:?xt=urn:btih:...", text: $alertInput)
                            .textFieldStyle(.roundedBorder)
                            .frame(height: 30)
                    }
                    .frame(height: 80) // Fixed height for both sections
                } else {
                    // Torrent file selection
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Select torrent file:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        HStack {
                            if selectedTorrentFiles.isEmpty {
                                Text("No files selected")
                                    .foregroundColor(.secondary)
                            } else {
                                Text("\(selectedTorrentFiles.count) files selected")
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            
                            Spacer()
                            
                            Button("Choose Files...") {
                                openTorrentFilePicker()
                            }
                            .controlSize(.regular)
                        }
                        .padding(8)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(6)
                    }
                    .frame(height: 80) // Fixed height for both sections
                }
            }
            
            // Download Location Section
            VStack(alignment: .leading) {
                Text("Download Location")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                HStack(spacing: 8) {
                    TextField("Download path", text: $downloadDir)
                        .textFieldStyle(.roundedBorder)
                        .frame(height: 24)
                    
                    Button(action: {
                        openDownloadLocationPicker()
                    }) {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.borderless)
                    .help("Choose download location")
                }
            }
        }
        .padding()
        .onAppear {
            downloadDir = store.defaultDownloadDir
        }
    }
    
    // MARK: - File Pickers
    private func openTorrentFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType(tag: "torrent", tagClass: .filenameExtension, conformingTo: nil)!]
        
        if panel.runModal() == .OK {
            for url in panel.urls {
                do {
                    let fileData = try Data(contentsOf: url)
                    selectedTorrentFiles.append((name: url.lastPathComponent, data: fileData))
                } catch {
                    handleAddTorrentError("Error loading torrent file: \(error.localizedDescription)", errorMessage: $errorMessage, showingError: $showingError)
                }
            }
        }
    }
    
    private func addTorrentFile(fileData: Data) {
        let fileStream = fileData.base64EncodedString(options: NSData.Base64EncodingOptions(rawValue: 0))
        
        let info = makeConfig(store: store)
        addTorrent(
            fileUrl: fileStream,
            saveLocation: downloadDir,
            auth: info.auth,
            file: true,
            config: info.config,
            onAdd: { response in
                // Ensure UI updates happen on the main thread
                DispatchQueue.main.async {
                    if response.response == TransmissionResponse.success {
                        store.isShowingAddAlert.toggle()
                    } else {
                        handleAddTorrentError("Failed to add torrent: \(response.response)", errorMessage: $errorMessage, showingError: $showingError)
                    }
                }
            }
        )
    }
    
    private func openDownloadLocationPicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        
        if panel.runModal() == .OK, let url = panel.url {
            downloadDir = url.path
        }
    }
}

// MARK: - Preview
#Preview("Add Torrent") {
    macOSAddTorrent(store: Store())
}

#else
// Empty struct for iOS to reference - this won't be compiled on iOS but provides the type
struct macOSAddTorrent: View {
    @ObservedObject var store: Store
    
    init(store: Store) {
        self.store = store
    }
    
    var body: some View {
        EmptyView()
    }
}
#endif 
