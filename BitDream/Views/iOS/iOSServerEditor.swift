import SwiftUI

#if os(iOS)
private enum iOSServerFormField: Hashable {
    case name
    case address
    case port
    case username
    case password
}

/// Sheet for adding a new server or editing an existing one.
struct iOSServerEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.hostRepositoryProvider) private var hostRepositoryProvider
    @ObservedObject var store: TransmissionStore
    let hosts: [Host]
    let host: Host?

    @State private var model = ServerFormModel()
    @State private var isConfirmingDiscard = false
    @State private var isConfirmingDelete = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: iOSServerFormField?

    private var isAddNew: Bool { host == nil }

    /// Transmission version reported by the server, when known.
    private var serverVersion: String? {
        guard let raw = host?.version?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }
        return "v\(raw)"
    }

    var body: some View {
        NavigationStack {
            form
                .navigationTitle(isAddNew ? "Add Server" : "Edit Server")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", role: .cancel, action: cancel)
                            .disabled(model.isSaving)
                    }

                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save", action: save)
                            .disabled(model.isSaving)
                    }
                }
                .confirmationDialog(
                    "Discard Changes?",
                    isPresented: $isConfirmingDiscard
                ) {
                    Button("Discard Changes", role: .destructive) {
                        dismiss()
                    }
                    Button("Keep Editing", role: .cancel) {}
                } message: {
                    Text("Your unsaved server changes will be lost.")
                }
                .confirmationDialog(
                    "Delete Server",
                    isPresented: $isConfirmingDelete,
                    presenting: host,
                    actions: { host in
                        Button("Delete \(host.displayName)", role: .destructive) {
                            performDelete(host)
                        }
                    },
                    message: { host in
                        deleteConfirmationMessage(for: host, store: store)
                    }
                )
                .alert("Error", isPresented: isPresentingError) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(errorMessage ?? "")
                }
        }
        .interactiveDismissDisabled(model.hasUnsavedChanges || model.isSaving)
        .onAppear {
            model.configure(host: host, store: store)
        }
    }

    private var form: some View {
        Form {
            Section {
                LabeledContent("Name") {
                    TextField("Friendly name", text: $model.values.name)
                        .multilineTextAlignment(.trailing)
                        .focused($focusedField, equals: .name)
                }

                Toggle("Default", isOn: $model.values.isDefault)
                    .disabled(!model.canEditDefaultToggle(hostCount: hosts.count))
            } footer: {
                Text("Preferred server when connecting at launch.")
            }

            Section {
                LabeledContent("Address") {
                    TextField("127.0.0.1", text: $model.values.address)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .address)
                }

                LabeledContent("Port") {
                    TextField("9091", value: $model.values.port, format: .number.grouping(.never))
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.numberPad)
                        .focused($focusedField, equals: .port)
                }

                Toggle("Use SSL", isOn: $model.values.isSSL)
            } header: {
                Text("Connection")
            } footer: {
                if let message = model.validationMessage {
                    Text(message)
                        .foregroundStyle(.red)
                }
            }

            Section("Authentication") {
                LabeledContent("Username") {
                    TextField("Optional", text: $model.values.username)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .username)
                }

                LabeledContent("Password") {
                    SecureField("Optional", text: $model.values.password)
                        .multilineTextAlignment(.trailing)
                        .focused($focusedField, equals: .password)
                }
            }

            if !isAddNew {
                Section {
                    Button("Delete Server", role: .destructive) {
                        isConfirmingDelete = true
                    }
                    .frame(maxWidth: .infinity)
                } footer: {
                    if let serverVersion {
                        Text("Transmission \(serverVersion)")
                            .frame(maxWidth: .infinity)
                            .padding(.top, 8)
                    }
                }
            }
        }
        .disabled(model.isSaving)
    }

    private var isPresentingError: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    errorMessage = nil
                }
            }
        )
    }

    private func save() {
        Task {
            do {
                switch try await model.save(
                    store: store,
                    hostRepository: hostRepositoryProvider.resolve()
                ) {
                case .validationFailed(let field):
                    focusedField = focusTarget(for: field)
                case .saved:
                    dismiss()
                }
            } catch {
                errorMessage = userFacingHostPersistenceMessage(error)
            }
        }
    }

    private func cancel() {
        if model.hasUnsavedChanges {
            isConfirmingDiscard = true
        } else {
            dismiss()
        }
    }

    private func performDelete(_ host: Host) {
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
                errorMessage = userFacingHostPersistenceMessage(error)
            }
        }
    }

    private func focusTarget(for field: ServerFormModel.Field?) -> iOSServerFormField? {
        switch field {
        case .address:
            return .address
        case .port:
            return .port
        case nil:
            return nil
        }
    }
}
#endif

#if os(iOS) && DEBUG
#Preview("iOS Edit Server") {
    PreviewContainer { environment in
        iOSServerEditor(
            store: environment.store,
            hosts: environment.hosts,
            host: environment.hosts[0]
        )
    }
}
#endif
