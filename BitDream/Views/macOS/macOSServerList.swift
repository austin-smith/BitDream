import Foundation
import SwiftData
import SwiftUI

#if os(macOS)
struct MacOSServerEditorNavigationState: Equatable {
    enum Destination: Equatable {
        case server(String)
        case newServer
    }

    enum TransitionRequestResult: Equatable {
        case applied
        case confirmationRequired
        case ignored
    }

    private(set) var selectedServerID: String?
    private(set) var isCreatingNew = false
    private(set) var hasUnsavedChanges = false
    private(set) var pendingDestination: Destination?

    init(
        selectedServerID: String? = nil,
        isCreatingNew: Bool = false,
        hasUnsavedChanges: Bool = false,
        pendingDestination: Destination? = nil
    ) {
        self.selectedServerID = selectedServerID
        self.isCreatingNew = isCreatingNew
        self.hasUnsavedChanges = hasUnsavedChanges
        self.pendingDestination = pendingDestination
    }

    var currentDestination: Destination? {
        if isCreatingNew {
            return .newServer
        }
        return selectedServerID.map(Destination.server)
    }

    mutating func setHasUnsavedChanges(_ hasChanges: Bool) {
        hasUnsavedChanges = hasChanges
    }

    func canConnect(to serverID: String, connectedServerID: String?) -> Bool {
        guard serverID != connectedServerID else { return false }
        return selectedServerID != serverID || !hasUnsavedChanges
    }

    mutating func requestTransition(
        to destination: Destination,
        whileSaving: Bool
    ) -> TransitionRequestResult {
        guard !whileSaving, destination != currentDestination else {
            return .ignored
        }

        guard !hasUnsavedChanges else {
            pendingDestination = destination
            return .confirmationRequired
        }

        apply(destination)
        return .applied
    }

    mutating func confirmDiscardAndTransition() {
        guard let pendingDestination else { return }
        apply(pendingDestination)
    }

    mutating func cancelPendingTransition() {
        pendingDestination = nil
    }

    mutating func apply(_ destination: Destination) {
        pendingDestination = nil
        hasUnsavedChanges = false

        switch destination {
        case .server(let serverID):
            selectedServerID = serverID
            isCreatingNew = false
        case .newServer:
            selectedServerID = nil
            isCreatingNew = true
        }
    }

    mutating func reconcileSelection(
        availableServerIDs: [String],
        preferredServerID: String?
    ) {
        guard !isCreatingNew else { return }

        guard !availableServerIDs.isEmpty else {
            apply(.newServer)
            return
        }

        if let selectedServerID, availableServerIDs.contains(selectedServerID) {
            return
        }

        let fallbackServerID = preferredServerID.flatMap { preferredID in
            availableServerIDs.contains(preferredID) ? preferredID : nil
        } ?? availableServerIDs[0]
        apply(.server(fallbackServerID))
    }

    mutating func didSave(serverID: String) {
        hasUnsavedChanges = false
        guard isCreatingNew else { return }
        apply(.server(serverID))
    }

    mutating func didDelete(serverID: String, remainingServerIDs: [String]) {
        guard selectedServerID == serverID else { return }

        guard !remainingServerIDs.isEmpty else {
            apply(.newServer)
            return
        }

        apply(.server(remainingServerIDs[0]))
    }
}

private enum MacOSServerListAlert {
    case discardChanges
    case error(String)

    var title: String {
        switch self {
        case .discardChanges:
            return "Discard Changes?"
        case .error:
            return "Error"
        }
    }

    var message: String {
        switch self {
        case .discardChanges:
            return "Your unsaved server changes will be lost."
        case .error(let message):
            return message
        }
    }
}

/// Root view for the Manage Servers auxiliary window.
struct macOSManageServersWindow: View {
    @EnvironmentObject var store: TransmissionStore
    @Query(sort: \Host.name, order: .forward) private var hosts: [Host]

    var body: some View {
        macOSServerList(
            hosts: hosts,
            store: store
        )
    }
}

struct macOSServerList: View {
    @Environment(\.hostRepositoryProvider) private var hostRepositoryProvider
    let hosts: [Host]
    @ObservedObject var store: TransmissionStore

    @State private var editorNavigation = MacOSServerEditorNavigationState()
    @State private var isSaving = false
    @State private var confirmingDelete = false
    @State private var serverToDelete: Host?
    @State private var activeAlert: MacOSServerListAlert?

    private var sortedHosts: [Host] {
        hosts.sortedByDisplayName()
    }

    private var selectedHost: Host? {
        guard let selectedServerID = editorNavigation.selectedServerID else { return nil }
        return hosts.first(where: { $0.serverID == selectedServerID })
    }

    private var editorIdentity: String {
        editorNavigation.isCreatingNew ? "new-server" : (editorNavigation.selectedServerID ?? "no-selection")
    }

    private var canConnectSelectedServer: Bool {
        guard let selectedHost else { return false }
        return editorNavigation.canConnect(
            to: selectedHost.serverID,
            connectedServerID: store.host?.serverID
        )
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .disabled(isSaving)
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 320)
        } detail: {
            detailPane
        }
        .frame(minWidth: 640, minHeight: 400)
        .confirmationDialog(
            "Delete Server",
            isPresented: $confirmingDelete,
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
        .alert(
            activeAlert?.title ?? "Error",
            isPresented: isPresentingAlert,
            presenting: activeAlert
        ) { alert in
            switch alert {
            case .discardChanges:
                Button("Discard Changes", role: .destructive, action: confirmDiscardAndTransition)
                Button("Cancel", role: .cancel, action: cancelPendingTransition)
            case .error:
                Button("OK", role: .cancel) {}
            }
        } message: { alert in
            Text(alert.message)
        }
        .dismissalConfirmationDialog(
            dismissalConfirmationTitle,
            shouldPresent: editorNavigation.hasUnsavedChanges || isSaving
        ) {
            if !isSaving {
                Button("Discard Changes", role: .destructive) {
                    editorNavigation.setHasUnsavedChanges(false)
                }
            }
        } message: {
            Text(dismissalConfirmationMessage)
        }
        .onAppear(perform: syncSelection)
        .onChange(of: hosts.map(\.serverID)) { _, _ in
            syncSelection()
        }
    }
}

private extension macOSServerList {
    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: serverSelection) {
                ForEach(sortedHosts) { host in
                    ServerRowLabel(
                        host: host,
                        isConnected: host.serverID == store.host?.serverID
                    )
                    .tag(host.serverID)
                    .contextMenu {
                        Button("Connect") {
                            connect(to: host)
                        }
                        .disabled(
                            !editorNavigation.canConnect(
                                to: host.serverID,
                                connectedServerID: store.host?.serverID
                            )
                        )

                        Divider()

                        Button("Delete…", role: .destructive) {
                            serverToDelete = host
                            confirmingDelete = true
                        }
                    }
                }
            }
            .onDeleteCommand(perform: promptDeleteSelectedServer)
            .overlay {
                if hosts.isEmpty {
                    ContentUnavailableView {
                        Label("No Servers", systemImage: "server.rack")
                    } description: {
                        Text("Click \(Image(systemName: "plus")) to add a server.")
                    }
                }
            }

            listGutter
        }
    }

    private var listGutter: some View {
        HStack(spacing: 2) {
            Button {
                startCreatingServer()
            } label: {
                Image(systemName: "plus")
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .help("Add a server")
            .accessibilityLabel("Add Server")

            Button {
                promptDeleteSelectedServer()
            } label: {
                Image(systemName: "minus")
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .disabled(selectedHost == nil)
            .help("Remove the selected server")
            .accessibilityLabel("Remove Server")

            Spacer()
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        if editorNavigation.isCreatingNew || selectedHost != nil {
            VStack(spacing: 0) {
                detailHeader

                macOSServerEditor(
                    store: store,
                    hosts: hosts,
                    host: selectedHost,
                    title: nil,
                    saveButtonTitle: editorNavigation.isCreatingNew ? "Add Server" : "Save Changes",
                    cancelButtonTitle: editorNavigation.isCreatingNew && !hosts.isEmpty ? "Cancel" : nil,
                    onCancel: editorNavigation.isCreatingNew && !hosts.isEmpty ? { cancelCreatingServer() } : nil,
                    onSaved: handleEditorSaved,
                    onDelete: nil,
                    onConnect: editorNavigation.isCreatingNew ? nil : { connectSelectedServer() },
                    canConnect: canConnectSelectedServer,
                    hasUnsavedChanges: hasUnsavedChanges,
                    isSaving: $isSaving,
                    onError: presentError
                )
            }
            .id(editorIdentity)
        } else {
            ContentUnavailableView {
                Label("No Server Selected", systemImage: "server.rack")
            } description: {
                Text("Select a server in the sidebar, or click \(Image(systemName: "plus")) to add one.")
            }
        }
    }

    private var detailHeader: some View {
        HStack(spacing: 8) {
            Text(editorNavigation.isCreatingNew ? "New Server" : (selectedHost?.displayName ?? ""))
                .font(.title3.weight(.semibold))
                .lineLimit(1)

            if let versionLabel {
                Text(versionLabel)
                    .font(.caption.weight(.medium).monospaced())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
                    .help("Transmission version reported by this server")
            }

            Spacer()
        }
        .frame(height: 24)
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    private var versionLabel: String? {
        guard !editorNavigation.isCreatingNew,
              let raw = selectedHost?.version?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }
        return "v\(raw)"
    }

    private func syncSelection() {
        editorNavigation.reconcileSelection(
            availableServerIDs: sortedHosts.map(\.serverID),
            preferredServerID: store.host?.serverID
        )
    }

    private func startCreatingServer() {
        requestTransition(to: .newServer)
    }

    private func cancelCreatingServer() {
        guard let serverID = preferredSelectionAfterCancel else { return }
        editorNavigation.apply(.server(serverID))
    }

    private func promptDeleteSelectedServer() {
        guard let selectedHost else { return }
        serverToDelete = selectedHost
        confirmingDelete = true
    }

    private func connectSelectedServer() {
        guard let selectedHost else { return }
        connect(to: selectedHost)
    }

    private func connect(to host: Host) {
        guard editorNavigation.canConnect(
            to: host.serverID,
            connectedServerID: store.host?.serverID
        ) else { return }
        store.setHost(host: host)
    }

    private func handleEditorSaved(_ savedHost: Host) {
        editorNavigation.didSave(serverID: savedHost.serverID)
    }

    private var serverSelection: Binding<String?> {
        Binding(
            get: { editorNavigation.selectedServerID },
            set: { requestedServerID in
                guard let requestedServerID else { return }
                requestTransition(to: .server(requestedServerID))
            }
        )
    }

    private var hasUnsavedChanges: Binding<Bool> {
        Binding(
            get: { editorNavigation.hasUnsavedChanges },
            set: { editorNavigation.setHasUnsavedChanges($0) }
        )
    }

    private var isPresentingAlert: Binding<Bool> {
        Binding(
            get: { activeAlert != nil },
            set: { isPresented in
                guard !isPresented else { return }
                if case .discardChanges = activeAlert {
                    editorNavigation.cancelPendingTransition()
                }
                activeAlert = nil
            }
        )
    }

    private var preferredSelectionAfterCancel: String? {
        if let activeServerID = store.host?.serverID,
           hosts.contains(where: { $0.serverID == activeServerID }) {
            return activeServerID
        }
        return sortedHosts.first?.serverID
    }

    private var dismissalConfirmationTitle: String {
        isSaving ? "Save in Progress" : "Discard Changes?"
    }

    private var dismissalConfirmationMessage: String {
        if isSaving {
            return "Wait for the server save to finish before closing this window."
        }
        return "Your unsaved server changes will be lost."
    }

    private func requestTransition(to destination: MacOSServerEditorNavigationState.Destination) {
        let result = editorNavigation.requestTransition(to: destination, whileSaving: isSaving)
        if result == .confirmationRequired {
            activeAlert = .discardChanges
        }
    }

    private func confirmDiscardAndTransition() {
        editorNavigation.confirmDiscardAndTransition()
        activeAlert = nil
    }

    private func cancelPendingTransition() {
        editorNavigation.cancelPendingTransition()
        activeAlert = nil
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
                let remainingServerIDs = sortedHosts
                    .filter { $0.serverID != host.serverID }
                    .map(\.serverID)
                editorNavigation.didDelete(
                    serverID: host.serverID,
                    remainingServerIDs: remainingServerIDs
                )
                serverToDelete = nil
            } catch {
                serverToDelete = nil
                presentError(userFacingHostPersistenceMessage(error))
            }
        }
    }

    private func presentError(_ message: String) {
        editorNavigation.cancelPendingTransition()
        activeAlert = .error(message)
    }
}

#endif

#if os(macOS) && DEBUG
#Preview("macOS Server List", traits: .fixedLayout(width: 900, height: 600)) {
    PreviewContainer { environment in
        macOSServerList(hosts: environment.hosts, store: environment.store)
    }
}
#endif
