import SwiftUI

#if os(macOS)
private enum macOSServerFormFocusField: Hashable {
    case name
    case address
    case port
    case username
    case password
}

struct macOSServerEditor: View {
    @Environment(\.hostRepositoryProvider) private var hostRepositoryProvider
    @ObservedObject var store: TransmissionStore
    let hosts: [Host]
    let host: Host?
    let title: String?
    let saveButtonTitle: String
    let cancelButtonTitle: String?
    let onCancel: (() -> Void)?
    let onSaved: (Host) -> Void
    let onDelete: (() -> Void)?
    var onConnect: (() -> Void)?
    var canConnect: Bool = false
    @Binding var hasUnsavedChanges: Bool
    @Binding var isSaving: Bool
    let onError: (String) -> Void

    @State private var model = ServerFormModel()

    @FocusState private var focusedField: macOSServerFormFocusField?

    private var isAddNew: Bool { host == nil }

    var body: some View {
        VStack(spacing: 0) {
            if let title {
                Text(title)
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)

                Divider()
            }

            Form {
                Section {
                    TextField("Name", text: $model.values.name, prompt: Text("Friendly name"))
                        .focused($focusedField, equals: .name)

                    Toggle(isOn: $model.values.isDefault) {
                        Text("Default")
                        Text("Preferred server when connecting at launch.")
                    }
                    .disabled(!model.canEditDefaultToggle(hostCount: hosts.count))
                }

                Section {
                    TextField("Address", text: $model.values.address, prompt: Text("127.0.0.1"))
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .address)

                    HStack {
                        TextField(
                            "Port",
                            value: $model.values.port,
                            format: .number.grouping(.never),
                            prompt: Text("9091")
                        )
                        .focused($focusedField, equals: .port)

                        Stepper("Port", value: $model.values.port, in: ServerFormModel.portRange)
                            .labelsHidden()
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
                    TextField("Username", text: $model.values.username, prompt: Text("Optional"))
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .username)

                    SecureField("Password", text: $model.values.password, prompt: Text("Optional"))
                        .focused($focusedField, equals: .password)
                }
            }
            .formStyle(.grouped)
            .disabled(model.isSaving)

            Divider()

            footerBar
        }
        .onAppear(perform: configureModel)
        .onChange(of: model.hasUnsavedChanges, initial: true) { _, newValue in
            hasUnsavedChanges = newValue
        }
        .onChange(of: model.isSaving, initial: true) { _, newValue in
            isSaving = newValue
        }
    }

    private var footerBar: some View {
        HStack {
            if !isAddNew, let onConnect {
                Button("Connect", action: onConnect)
                    .disabled(!canConnect || model.isSaving)
                    .help(connectButtonHelp)
            }

            if !isAddNew, let onDelete {
                Button("Delete…", role: .destructive, action: onDelete)
                    .disabled(model.isSaving)
            }

            Spacer()

            if let cancelButtonTitle, let onCancel {
                Button(cancelButtonTitle, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .disabled(model.isSaving)
            }

            Button(saveButtonTitle, action: performSave)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(model.isSaving)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var connectButtonHelp: String {
        if model.hasUnsavedChanges {
            return "Save changes before connecting to this server"
        }
        return canConnect ? "Connect to this server" : "Already connected to this server"
    }

    private func configureModel() {
        model.configure(host: host, store: store)
        if isAddNew {
            focusedField = .address
        }
    }

    private func performSave() {
        Task {
            do {
                switch try await model.save(
                    store: store,
                    hostRepository: hostRepositoryProvider.resolve()
                ) {
                case .validationFailed(let field):
                    focusedField = focusTarget(for: field)
                case .saved(let savedHost):
                    onSaved(savedHost)
                }
            } catch {
                onError(userFacingHostPersistenceMessage(error))
            }
        }
    }

    private func focusTarget(for field: ServerFormModel.Field?) -> macOSServerFormFocusField? {
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

#if os(macOS) && DEBUG
#Preview("macOS Server Editor", traits: .fixedLayout(width: 460, height: 560)) {
    @Previewable @State var hasUnsavedChanges = false
    @Previewable @State var isSaving = false

    PreviewContainer { environment in
        macOSServerEditor(
            store: environment.store,
            hosts: environment.hosts,
            host: environment.hosts[0],
            title: "Edit Server",
            saveButtonTitle: "Save",
            cancelButtonTitle: "Cancel",
            onCancel: {},
            onSaved: { _ in },
            onDelete: {},
            hasUnsavedChanges: $hasUnsavedChanges,
            isSaving: $isSaving,
            onError: { _ in }
        )
    }
}
#endif
