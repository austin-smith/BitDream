import SwiftUI

#if os(macOS)
struct macOSServerDetail: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.hostRepositoryProvider) private var hostRepositoryProvider

    @ObservedObject var store: TransmissionStore
    let hosts: [Host]
    let host: Host?

    @State private var showingDeleteConfirmation = false
    @State private var hasUnsavedChanges = false
    @State private var isSaving = false

    var body: some View {
        macOSServerEditor(
            store: store,
            hosts: hosts,
            host: host,
            title: host == nil ? "Add Server" : "Edit Server",
            saveButtonTitle: "Save",
            cancelButtonTitle: "Cancel",
            onCancel: { dismiss() },
            onSaved: { _ in dismiss() },
            onDelete: host == nil ? nil : { showingDeleteConfirmation = true },
            hasUnsavedChanges: $hasUnsavedChanges,
            isSaving: $isSaving,
            onError: presentError
        )
        .frame(width: 460, height: 560)
        .interactiveDismissDisabled(isSaving)
        .alert("Delete Server", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                if let host {
                    Task {
                        do {
                            try await deleteServer(
                                host: host,
                                store: store,
                                hosts: hosts,
                                hostRepository: hostRepositoryProvider.resolve()
                            )
                            dismiss()
                        } catch {
                            presentError(userFacingHostPersistenceMessage(error))
                        }
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete this server? This action cannot be undone.")
        }
    }

    private func presentError(_ message: String) {
        store.globalAlertTitle = "Error"
        store.globalAlertMessage = message
        store.showGlobalAlert = true
    }
}
#endif

#if os(macOS) && DEBUG
#Preview("macOS Server Detail") {
    PreviewContainer { environment in
        macOSServerDetail(
            store: environment.store,
            hosts: environment.hosts,
            host: environment.hosts[0]
        )
    }
}
#endif
