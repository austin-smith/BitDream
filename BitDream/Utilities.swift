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

public enum sortBy: String, CaseIterable {
    case name = "Name"
    case dateAddedAsc = "Date Added ↑"
    case dateAddedDesc = "Date Added ↓"
    case eta = "Remaining Time ↑"
    case status = "Status"
}

func sortTorrents(_ torrents: [Torrent], sortBy: sortBy) -> [Torrent] {
    // we will always sort by name first
    let sortedList = torrents.sortedAscending(using: .keyPath(\.name))

    switch sortBy {
    case .name:
        return sortedList
    case .dateAddedAsc:
        return sortedList.sortedAscending(using: .keyPath(\.addedDate))
    case .dateAddedDesc:
        return sortedList.sortedDescending(using: .keyPath(\.addedDate))
    case .eta:
        // Simple custom sorting that prioritizes active torrents with valid ETAs
        // and puts completed, paused, and stalled at the bottom
        return sortedList.sorted { a, b in
            // Helper function to get sort priority (lower number = higher priority)
            func getPriority(_ torrent: Torrent) -> Int {
                if torrent.statusCalc == .complete { return 4 }      // Lowest priority
                if torrent.statusCalc == .paused { return 3 }        // Second lowest
                if torrent.statusCalc == .stalled { return 2 }       // Third lowest
                if torrent.eta <= 0 { return 1 }                     // Unknown ETA but active
                return 0                                             // Active with valid ETA
            }
            
            let priorityA = getPriority(a)
            let priorityB = getPriority(b)
            
            // If priorities differ, sort by priority
            if priorityA != priorityB {
                return priorityA < priorityB
            }
            
            // If both are active with valid ETAs, sort by ETA
            if priorityA == 0 && priorityB == 0 {
                return a.eta < b.eta
            }
            
            // Otherwise maintain name-based sort
            return true
        }
    case .status:
        return sortedList.sortedAscending(using: .keyPath(\.statusCalc.rawValue))
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
    let info = makeConfig(store: store)
    getTorrents(config: info.config, auth: info.auth, onReceived: { torrents, err in
        if (err != nil) {
            print("Showing error...")
            DispatchQueue.main.async {
                store.isError.toggle()
                store.debugBrief = "The server gave us this response:"
                store.debugMessage = err!
                store.timer.invalidate()
            }
        } else if (torrents == nil) {
            if (retry > 3) {
                print("Showing error...")
                store.isError.toggle()
                store.debugBrief = "Couldn't reach server."
                store.debugMessage = "We asked the server a few times for a response, \nbut it never got back to us 😔"
            }
            updateList(store: store, update: update, retry: retry + 1)
        } else {
            update(torrents!)
        }
    })
}

/// Updates the list of torrents when called
func updateSessionStats(store: Store, update: @escaping (SessionStats) -> Void, retry: Int = 0) {
    let info = makeConfig(store: store)
    getSessionStats(config: info.config, auth: info.auth, onReceived: { sessions, err in
        if (err != nil) {
            print("Showing error...")
            DispatchQueue.main.async {
                store.isError.toggle()
                store.debugBrief = "The server gave us this response:"
                store.debugMessage = err!
                store.timer.invalidate()
            }
        } else if (sessions == nil) {
            if (retry > 3) {
                print("Showing error...")
                store.isError.toggle()
                store.debugBrief = "Couldn't reach server."
                store.debugMessage = "We asked the server a few times for a response, \nbut it never got back to us 😔"
            }
            updateSessionStats(store: store, update: update, retry: retry + 1)
        } else {
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
    getDefaultDownloadDir(config: info.config, auth: info.auth, onResponse: { downloadDir in
        DispatchQueue.main.async {
            store.objectWillChange.send()
            store.defaultDownloadDir = downloadDir
        }
    })
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
