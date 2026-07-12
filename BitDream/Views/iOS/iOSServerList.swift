import SwiftUI

#if os(iOS)
/// Sheet listing the configured servers with add, edit, connect, and delete actions.
struct iOSServerList: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.hapticFeedback) private var hapticFeedback
    @Environment(\.hostRepositoryProvider) private var hostRepositoryProvider
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

                    Section {
                        Button {
                            hapticFeedback.play(.actionTriggered)
                            presentedEditor = .add
                        } label: {
                            Label("New Server", systemImage: "plus")
                                .frame(maxWidth: .infinity)
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
            .navigationTitle("Servers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close", systemImage: "xmark", role: .close) {
                        hapticFeedback.play(.actionTriggered)
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
                            hapticFeedback.play(.actionTriggered)
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
                Button("OK", role: .cancel) {
                    hapticFeedback.play(.actionTriggered)
                }
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
                hapticFeedback.play(.selectionChanged)
            }
        )
    }

    private func row(for host: Host) -> some View {
        let isConnected = host.serverID == store.host?.serverID

        return Button {
            hapticFeedback.play(.actionTriggered)
            presentedEditor = .edit(host)
        } label: {
            ServerRowLabel(host: host, isConnected: isConnected)
        }
        .tint(.primary)
        .contextMenu {
            Button("Connect", systemImage: "bolt.fill") {
                store.setHost(host: host)
                hapticFeedback.play(.selectionChanged)
            }
            .disabled(isConnected)

            Button("Edit", systemImage: "square.and.pencil") {
                hapticFeedback.play(.actionTriggered)
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
        hapticFeedback.play(.actionTriggered)
        serverToDelete = host
        isConfirmingDelete = true
    }

    private func performDelete(_ host: Host) {
        hapticFeedback.play(.actionTriggered)
        Task {
            do {
                try await deleteServer(
                    host: host,
                    store: store,
                    hosts: hosts,
                    hostRepository: hostRepositoryProvider.resolve()
                )
                hapticFeedback.play(.operationSucceeded)
                serverToDelete = nil
            } catch {
                serverToDelete = nil
                hapticFeedback.play(.operationFailed)
                errorMessage = userFacingHostPersistenceMessage(error)
            }
        }
    }
}
#endif

#if os(iOS) && DEBUG
#Preview("iOS Servers") {
    PreviewContainer { environment in
        iOSServerList(hosts: environment.hosts, store: environment.store)
    }
}
#endif
