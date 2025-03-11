//
//  BitDreamApp.swift
//  BitDream
//
//  Created by Austin Smith on 12/29/22.
//

import SwiftUI
import UserNotifications
import CoreData
// Import Store from the main module
import Foundation

@main
struct BitDreamApp: App {
    let persistenceController = PersistenceController.shared
    
    init() {
        // Register default values for view state
        UserDefaults.standard.register(defaults: [
            "sidebarVisibility": true, // true = show sidebar (.all), false = hide sidebar (.detailOnly)
            "inspectorVisibility": true,
            "sortBySelection": "name" // Default sort by name
        ])
        
        // Request permission to use badges on macOS
        #if os(macOS)
        UNUserNotificationCenter.current().requestAuthorization(options: [.badge]) { granted, error in
            if let error = error {
                print("Error requesting notification authorization: \(error)")
            }
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
