//
//  ServerDetail.swift
//  BitDream
//
//  Created by Austin Smith on 12/29/22.
//

import Foundation
import SwiftUI
import KeychainAccess
import CoreData

/// Platform-agnostic wrapper for ServerDetail view
/// This view simply delegates to the appropriate platform-specific implementation
struct ServerDetail: View {
    @ObservedObject var store: Store
    var viewContext: NSManagedObjectContext
    var hosts: FetchedResults<Host>
    @State var host: Host?
    var isAddNew: Bool
    
    var body: some View {
        #if os(iOS)
        iOSServerDetail(
            store: store,
            viewContext: viewContext,
            hosts: hosts,
            host: host,
            isAddNew: isAddNew
        )
        #else
        macOSServerDetail(
            store: store,
            viewContext: viewContext,
            hosts: hosts,
            host: host,
            isAddNew: isAddNew
        )
        #endif
    }
}

// MARK: - Shared Helper Functions

/// Saves a new server to Core Data and Keychain
func saveNewServer(
    nameInput: String,
    hostInput: String,
    portInput: String,
    userInput: String,
    passInput: String,
    isDefault: Bool,
    isSSL: Bool,
    viewContext: NSManagedObjectContext,
    store: Store,
    keychain: Keychain,
    completion: @escaping () -> Void
) {
    // Save host
    let newHost = Host(context: viewContext)
    newHost.name = nameInput
    newHost.server = hostInput
    newHost.port = Int16(portInput)!
    newHost.username = userInput
    newHost.isDefault = isDefault
    newHost.isSSL = isSSL
    
    try? viewContext.save()
    
    // Save password to keychain
    keychain[nameInput] = passInput
    
    // if there is no host currently set, then set it to the one being created
    if (store.host == nil) {
        store.setHost(host: newHost)
    }
    
    completion()
}

/// Updates an existing server in Core Data and Keychain
func updateExistingServer(
    host: Host,
    nameInput: String,
    hostInput: String,
    portInput: String,
    userInput: String,
    passInput: String,
    isDefault: Bool,
    isSSL: Bool,
    viewContext: NSManagedObjectContext,
    hosts: FetchedResults<Host>,
    keychain: Keychain,
    completion: @escaping () -> Void
) {
    // Save host
    host.name = nameInput
    host.isDefault = isDefault
    host.server = hostInput
    host.port = Int16(portInput)!
    host.username = userInput
    host.isSSL = isSSL
    
    // If default is being enabled then ensure to disable it on any current default server
    if (isDefault) {
        hosts.forEach { h in
            if (h.isDefault && h.id != host.id) {
                h.isDefault.toggle()
            }
        }
    }
    
    try? viewContext.save()
    
    // Save password to keychain
    keychain[nameInput] = passInput
    
    completion()
}

/// Loads server data into state variables
func loadServerData(
    host: Host,
    keychain: Keychain,
    onLoad: @escaping (String, Bool, String, String, Bool, String, String) -> Void
) {
    let nameInput = host.name ?? ""
    let isDefault = host.isDefault
    let hostInput = host.server ?? ""
    let portInput = String(host.port)
    let isSSL = host.isSSL
    let userInput = host.username ?? ""
    let passInput = keychain[host.name!] ?? ""
    
    onLoad(nameInput, isDefault, hostInput, portInput, isSSL, userInput, passInput)
}

/// Deletes a server from Core Data
func deleteServer(
    host: Host,
    viewContext: NSManagedObjectContext,
    completion: @escaping () -> Void
) {
    viewContext.delete(host)
    try? viewContext.save()
    completion()
}
