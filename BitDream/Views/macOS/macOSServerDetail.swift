import Foundation
import CoreData
import KeychainAccess
import SwiftUI

#if os(macOS)
struct ValidationTextFieldStyle: TextFieldStyle {
    var isInvalid: Bool

    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(RoundedBorderTextFieldStyle())
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.red, lineWidth: 1)
                    .opacity(isInvalid ? 1 : 0)
            )
    }
}

struct macOSServerDetail: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: Store
    var viewContext: NSManagedObjectContext
    var hosts: FetchedResults<Host>
    @State var host: Host?
    var isAddNew: Bool

    let keychain = Keychain(service: "crapshack.BitDream")

    @State var nameInput: String = ""
    @State var hostInput: String = ""
    @State var portInput: Int = ServerDetail.defaultPort
    @State var userInput: String = ""
    @State var passInput: String = ""
    @State var isDefault: Bool = false
    @State var isSSL: Bool = false
    @State private var hasAttemptedSave = false
    @State private var showingDeleteConfirmation = false

    private var isHostValid: Bool {
        !hostInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isPortValid: Bool {
        portInput >= 1 && portInput <= 65535
    }

    private func validateFields() -> Bool {
        hasAttemptedSave = true
        return isHostValid && isPortValid
    }

    var body: some View {
        // macOS version with native form styling
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(isAddNew ? "Add Server" : "Edit Server")
                    .font(.headline)
                    .padding()
                Spacer()
            }
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Form content
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 20) {
                    // Friendly Name
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Friendly Name")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        TextField("", text: $nameInput)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(maxWidth: .infinity)
                    }

                    // Default server
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Default", isOn: $isDefault)
                            .disabled(hosts.count == 0 || (hosts.count == 1 && (!isAddNew)))

                        Text("Automatically connect to this server on app startup.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // Host section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Host")
                            .font(.headline)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Hostname")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            TextField("127.0.0.1", text: $hostInput)
                                .textFieldStyle(ValidationTextFieldStyle(isInvalid: hasAttemptedSave && !isHostValid))
                                .autocorrectionDisabled()
                                .frame(maxWidth: .infinity)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Port")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            HStack {
                                TextField("", value: $portInput, formatter: ServerDetail.portFormatter)
                                    .textFieldStyle(ValidationTextFieldStyle(isInvalid: hasAttemptedSave && !isPortValid))
                                    .frame(maxWidth: .infinity)

                                Stepper("", value: $portInput, in: 1...65535)
                            }
                        }

                        Toggle("Use SSL", isOn: $isSSL)
                    }

                    // Authentication section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Authentication")
                            .font(.headline)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Username")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            TextField("", text: $userInput)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .autocorrectionDisabled()
                                .frame(maxWidth: .infinity)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Password")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            SecureField("", text: $passInput)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .frame(maxWidth: .infinity)
                        }
                    }

                    // Delete button (if editing)
                    if (!isAddNew) {
                        Button(action: {
                            showingDeleteConfirmation = true
                        }) {
                            HStack {
                                Image(systemName: "trash")
                                Text("Delete Server")
                            }
                            .foregroundColor(.red)
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 15)
                .frame(maxWidth: .infinity)
            }

            Divider()

            // Footer with buttons
            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)

                Button("Save") {
                    if (isAddNew) {
                        if validateFields() {
                            saveNewServer(
                                nameInput: nameInput,
                                hostInput: hostInput,
                                portInput: portInput,
                                userInput: userInput,
                                passInput: passInput,
                                isDefault: isDefault,
                                isSSL: isSSL,
                                viewContext: viewContext,
                                store: store,
                                keychain: keychain
                            ) {
                                dismiss()
                            }
                        }
                    } else {
                        if validateFields() {
                            if let host = host {
                                updateExistingServer(
                                    host: host,
                                    nameInput: nameInput,
                                    hostInput: hostInput,
                                    portInput: portInput,
                                    userInput: userInput,
                                    passInput: passInput,
                                    isDefault: isDefault,
                                    isSSL: isSSL,
                                    viewContext: viewContext,
                                    hosts: hosts,
                                    keychain: keychain
                                ) {
                                    dismiss()
                                }
                            }
                        }
                    }
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 400, alignment: .top)
        .frame(idealHeight: 600)
        .fixedSize(horizontal: true, vertical: false)
        .alert("Delete Server", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                if let host = host {
                    deleteServer(host: host, viewContext: viewContext) {
                        dismiss()
                    }
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to delete this server? This action cannot be undone.")
        }
        .onAppear {
            if (!isAddNew) {
                if let host = host {
                    loadServerData(host: host, keychain: keychain) { name, def, hostIn, port, ssl, user, pass in
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

            if (store.host == nil) {
                isDefault = true
            }
        }
    }
}
#else
// Empty struct for iOS to reference - this won't be compiled on macOS but provides the type
struct macOSServerDetail: View {
    @ObservedObject var store: Store
    var viewContext: NSManagedObjectContext
    var hosts: FetchedResults<Host>
    @State var host: Host?
    var isAddNew: Bool

    init(store: Store, viewContext: NSManagedObjectContext, hosts: FetchedResults<Host>, host: Host? = nil, isAddNew: Bool) {
        self.store = store
        self.viewContext = viewContext
        self.hosts = hosts
        self.host = host
        self.isAddNew = isAddNew
    }

    var body: some View {
        EmptyView()
    }
}
#endif
