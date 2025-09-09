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
import Combine

@main
struct BitDreamApp: App {
    let persistenceController = PersistenceController.shared
    
    // Create a shared store instance that will be used by both the main app and settings
    @StateObject private var store = Store()
    @StateObject private var themeManager = ThemeManager.shared
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppFileOpenDelegate.self) private var appFileOpenDelegate
    #endif
    
    // HUD state for macOS appearance toggle feedback
    @State private var showAppearanceHUD: Bool = false
    @State private var appearanceHUDText: String = ""
    @State private var hideHUDWork: DispatchWorkItem?
    
    init() {
        // Register default values for view state
        UserDefaults.registerViewStateDefaults()
        
        // Register additional defaults
        UserDefaults.standard.register(defaults: [
            "sortBySelection": "nameAsc", // Default sort by name ascending
            "themeModeKey": ThemeMode.system.rawValue // Default theme mode
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
        #if os(macOS)
        Window("BitDream", id: "main") {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(store) // Pass the shared store to the ContentView
                .accentColor(themeManager.accentColor) // Apply the accent color to the entire app
                .environmentObject(themeManager) // Pass the ThemeManager to all views
                .immediateTheme(manager: themeManager)
                .onAppear {
                    // Bind delegate to Store and auto-flush when host becomes available
                    appFileOpenDelegate.configure(with: store)
                }
                .overlay(alignment: .center) {
                    if showAppearanceHUD {
                        AppearanceHUDView(text: appearanceHUDText)
                            .allowsHitTesting(false)
                    }
                }
                .animation(.easeOut(duration: 0.25), value: showAppearanceHUD)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(after: .sidebar) {
                Menu("Appearance") {
                    Picker("Appearance", selection: $themeManager.themeMode) {
                        Text("System").tag(ThemeMode.system)
                        Text("Light").tag(ThemeMode.light)
                        Text("Dark").tag(ThemeMode.dark)
                    }
                    .pickerStyle(.inline)
                    
                    Divider()
                    
                    Button("Toggle Appearance") {
                        themeManager.cycleThemeMode()
                        appearanceHUDText = "Appearance: \(themeManager.themeMode.rawValue)"
                        hideHUDWork?.cancel()
                        showAppearanceHUD = true
                        let work = DispatchWorkItem {
                            showAppearanceHUD = false
                        }
                        hideHUDWork = work
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: work)
                    }
                    .keyboardShortcut("j", modifiers: .command)
                }
            }
        }
        #else
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(store) // Pass the shared store to the ContentView
                .accentColor(themeManager.accentColor) // Apply the accent color to the entire app
                .environmentObject(themeManager) // Pass the ThemeManager to all views
                .immediateTheme(manager: themeManager)
        }
        #endif
        
        #if os(macOS)
        Settings {
            SettingsView(store: store) // Use the same store instance
                .frame(minWidth: 500, idealWidth: 550, maxWidth: 650, minHeight: 300, idealHeight: 350, maxHeight: 450)
                .environmentObject(themeManager) // Pass the ThemeManager to the Settings view
                .immediateTheme(manager: themeManager)
        }
        #endif
    }
}

#if os(macOS)
private struct AppearanceHUDView: View {
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "circle.lefthalf.filled")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        )
    }
}
#endif
