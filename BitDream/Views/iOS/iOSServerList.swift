import SwiftUI

#if os(iOS)
/// Sheet listing the configured servers with add, edit, connect, and delete actions.
struct iOSServerList: View {
    @Environment(\.dismiss) private var dismiss
    let hosts: [Host]
    @ObservedObject var store: TransmissionStore

    @State private var presentedEditor: EditorPresentation?
    @State private var serverToDelete: Host?
    @State private var isConfirmingDelete = false
    @State private var errorMessage: String?

    private enum EditorPresentation: Identifiable {
        case add
        case edit(Host)

        var id: String {
            switch self {
            case .add:
                return "add"
            case .edit(let host):
                return "edit-\(host.serverID)"
            }
        }
    }

    private var sortedHosts: [Host] {
        hosts.sortedByDisplayName()
    }

    var body: some View {
        NavigationStack {
            List {
                if !sortedHosts.isEmpty {
                    Section {
                        Picker(selection: activeServerID) {
                            ForEach(sortedHosts) { host in
                                Text(host.displayName)
                                    .tag(Optional(host.serverID))
                            }
                        } label: {
                            Label("Current Server", systemImage: "server.rack")
                        }
                        .pickerStyle(.navigationLink)
                    }

                    Section("Servers") {
                        ForEach(sortedHosts) { host in
                            row(for: host)
                        }
                    }
                }
            }
            .navigationTitle("Servers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Add Server", systemImage: "plus") {
                        presentedEditor = .add
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close", systemImage: "xmark", role: .close) {
                        dismiss()
                    }
                }
            }
            .overlay {
                if hosts.isEmpty {
                    ContentUnavailableView {
                        Label("No Servers", systemImage: "server.rack")
                    } description: {
                        Text("Add a server to get started with BitDream.")
                    } actions: {
                        Button("Add Server") {
                            presentedEditor = .add
                        }
                    }
                }
            }
            .confirmationDialog(
                "Delete Server",
                isPresented: $isConfirmingDelete,
                presenting: serverToDelete,
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
            .sheet(item: $presentedEditor) { presentation in
                switch presentation {
                case .add:
                    iOSServerEditor(store: store, hosts: hosts, host: nil)
                case .edit(let host):
                    iOSServerEditor(store: store, hosts: hosts, host: host)
                }
            }
        }
    }

    private var activeServerID: Binding<String?> {
        Binding(
            get: { store.host?.serverID },
            set: { serverID in
                guard let serverID,
                      let host = hosts.first(where: { $0.serverID == serverID }) else { return }
                store.setHost(host: host)
            }
        )
    }

    private func row(for host: Host) -> some View {
        let isConnected = host.serverID == store.host?.serverID

        return Button {
            presentedEditor = .edit(host)
        } label: {
            ServerRowLabel(host: host, isConnected: isConnected)
        }
        .tint(.primary)
        .contextMenu {
            Button("Connect", systemImage: "bolt.fill") {
                store.setHost(host: host)
            }
            .disabled(isConnected)

            Button("Edit", systemImage: "square.and.pencil") {
                presentedEditor = .edit(host)
            }

            Divider()

            Button("Delete…", systemImage: "trash", role: .destructive) {
                promptDelete(host)
            }
        }
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

    private func promptDelete(_ host: Host) {
        serverToDelete = host
        isConfirmingDelete = true
    }

    private func performDelete(_ host: Host) {
        Task {
            do {
                try await deleteServer(host: host, store: store, hosts: hosts)
                serverToDelete = nil
            } catch {
                serverToDelete = nil
                errorMessage = userFacingHostPersistenceMessage(error)
            }
        }
    }
}
#endif
