import Foundation
import SwiftUI
import UniformTypeIdentifiers

#if os(iOS)
struct iOSAddTorrent: View {
    // MARK: - Properties
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: TransmissionStore

    @State private var alertInput: String = ""
    @State private var downloadDir: String = ""
    @State private var errorMessage: String?
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
                            submitMagnetTorrent()
                        }
                        .keyboardShortcut(.defaultAction)
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
                    .submitLabel(.done)
                    .onSubmit {
                        submitMagnetTorrent()
                    }
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

    private func submitMagnetTorrent() {
        guard !alertInput.isEmpty else { return }

        performTransmissionAction(
            operation: {
                try await store.addTorrent(
                    magnetLink: alertInput,
                    saveLocation: downloadDir
                )
            },
            onSuccess: { (_: TransmissionTorrentAddOutcome) in
                dismiss()
            },
            onError: { message in
                presentAddTorrentSheetError(
                    detail: message,
                    errorMessage: $errorMessage,
                    showingError: $showingError
                )
            }
        )
    }
}
#endif
