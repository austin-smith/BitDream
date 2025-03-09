//
//  iOSServerDetail.swift
//  BitDream
//
//  Created by Austin Smith on 12/29/22.
//

import Foundation
import SwiftUI
import KeychainAccess
import CoreData

#if os(iOS)
struct iOSServerDetail: View {
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
                            .textInputAutocapitalization(.never)
                    }
                    
                    HStack {
                        Text("Port")
                        TextField("port", text: $portInput)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
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
                            .autocapitalization(.none)
                            // .textInputAutocapitalization(.never)
                    }
                    
                    HStack {
                        Text("Password")
                        SecureField("password", text: $passInput)
                            .multilineTextAlignment(.trailing)
                    }
                }
                
                if (!isAddNew) {
                    Button(role: .destructive, action: {
                        if let host = host {
                            deleteServer(host: host, viewContext: viewContext) {
                                dismiss()
                            }
                        }
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
            }
            .navigationBarTitle(Text(isAddNew ? "Add Server" : "Edit Server"), displayMode: .inline)
            .toolbar {
                if (isAddNew) {
                    ToolbarItem (placement: .automatic) {
                        Button("Save") {
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
                    }
                }
                else {
                    ToolbarItem (placement: .automatic) {
                        Button("Save") {
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
            }
        }
    }
}
#else
// Empty struct for macOS to reference - this won't be compiled on iOS but provides the type
struct iOSServerDetail: View {
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