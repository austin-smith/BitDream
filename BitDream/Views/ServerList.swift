//
//  ServerList.swift
//  BitDream
//
//  Created by Austin Smith on 12/29/22.
//

import SwiftUI
import CoreData
import KeychainAccess

struct ServerList: View {
    @Environment(\.dismiss) private var dismiss
    var viewContext: NSManagedObjectContext
    @ObservedObject var store: Store
    
    @State var selected: Host? = nil
    
    @FetchRequest(
        entity: Host.entity(),
        sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)]
    ) var hosts: FetchedResults<Host>
    
    var body: some View {
        NavigationStack {
            Form {
                List {
                    ForEach(hosts) { host in
                        NavigationLink(host.name!, destination: ServerDetail(store: store, viewContext: viewContext, hosts: hosts, host: host, isAddNew: false))
                    }
                }
            }
            .navigationTitle(Text("Servers"))
#if os(iOS)
            .toolbar{
                ToolbarItem(placement: .navigationBarLeading) {
                    NavigationLink (destination: ServerDetail(store: store, viewContext: viewContext, hosts: hosts, isAddNew: true)) {
                        Text("Add New")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        dismiss()
                    }, label: {
                        Image(systemName: "xmark.circle.fill")
                        
                    })
                    .foregroundColor(Color(UIColor.lightGray))
                }
            }
#elseif os(macOS)
            .toolbar{
                ToolbarItem(placement: .automatic) {
                    NavigationLink (destination: ServerDetail(store: store, viewContext: viewContext, hosts: hosts, isAddNew: true)) {
                        Text("Add New")
                    }
                }
                ToolbarItem(placement: .automatic) {
                    Button(action: {
                        dismiss()
                    }, label: {
                        Image(systemName: "xmark.circle.fill")
                        
                    })
                }
            }
            .frame(minWidth: 600, maxWidth: 600, minHeight: 400, maxHeight: 400)
#endif
        }
    }
}
