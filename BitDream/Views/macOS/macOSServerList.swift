import Foundation
import SwiftUI
import SwiftData

#if os(macOS)
struct macOSServerList: View {
    @Environment(\.dismiss) private var dismiss
    let modelContext: ModelContext
    let hosts: [Host]
    @ObservedObject var store: TransmissionStore

    @State var selected: Host?
    @State private var showingAddServer = false
    @State private var confirmingDelete = false
    @State private var serverToDelete: Host?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Manage Servers")
                    .font(.headline)
                    .padding()
                Spacer()
                Button(action: {
                    dismiss()
                }, label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                })
                .buttonStyle(PlainButtonStyle())
                .padding()
            }
            .background(Color(NSColor.windowBackgroundColor))

            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: []) {
                    if hosts.isEmpty {
                        emptyServerListView
                    } else {
                        ForEach(hosts) { host in
                            VStack {
                                HStack {
                                    Image(systemName: "server.rack")
                                        .foregroundColor(.accentColor)
                                        .frame(width: 24, height: 24)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(host.name ?? "Unnamed Server")
                                            .font(.headline)

                                        Text("\(host.server ?? "Unknown server"):\(String(host.port))")
                                            .font(.caption)
                                            .foregroundColor(.secondary)

                                        if let version = host.version {
                                            Text("\(version)")
                                                .font(.caption)
                                                .foregroundColor(.purple)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 2)
                                                .background(
                                                    Capsule()
                                                        .fill(Color.purple.opacity(0.1))
                                                )
                                        }
                                    }

                                    Spacer()

                                    // Status badges
                                    HStack(spacing: 8) {
                                        // Default server badge
                                        if host.isDefault {
                                            Text("Default")
                                                .font(.caption)
                                                .foregroundColor(.blue)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 2)
                                                .background(
                                                    Capsule()
                                                        .fill(Color.blue.opacity(0.1))
                                                )
                                        }

                                        // Connected server badge
                                        if host.serverID == store.host?.serverID {
                                            Text("Connected")
                                                .font(.caption)
                                                .foregroundColor(.green)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 2)
                                                .background(
                                                    Capsule()
                                                        .fill(Color.green.opacity(0.1))
                                                )
                                        }
                                    }

                                    Button {
                                        selected = host
                                    } label: {
                                        Image(systemName: "pencil")
                                            .foregroundColor(.accentColor)
                                    }
                                    .buttonStyle(HoverButtonStyle())

                                    Button {
                                        serverToDelete = host
                                        confirmingDelete = true
                                    } label: {
                                        Image(systemName: "trash")
                                            .foregroundColor(.red)
                                    }
                                    .buttonStyle(HoverButtonStyle())
                                }
                                .padding(.vertical, 4)
                                .padding(.horizontal)
                                .contentShape(Rectangle())
                                Divider()
                            }
                        }
                    }
                }
            }
            .confirmationDialog(
                "Delete Server",
                isPresented: $confirmingDelete,
                presenting: serverToDelete,
                actions: { host in
                Button("Delete \(host.name ?? "Unnamed Server")", role: .destructive) {
                    deleteServer(host: host, store: store, hosts: hosts, modelContext: modelContext) {
                        serverToDelete = nil
                    } onError: { message in
                        store.globalAlertTitle = "Error"
                        store.globalAlertMessage = message
                        store.showGlobalAlert = true
                    }
                }
            },
                message: { host in
                deleteConfirmationMessage(for: host, store: store)
            })

            Divider()

            HStack {
                Button(action: {
                    showingAddServer = true
                }, label: {
                    Label("Add New", systemImage: "plus")
                })
                .buttonStyle(.borderedProminent)

                Spacer()
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 500, height: 400)
        .background(Color(NSColor.windowBackgroundColor))
        // Sheet for editing an existing server
        .sheet(item: $selected, content: { host in
            ServerDetail(store: store, modelContext: modelContext, hosts: hosts, host: host, isAddNew: false)
        })
        // Sheet for adding a new server
        .sheet(isPresented: $showingAddServer, content: {
            ServerDetail(store: store, modelContext: modelContext, hosts: hosts, isAddNew: true)
        })
    }

    // Empty state view for when there are no servers
    private var emptyServerListView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "server.rack")
                .font(.system(size: 50))
                .foregroundColor(.secondary.opacity(0.5))

            Text("No Servers Added")
                .font(.headline)
                .foregroundColor(.primary)

            Text("Add a server to get started with BitDream")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button(action: {
                showingAddServer = true
            }, label: {
                Label("Add Your First Server", systemImage: "plus")
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            })
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 10)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
#endif
