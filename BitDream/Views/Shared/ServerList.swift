//
//  ServerList.swift
//  BitDream
//
//  Created by Austin Smith on 12/29/22.
//

import SwiftUI
import CoreData
import KeychainAccess

/// Platform-agnostic wrapper for ServerList view
/// This view simply delegates to the appropriate platform-specific implementation
struct ServerList: View {
    @ObservedObject var store: Store
    var viewContext: NSManagedObjectContext
    
    var body: some View {
        // Use NavigationStack for iOS to handle navigation properly
        // This ensures the navigation context is established at this level
        #if os(iOS)
        NavigationStack {
            iOSServerList(
                viewContext: viewContext,
                store: store
            )
        }
        #else
        // No navigation container needed for macOS
        macOSServerList(
            viewContext: viewContext,
            store: store
        )
        #endif
        // Ensure no toolbar modifiers are applied at this level
    }
}

// MARK: - Shared Helper Functions

/// Deletes a server from Core Data and handles disconnection if needed
func deleteServer(
    host: Host,
    store: Store,
    hosts: FetchedResults<Host>,
    viewContext: NSManagedObjectContext,
    completion: @escaping () -> Void
) {
    // If deleting the connected server, disconnect first
    let currentStore = store // Create a local reference to avoid wrapper issues
    if host == currentStore.host {
        // Find another server to connect to
        let otherServers = hosts.filter { $0 != host }
        if let newServer = otherServers.first {
            // Set the new server as the current host
            currentStore.host = newServer
            // Save the change to UserDefaults
            UserDefaults.standard.set(newServer.objectID.uriRepresentation().absoluteString, forKey: "selectedHost")
        } else {
            // If no other servers, set host to nil
            // Clear the current host
            currentStore.host = nil
            // Remove from UserDefaults
            UserDefaults.standard.removeObject(forKey: "selectedHost")
            
            // Reset any state that might cause crashes when no server is connected
            currentStore.torrents = []
            currentStore.sessionStats = nil
            
            // Stop any background refresh operations that might try to access the host
            currentStore.timer.invalidate()
        }
    }
    
    // Delete the server
    viewContext.delete(host)
    try? viewContext.save()
    completion()
}

/// Creates a confirmation message for server deletion
@ViewBuilder
func deleteConfirmationMessage(for host: Host, store: Store) -> some View {
    let currentStore = store // Create a local reference to avoid wrapper issues
    VStack(alignment: .leading, spacing: 8) {
        Text("Are you sure you want to delete \(host.name ?? "Unnamed Server")?")
        
        if host == currentStore.host {
            Text("This is your currently connected server. You will be disconnected and connected to another server if available.")
                .font(.caption)
                .foregroundColor(.orange)
        }
        
        Text("This action cannot be undone.")
            .font(.caption2)
            .foregroundColor(.secondary)
    }
}

// MARK: - Shared UI Components

/// Button style for hover effects
struct HoverButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverButton(configuration: configuration)
    }

    struct HoverButton: View {
        let configuration: Configuration
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .padding(6)
                .background(isHovered ? Color.gray.opacity(0.2) : Color.clear)
                .cornerRadius(6)
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isHovered = hovering
                    }
                }
        }
    }
}
