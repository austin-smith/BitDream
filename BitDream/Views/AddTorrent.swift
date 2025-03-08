//
//  AddTorrent.swift
//  BitDream
//
//  Created by Austin Smith on 12/29/22.
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct AddTorrent: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: Store
    
    @State var alertInput: String = ""
    @State var downloadDir: String = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Magnet Link")) {
                    TextField(
                        "magnet link",
                        text: $alertInput
                    ).onSubmit {
                        // TODO: Validate entry
                    }
                }
                Section(header: Text("Download Destination")) {
                    VStack(alignment: .leading, spacing: 0) {
                        TextField(
                            "Download Destination",
                            text: $downloadDir
                        )
                    }
                }
                
//                HStack {
//                    Button("Upload file") {
//                        // Show file chooser panel
//                        let panel = NSOpenPanel()
//                        panel.allowsMultipleSelection = false
//                        panel.canChooseDirectories = false
//                        panel.allowedContentTypes = [.torrent]
//
//                        if panel.runModal() == .OK {
//                            // Convert the file to a base64 string
//                            let fileData = try! Data.init(contentsOf: panel.url!)
//                            let fileStream: String = fileData.base64EncodedString(options: NSData.Base64EncodingOptions.init(rawValue: 0))
//
//                            let info = makeConfig(store: store)
//
//                            addTorrent(fileUrl: fileStream, saveLocation: downloadDir, auth: info.auth, file: true, config: info.config, onAdd: { response in
//                                if response.response == TransmissionResponse.success {
//                                    store.isShowingAddAlert.toggle()
//                                    showFilePicker(transferId: response.transferId, info: info)
//                                }
//                            })
//                        }
//                    }
//                    .padding()
//                }
            }
            #if os(iOS)
            .navigationBarTitle(Text("Add Torrent"), displayMode: .inline)
            #endif
            .interactiveDismissDisabled(false)
            .onAppear {
                downloadDir = store.defaultDownloadDir
            }
            #if os(iOS)
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
                        // Send the magnet link to the server
                        let info = makeConfig(store: store)
                        addTorrent(fileUrl: alertInput, saveLocation: downloadDir, auth: info.auth, file: false, config: info.config, onAdd: { response in
                            if response.response == TransmissionResponse.success {
                                store.isShowingAddAlert.toggle()
                                showFilePicker(transferId: response.transferId, info: info)
                            }
                        })
                    }
                }
            }
            #endif
        }
    }
    
    func showFilePicker(transferId: Int, info: (config: TransmissionConfig, auth: TransmissionAuth)) {
        getTorrentFiles(transferId: transferId, info: info, onReceived: { f in
            store.addTransferFilesList = f
            store.transferToSetFiles = transferId
            store.isShowingTransferFiles.toggle()
        })
    }
}

// This is needed to silence buildtime warnings related to the filepicker.
// `.allowedFileTypes` was deprecated in favor of this attrocity. No comment <3
extension UTType {
    static var torrent: UTType {
        UTType.types(tag: "torrent", tagClass: .filenameExtension, conformingTo: nil).first!
    }
}
