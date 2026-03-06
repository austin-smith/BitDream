import Foundation
import SwiftUI
import SwiftData

#if os(iOS)
struct iOSServerList: View {
    @Environment(\.dismiss) private var dismiss
    let modelContext: ModelContext
    let hosts: [Host]
    @ObservedObject var store: AppStore

    @State private var showingAddServer = false

    var body: some View {
        // Use a simple VStack instead of nested navigation containers
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Servers")
                    .font(.headline)
                    .padding()
                Spacer()
                Button(action: {
                    dismiss()
                }, label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                })
                .padding()
            }

            // Content
            List {
                if hosts.isEmpty {
                    emptyServerListView
                } else {
                    ForEach(hosts) { host in
                        NavigationLink(host.name ?? "Unnamed Server", destination: ServerDetail(store: store, modelContext: modelContext, hosts: hosts, host: host, isAddNew: false))
                    }
                }
            }

            // Footer
            HStack {
                NavigationLink(destination: ServerDetail(store: store, modelContext: modelContext, hosts: hosts, isAddNew: true)) {
                    Label("Add New", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .padding()

                Spacer()
            }
            .background(Color(.secondarySystemBackground))
        }
        .background(Color(.systemBackground))
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

            NavigationLink(destination: ServerDetail(store: store, modelContext: modelContext, hosts: hosts, isAddNew: true)) {
                Label("Add Your First Server", systemImage: "plus")
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 10)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
#else
// Empty struct for macOS to reference - this won't be compiled on iOS but provides the type
struct iOSServerList: View {
    let modelContext: ModelContext
    let hosts: [Host]
    @ObservedObject var store: AppStore

    init(store: AppStore, modelContext: ModelContext, hosts: [Host]) {
        self.modelContext = modelContext
        self.hosts = hosts
        self.store = store
    }

    var body: some View {
        EmptyView()
    }
}
#endif
