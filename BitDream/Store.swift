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
    
    @Published var isError: Bool = false
    @Published var debugBrief: String = ""
    @Published var debugMessage: String = ""
    
    var timer: Timer = Timer()
    
    public func setHost(host: Host) {
        var config = TransmissionConfig()
        config.host = host.server
        config.port = Int(host.port)
        config.scheme = host.isSSL ? "https" : "http"
        
        let auth = TransmissionAuth(username: host.username!, password: readPassword(name: host.name!))
        self.server = Server(config: config, auth: auth)
        self.host = host
        
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
        self.timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true, block: { _ in
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
}
