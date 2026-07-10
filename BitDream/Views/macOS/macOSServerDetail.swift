import Foundation
import SwiftData
import SwiftUI

#if os(macOS)
private enum macOSServerFormFocusField: Hashable {
    case name
    case host
    case port
    case username
    case password
}

private struct macOSServerFormValues: Equatable {
    var name = ""
    var host = ""
    var port = ServerDetail.defaultPort
    var username = ""
    var password = ""
    var isDefault = false
    var isSSL = false
}

struct macOSServerEditor: View {
    @ObservedObject var store: TransmissionStore
    let hosts: [Host]
    let host: Host?
    let isAddNew: Bool
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

    @State private var nameInput = ""
    @State private var hostInput = ""
    @State private var portInput = ServerDetail.defaultPort
    @State private var userInput = ""
    @State private var passInput = ""
    @State private var isDefault = false
    @State private var isSSL = false
    @State private var hasAttemptedSave = false
    @State private var initialValues = macOSServerFormValues()
    @State private var hasConfiguredValues = false

    @FocusState private var focusedField: macOSServerFormFocusField?

    private var isHostValid: Bool {
        !hostInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isPortValid: Bool {
        portInput >= 1 && portInput <= 65535
    }

    private var currentValues: macOSServerFormValues {
        macOSServerFormValues(
            name: nameInput,
            host: hostInput,
            port: portInput,
            username: userInput,
            password: passInput,
            isDefault: isDefault,
            isSSL: isSSL
        )
    }

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
                    TextField("Name", text: $nameInput, prompt: Text("Office NAS"))
                        .focused($focusedField, equals: .name)

                    Toggle(isOn: $isDefault) {
                        Text("Default")
                        Text("Preferred server when connecting at launch.")
                    }
                    .disabled(hosts.count == 0 || (hosts.count == 1 && !isAddNew))
                }

                Section {
                    TextField("Address", text: $hostInput, prompt: Text("127.0.0.1"))
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .host)

                    HStack {
                        TextField(
                            "Port",
                            value: $portInput,
                            format: .number.grouping(.never),
                            prompt: Text("9091")
                        )
                        .focused($focusedField, equals: .port)

                        Stepper("Port", value: $portInput, in: 1...65535)
                            .labelsHidden()
                    }

                    Toggle("Use SSL", isOn: $isSSL)
                } header: {
                    Text("Connection")
                } footer: {
                    connectionValidationFooter
                }

                Section("Authentication") {
                    TextField("Username", text: $userInput, prompt: Text("Optional"))
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .username)

                    SecureField("Password", text: $passInput, prompt: Text("Optional"))
                        .focused($focusedField, equals: .password)
                }

            }
            .formStyle(.grouped)
            .disabled(isSaving)

            Divider()

            footerBar
        }
        .onAppear(perform: configureInitialValues)
        .onChange(of: currentValues) { _, newValues in
            guard hasConfiguredValues else { return }
            hasUnsavedChanges = newValues != initialValues
        }
    }

    @ViewBuilder
    private var connectionValidationFooter: some View {
        if hasAttemptedSave && !isHostValid {
            Text(ServerDetail.hostRequiredMessage)
                .foregroundStyle(.red)
        } else if hasAttemptedSave && !isPortValid {
            Text(ServerDetail.invalidPortMessage)
                .foregroundStyle(.red)
        }
    }

    private var footerBar: some View {
        HStack {
            if !isAddNew, let onConnect {
                Button("Connect", action: onConnect)
                    .disabled(!canConnect || isSaving)
                    .help(connectButtonHelp)
            }

            if !isAddNew, let onDelete {
                Button("Delete…", role: .destructive, action: onDelete)
                    .disabled(isSaving)
            }

            Spacer()

            if let cancelButtonTitle, let onCancel {
                Button(cancelButtonTitle, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .disabled(isSaving)
            }

            Button(saveButtonTitle, action: performSave)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(isSaving)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var connectButtonHelp: String {
        if hasUnsavedChanges {
            return "Save changes before connecting to this server"
        }
        return canConnect ? "Connect to this server" : "Already connected to this server"
    }

    private func configureInitialValues() {
        if let host, !isAddNew {
            loadServerData(host: host) { name, `default`, hostname, port, ssl, user, pass in
                applyInitialValues(
                    macOSServerFormValues(
                        name: name,
                        host: hostname,
                        port: port,
                        username: user,
                        password: pass,
                        isDefault: `default`,
                        isSSL: ssl
                    )
                )
            }
        } else {
            applyInitialValues(
                macOSServerFormValues(isDefault: store.host == nil)
            )
            focusedField = .host
        }
    }

    private func applyInitialValues(_ values: macOSServerFormValues) {
        hasConfiguredValues = false
        nameInput = values.name
        hostInput = values.host
        portInput = values.port
        userInput = values.username
        passInput = values.password
        isDefault = values.isDefault
        isSSL = values.isSSL
        initialValues = values
        hasAttemptedSave = false
        hasUnsavedChanges = false
        isSaving = false
        hasConfiguredValues = true
    }

    private func performSave() {
        guard validateFields() else {
            focusedField = firstInvalidField
            return
        }

        isSaving = true

        let draft = HostDraft(
            name: nameInput,
            server: hostInput,
            port: portInput,
            username: userInput,
            isSSL: isSSL,
            isDefault: isDefault,
            password: passInput
        )

        if isAddNew {
            saveNewServer(
                draft: draft,
                store: store
            ) { createdHost in
                finishSave(with: createdHost)
            } onError: { message in
                handleSaveError(message)
            }
            return
        }

        guard let host else {
            isSaving = false
            return
        }

        updateExistingServer(
            host: host,
            draft: draft,
            store: store
        ) {
            finishSave(with: host)
        } onError: { message in
            handleSaveError(message)
        }
    }

    private func finishSave(with savedHost: Host) {
        initialValues = currentValues
        hasUnsavedChanges = false
        isSaving = false
        onSaved(savedHost)
    }

    private func handleSaveError(_ message: String) {
        isSaving = false
        onError(message)
    }

    private func validateFields() -> Bool {
        hasAttemptedSave = true
        return isHostValid && isPortValid
    }

    private var firstInvalidField: macOSServerFormFocusField? {
        if !isHostValid {
            return .host
        }
        if !isPortValid {
            return .port
        }
        return nil
    }
}

struct macOSServerDetail: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var store: TransmissionStore
    let modelContext: ModelContext
    let hosts: [Host]
    @State var host: Host?
    var isAddNew: Bool

    @State private var showingDeleteConfirmation = false
    @State private var hasUnsavedChanges = false
    @State private var isSaving = false

    var body: some View {
        macOSServerEditor(
            store: store,
            hosts: hosts,
            host: host,
            isAddNew: isAddNew,
            title: isAddNew ? "Add Server" : "Edit Server",
            saveButtonTitle: "Save",
            cancelButtonTitle: "Cancel",
            onCancel: { dismiss() },
            onSaved: { _ in dismiss() },
            onDelete: isAddNew ? nil : { showingDeleteConfirmation = true },
            hasUnsavedChanges: $hasUnsavedChanges,
            isSaving: $isSaving,
            onError: presentError
        )
        .frame(width: 460, height: 560)
        .interactiveDismissDisabled(isSaving)
        .alert("Delete Server", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                if let host {
                    deleteServerFromDetail(host: host, store: store, hosts: hosts, modelContext: modelContext) {
                        dismiss()
                    } onError: { message in
                        presentError(message)
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
