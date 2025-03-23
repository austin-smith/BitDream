//
//  Store.swift
//  BitDream
//
//  Created by Austin Smith on 12/29/22.
//

import SwiftUI
import Foundation
import KeychainAccess

struct Server {
    var config: TransmissionConfig
    var auth: TransmissionAuth
}

class Store: NSObject, ObservableObject {
    @Published var torrents: [Torrent] = []
    @Published var sessionStats: SessionStats?
    @Published var setup: Bool = false
    @Published var server: Server?
    @Published var host: Host?

    @Published var defaultDownloadDir: String = ""
    
    @Published var isShowingAddAlert: Bool = false
    @Published var isShowingServerAlert: Bool = false
    @Published var editServers: Bool = false
    @Published var showSettings: Bool = false
    
    @Published var isError: Bool = false
    @Published var debugBrief: String = ""
    @Published var debugMessage: String = ""
    
    @Published var pollInterval: Double = 5.0 // Default poll interval in seconds
    
    var timer: Timer = Timer()
    
    override init() {
        super.init()
    }
    
    public func setHost(host: Host) {
        var config = TransmissionConfig()
        config.host = host.server
        config.port = Int(host.port)
        config.scheme = host.isSSL ? "https" : "http"
        
        let auth = TransmissionAuth(username: host.username!, password: readPassword(name: host.name!))
        self.server = Server(config: config, auth: auth)
        self.host = host
        
        // Get server version and download directory
        getSession(config: config, auth: auth) { sessionInfo in
            DispatchQueue.main.async {
                self.defaultDownloadDir = sessionInfo.downloadDir
                
                // Store the version in CoreData
                host.version = sessionInfo.version
                try? PersistenceController.shared.container.viewContext.save()
            }
        }
        
        // Clear torrents before refreshing to ensure list resets to top
        self.torrents = []
        
        // refresh data immediately after setting new host
        refreshTransmissionData(store: self)
        
        // begin auto-refresh of data
        startTimer()
    }
    
    func readPassword(name: String) -> String {
        let keychain = Keychain(service: "crapshack.BitDream")
        if let password = keychain[name] {
            return password
        }
        else {
            return "Whoopsie!"
        }
    }
    
    func startTimer() {
        self.timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true, block: { _ in
            DispatchQueue.main.async {
                updateList(store: self, update: { vals in
                    DispatchQueue.main.async {
                        self.objectWillChange.send()
                        self.torrents = vals
                    }
                })
                updateSessionStats(store: self, update: { vals in
                    DispatchQueue.main.async {
                        self.objectWillChange.send()
                        self.sessionStats = vals
                    }
                })
            }
        })
    }
    
    // Add a method to update the poll interval and restart the timer
    func updatePollInterval(_ newInterval: Double) {
        // Ensure the interval is at least 1 second
        pollInterval = max(1.0, newInterval)
        
        // Stop the current timer
        timer.invalidate()
        
        // Start a new timer with the updated interval
        startTimer()
    }
}
