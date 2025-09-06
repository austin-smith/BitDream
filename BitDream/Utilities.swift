//
//  Utilities.swift
//  BitDream
//
//  Created by Austin Smith on 12/29/22.
//

import Foundation
import SwiftUI
import CoreData
import KeychainAccess

/*--------------------------------------------------------------------------------------------
 Sorting stuff
 -------------------------------------------------------------------------------------------*/

struct SortDescriptor<Value> {
    var comparator: (Value, Value) -> ComparisonResult
}

extension SortDescriptor {
    static func keyPath<T: Comparable>(_ keyPath: KeyPath<Value, T>) -> Self {
        Self { rootA, rootB in
            let valueA = rootA[keyPath: keyPath]
            let valueB = rootB[keyPath: keyPath]

            guard valueA != valueB else {
                return .orderedSame
            }

            return valueA < valueB ? .orderedAscending : .orderedDescending
        }
    }
}

enum SortOrder {
    case ascending
    case descending
}

extension Sequence {
    func sorted(using descriptors: [SortDescriptor<Element>],
                order: SortOrder) -> [Element] {
        sorted { valueA, valueB in
            for descriptor in descriptors {
                let result = descriptor.comparator(valueA, valueB)

                switch result {
                case .orderedSame:
                    // Keep iterating if the two elements are equal,
                    // since that'll let the next descriptor determine
                    // the sort order:
                    break
                case .orderedAscending:
                    return order == .ascending
                case .orderedDescending:
                    return order == .descending
                }
            }

            // If no descriptor was able to determine the sort
            // order, we'll default to false (similar to when
            // using the '<' operator with the built-in API):
            return false
        }
    }
}


extension Sequence {
    func sortedAscending(using descriptors: SortDescriptor<Element>...) -> [Element] {
        sorted(using: descriptors, order: .ascending)
    }
}

extension Sequence {
    func sortedDescending(using descriptors: SortDescriptor<Element>...) -> [Element] {
        sorted(using: descriptors, order: .descending)
    }
}

public enum SortProperty: String, CaseIterable {
    case name = "Name"
    case dateAdded = "Date Added"
    case status = "Status"
    case eta = "Remaining Time"
}

func sortTorrents(_ torrents: [Torrent], by property: SortProperty, order: SortOrder) -> [Torrent] {
    let sortedList = torrents.sortedAscending(using: .keyPath(\.name))
    switch property {
    case .name:
        return order == .ascending ? torrents.sortedAscending(using: .keyPath(\.name)) : torrents.sortedDescending(using: .keyPath(\.name))
    case .dateAdded:
        return order == .ascending ? sortedList.sortedAscending(using: .keyPath(\.addedDate)) : sortedList.sortedDescending(using: .keyPath(\.addedDate))
    case .status:
        return order == .ascending ? sortedList.sortedAscending(using: .keyPath(\.statusCalc.rawValue)) : sortedList.sortedDescending(using: .keyPath(\.statusCalc.rawValue))
    case .eta:
        let ascending = (order == .ascending)
        return sortedList.sorted { a, b in
            func getPriority(_ torrent: Torrent) -> Int {
                if torrent.statusCalc == .complete { return 5 }
                if torrent.statusCalc == .seeding { return 4 }
                if torrent.statusCalc == .paused { return 3 }
                if torrent.statusCalc == .stalled { return 2 }
                if torrent.eta <= 0 { return 1 }
                return 0
            }
            let priorityA = getPriority(a)
            let priorityB = getPriority(b)
            if priorityA != priorityB {
                return ascending ? (priorityA < priorityB) : (priorityA > priorityB)
            }
            return ascending ? (a.eta < b.eta) : (a.eta > b.eta)
        }
    }
}

/*--------------------------------------------------------------------------------------------
 Formatting stuff
 -------------------------------------------------------------------------------------------*/

public let byteCountFormatter: ByteCountFormatter = {
    var formatter = ByteCountFormatter()
    formatter.allowsNonnumericFormatting = false // Uses '0' instead of 'Zero'
    formatter.countStyle = .file
    formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
    
    return formatter
}()

/*--------------------------------------------------------------------------------------------
 Colors
 -------------------------------------------------------------------------------------------*/

// extension Color {
//     static let primary = Color("AccemtColor")
//     static let secondary = Color("SecondaryColor")
//     static let third = Color("ThirdColor")
// }

/*--------------------------------------------------------------------------------------------
 Refresh transmission data functions
 -------------------------------------------------------------------------------------------*/

/// Updates the list of torrents when called
func updateList(store: Store, update: @escaping ([Torrent]) -> Void, retry: Int = 0) {
    // Skip connection attempts if user is actively editing server settings
    if store.isEditingServerSettings {
        return
    }
    
    let info = makeConfig(store: store)
    getTorrents(config: info.config, auth: info.auth, onReceived: { torrents, err in
        if (err != nil) {
            print("Connection error...")
            store.handleConnectionError(message: err!)
        } else if (torrents == nil) {
            if (retry > 3) {
                print("Connection error after retries...")
                store.handleConnectionError(message: "Could not reach server after multiple attempts. Please check your connection.")
            } else {
                updateList(store: store, update: update, retry: retry + 1)
            }
        } else {
            // Clear connection error state on successful response
            DispatchQueue.main.async {
                // If we were in an error state before, this means we've successfully reconnected
                let wasInErrorState = store.connectionError
                
                // Clear error state
                store.connectionError = false
                store.connectionErrorMessage = ""
                
                // Auto-dismiss the alert when connection is restored
                if wasInErrorState {
                    store.showConnectionErrorAlert = false
                }
            }
            update(torrents!)
        }
    })
}

/// Updates the list of torrents when called
func updateSessionStats(store: Store, update: @escaping (SessionStats) -> Void, retry: Int = 0) {
    // Skip connection attempts if user is actively editing server settings
    if store.isEditingServerSettings {
        return
    }
    
    let info = makeConfig(store: store)
    getSessionStats(config: info.config, auth: info.auth, onReceived: { sessions, err in
        if (err != nil) {
            print("Connection error...")
            store.handleConnectionError(message: err!)
        } else if (sessions == nil) {
            if (retry > 3) {
                print("Connection error after retries...")
                store.handleConnectionError(message: "Could not reach server after multiple attempts. Please check your connection.")
            } else {
                updateSessionStats(store: store, update: update, retry: retry + 1)
            }
        } else {
            // Clear connection error state on successful response
            DispatchQueue.main.async {
                // If we were in an error state before, this means we've successfully reconnected
                let wasInErrorState = store.connectionError
                
                // Clear error state
                store.connectionError = false
                store.connectionErrorMessage = ""
                
                // Auto-dismiss the alert when connection is restored
                if wasInErrorState {
                    store.showConnectionErrorAlert = false
                }
            }
            update(sessions!)
        }
    })
}

// updates all Transmission data based on current host
func refreshTransmissionData(store: Store) {
    // update the list of torrents when new host is set
    updateList(store: store, update: { vals in
        DispatchQueue.main.async {
            store.objectWillChange.send()
            store.torrents = vals
        }
    })
    
    updateSessionStats(store: store, update: { vals in
        DispatchQueue.main.async {
            store.objectWillChange.send()
            store.sessionStats = vals
        }
    })
    
    let info = makeConfig(store: store)
    // also reset default download directory when new host is set
    getSession(config: info.config, auth: info.auth) { sessionInfo in
        DispatchQueue.main.async {
            store.objectWillChange.send()
            store.defaultDownloadDir = sessionInfo.downloadDir
            
            // Update version in CoreData
            if let host = store.host {
                host.version = sessionInfo.version
                try? PersistenceController.shared.container.viewContext.save()
            }
        }
    }
}

/*--------------------------------------------------------------------------------------------
 More functions
 -------------------------------------------------------------------------------------------*/

/// Function for generating config and auth for API calls
/// - Parameter store: The current `Store` containing session information needed for creating the config.
/// - Returns a tuple containing the requested `config` and `auth`
func makeConfig(store: Store) -> (config: TransmissionConfig, auth: TransmissionAuth) {
    // Send the file to the server
    var config = TransmissionConfig()
    config.host = store.host?.server
    config.port = Int(store.host!.port)
    config.scheme = store.host!.isSSL ? "https" : "http"
    let keychain = Keychain(service: "crapshack.BitDream")
    var auth: TransmissionAuth
    
    if let password = keychain[store.host!.name!] {
        auth = TransmissionAuth(username: store.host!.username!, password: password)
    }
    else {
        auth = TransmissionAuth(username: store.host!.username!, password: "")
    }

    return (config: config, auth: auth)
}
