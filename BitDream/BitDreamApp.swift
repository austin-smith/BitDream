//
//  BitDreamApp.swift
//  BitDream
//
//  Created by Austin Smith on 12/29/22.
//

import SwiftUI

@main
struct BitDreamApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
