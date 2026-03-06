import Foundation
import SwiftUI
import SwiftData

#if os(iOS)
struct iOSServerDetail: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: AppStore
    let modelContext: ModelContext
    let hosts: [Host]
    @State var host: Host?
    var isAddNew: Bool

    @State var nameInput: String = ""
    @State var hostInput: String = ""
    @State var portInput: Int = ServerDetail.defaultPort
    @State var userInput: String = ""
    @State var passInput: String = ""
    @State var isDefault: Bool = false
    @State var isSSL: Bool = false
    @State private var showingValidationAlert = false
    @State private var validationMessage = ""
    @State private var showingDeleteConfirmation = false

    private var isHostValid: Bool {
        !hostInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isPortValid: Bool {
        portInput >= 1 && portInput <= 65535
    }

    private func validateFields() -> Bool {
        if !isHostValid {
            validationMessage = ServerDetail.hostRequiredMessage
            showingValidationAlert = true
            return false
        }
        if !isPortValid {
            validationMessage = ServerDetail.invalidPortMessage
            showingValidationAlert = true
            return false
        }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                HStack {
                    Text("Friendly Name")
                    TextField("friendly name", text: $nameInput)
                        .multilineTextAlignment(.trailing)
                }

                Section(footer: Text("Automatically connect to this server on app startup.")) {
                    Toggle("Default", isOn: $isDefault)
                        // disable the "Default" toggle if this is the only server
                        // it is either the first server being added, or the only one that exists
                        .disabled(hosts.count == 0 || (hosts.count == 1 && (!isAddNew)))
                }

                Section(header: Text("Host")) {
                    HStack {
                        Text("Hostname")
                        TextField("hostname", text: $hostInput)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }

                    HStack {
                        Text("Port")
                        TextField("port", value: $portInput, format: .number.grouping(.never))
                            .multilineTextAlignment(.trailing)
                    }

                    Toggle("Use SSL", isOn: $isSSL)
                        .onAppear {
                            if store.host == nil {
                                isDefault = true
                            }
                        }
                }

                Section(header: Text("Authentication")) {
                    HStack {
                        Text("Username")
                        TextField("username", text: $userInput)
                            .multilineTextAlignment(.trailing)
                            .autocapitalization(.none)
                            // .textInputAutocapitalization(.never)
                    }

                    HStack {
                        Text("Password")
                        SecureField("password", text: $passInput)
                            .multilineTextAlignment(.trailing)
                    }
                }

                if !isAddNew {
                    Button(role: .destructive, action: {
                        showingDeleteConfirmation = true
                    }, label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("Delete Server")
                            Spacer()
                        }
                    })
                }
            }
            .onAppear {
                if !isAddNew {
                    if let host = host {
                        loadServerData(host: host) { name, def, hostIn, port, ssl, user, pass in
                            nameInput = name
                            isDefault = def
                            hostInput = hostIn
                            portInput = port
                            isSSL = ssl
                            userInput = user
                            passInput = pass
                        }
                    }
                }
            }
            .alert("Required Fields", isPresented: $showingValidationAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(validationMessage)
            }
            .alert("Delete Server", isPresented: $showingDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    if let host = host {
                        deleteServerFromDetail(host: host, store: store, hosts: hosts, modelContext: modelContext) {
                            dismiss()
                        } onError: { message in
                            validationMessage = message
                            showingValidationAlert = true
                        }
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Are you sure you want to delete this server? This action cannot be undone.")
            }
            .navigationBarTitle(Text(isAddNew ? "Add Server" : "Edit Server"), displayMode: .inline)
            .toolbar {
                if isAddNew {
                    ToolbarItem(placement: .automatic) {
                        Button("Save") {
                            if validateFields() {
                                let draft = HostDraft(
                                    name: nameInput,
                                    server: hostInput,
                                    port: portInput,
                                    username: userInput,
                                    isSSL: isSSL,
                                    isDefault: isDefault,
                                    password: passInput
                                )
                                saveNewServer(
                                    draft: draft,
                                    modelContext: modelContext,
                                    store: store
                                ) {
                                    dismiss()
                                } onError: { message in
                                    validationMessage = message
                                    showingValidationAlert = true
                                }
                            }
                        }
                    }
                } else {
                    ToolbarItem(placement: .automatic) {
                        Button("Save") {
                            if validateFields() {
                                if let host = host {
                                    let draft = HostDraft(
                                        name: nameInput,
                                        server: hostInput,
                                        port: portInput,
                                        username: userInput,
                                        isSSL: isSSL,
                                        isDefault: isDefault,
                                        password: passInput
                                    )
                                    updateExistingServer(
                                        host: host,
                                        draft: draft
                                    ) {
                                        dismiss()
                                    } onError: { message in
                                        validationMessage = message
                                        showingValidationAlert = true
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
#endif
