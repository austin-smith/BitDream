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

struct ServerDetail: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: Store
    var viewContext: NSManagedObjectContext
    var hosts: FetchedResults<Host>
    @State var host: Host?
    var isAddNew: Bool
    
    let keychain = Keychain(service: "crapshack.BitDream")
    
    @State var nameInput: String = ""
    @State var hostInput: String = ""
    @State var portInput: String = ""
    @State var userInput: String = ""
    @State var passInput: String = ""
    @State var isDefault: Bool = false
    @State var isSSL: Bool = false
    
    var body: some View {
        NavigationStack {
            Form {
                HStack {
                    Text("Friendly Name")
                    TextField("friendly name", text: $nameInput)
                        .multilineTextAlignment(.trailing)
                }
                
                Section (footer: Text("Automatically connect to this server on app startup.")) {
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
                            #if os(iOS)
                            .autocapitalization(.none)
                            #endif
                    }
                    
                    HStack {
                        Text("Port")
                        TextField("port", text: $portInput)
                            .multilineTextAlignment(.trailing)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                    }
                    
                    Toggle("Use SSL", isOn: $isSSL)
                        .onAppear {
                            if (store.host == nil) {
                                isDefault = true
                            }
                        }
                }
                
                Section(header: Text("Authentication")) {
                    HStack {
                        Text("Username")
                        TextField("username",text: $userInput)
                            .multilineTextAlignment(.trailing)
                            #if os(iOS)
                            .autocapitalization(.none)
                            #endif
                    }
                    
                    HStack {
                        Text("Password")
                        SecureField("password", text: $passInput)
                            .multilineTextAlignment(.trailing)
                    }
                }
                
                if (!isAddNew) {
                    Button(role: .destructive, action: {
                            viewContext.delete(host!.self)
                            try? viewContext.save()
                            dismiss()
                    }, label: {
                        HStack{
                            Image(systemName: "trash")
                            Text("Delete Server")
                            Spacer()
                        }
                    })
                }
            }
            .onAppear {
                if(!isAddNew) {
                    if let host = host {
                        nameInput = host.name ?? ""
                        isDefault = host.isDefault
                        hostInput = host.server ?? ""
                        portInput = String(host.port)
                        isSSL = host.isSSL
                        userInput = host.username ?? ""
                        passInput = keychain[host.name!] ?? ""
                    }
                }
            }
            #if os(iOS)
            .navigationBarTitle(Text(isAddNew ? "Add Server" : "Edit Server"), displayMode: .inline)
            #else
            .padding()
            .navigationTitle(Text(isAddNew ? "Add Server" : "Edit Server"))
            #endif
            .toolbar {
                if (isAddNew) {
                    ToolbarItem (placement: .automatic) {
                        Button("Save") {
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
                            
                            dismiss()
                        }
                    }
                }
                else {
                    ToolbarItem (placement: .automatic) {
                        Button("Save") {
                            // Save host
                            host!.name = nameInput
                            host!.isDefault = isDefault
                            host!.server = hostInput
                            host!.port = Int16(portInput)!
                            host!.username = userInput
                            host!.isSSL = isSSL
                            
                            // If default is being enabled then ensure to disable it on any current default server
                            if (isDefault) {
                                hosts.forEach { h in
                                    if (h.isDefault && h.id != host!.id) {
                                        h.isDefault.toggle()
                                    }
                                }
                            }
                            
                            try? viewContext.save()
                            
                            // Save password to keychain
                            keychain[nameInput] = passInput
                            
                            dismiss()
                        }
                    }
                }
            }
        }
    }
}
