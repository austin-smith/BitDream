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
    @State private var isAdding = false
    @FocusState private var isSourceFocused: Bool

    private var trimmedInput: String {
        alertInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isAddDisabled: Bool {
        trimmedInput.isEmpty || isAdding
    }

    // MARK: - Body
    var body: some View {
        NavigationStack {
            addTorrentForm
                .navigationTitle("Add Torrent")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", action: dismiss.callAsFunction)
                            .disabled(isAdding)
                    }

                    ToolbarItem(placement: .confirmationAction) {
                        Button(action: submitMagnetTorrent) {
                            if isAdding {
                                ProgressView()
                                    .accessibilityLabel("Adding torrent")
                            } else {
                                Text("Add")
                            }
                        }
                        .keyboardShortcut(.defaultAction)
                        .disabled(isAddDisabled)
                    }
                }
        }
        .interactiveDismissDisabled(isAdding)
        .alert("Error", isPresented: $showingError, actions: {
            Button("OK", role: .cancel) {}
        }, message: {
            Text(errorMessage ?? "An unknown error occurred")
        })
    }

    // MARK: - Form View
    var addTorrentForm: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "link")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)

                    TextField("magnet:?xt=urn:btih:…", text: $alertInput)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($isSourceFocused)
                        .submitLabel(.go)
                        .onSubmit(submitMagnetTorrent)
                }
            } header: {
                Text("Magnet Link")
            }

            Section {
                HStack(spacing: 12) {
                    Image(systemName: "folder")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)

                    TextField("Download path", text: $downloadDir)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            } header: {
                Text("Download To")
            }
        }
        .formStyle(.grouped)
        .scrollDismissesKeyboard(.interactively)
        .disabled(isAdding)
        .onAppear {
            downloadDir = store.defaultDownloadDir
        }
        .task {
            isSourceFocused = true
        }
    }

    // MARK: - Actions

    private func submitMagnetTorrent() {
        guard !isAddDisabled else { return }

        isAdding = true
        alertInput = trimmedInput

        performTransmissionAction(
            operation: {
                try await store.addTorrent(
                    magnetLink: alertInput,
                    saveLocation: downloadDir
                )
            },
            onSuccess: { (_: TransmissionTorrentAddOutcome) in
                isAdding = false
                dismiss()
            },
            onError: { message in
                isAdding = false
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

#if os(iOS) && DEBUG
#Preview("iOS Add Torrent") {
    PreviewContainer { environment in
        iOSAddTorrent(store: environment.store)
    }
}
#endif
