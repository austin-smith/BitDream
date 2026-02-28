import AppKit
import SwiftUI

#if os(macOS)
// AppKit bridge is intentional here.
// SwiftUI MenuBarExtra could not satisfy the macOS menu bar requirements.
final class MenuBarStatusItemBridge: NSObject, ObservableObject {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private weak var store: Store?

    func configure(isEnabled: Bool, store: Store) {
        self.store = store

        if isEnabled {
            installStatusItemIfNeeded()
            updatePopoverContent()
        } else {
            tearDownStatusItem()
        }
    }

    private func installStatusItemIfNeeded() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = item.button else { return }

        button.image = NSImage(named: "MenuBarIcon")
        button.image?.isTemplate = true
        button.toolTip = "BitDream Transfers"
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp])

        popover.behavior = .transient
        popover.animates = true

        statusItem = item
    }

    private func tearDownStatusItem() {
        popover.performClose(nil)
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
    }

    private func updatePopoverContent() {
        guard let store else { return }

        let rootView = macOSMenuBarTransferWidget(
            onOpenMainWindow: { [weak self] in
                self?.openMainWindow()
            },
            onOpenSettingsWindow: { [weak self] in
                self?.openSettingsWindow()
            }
        )
        .environmentObject(store)

        popover.contentViewController = NSHostingController(rootView: rootView)
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button else { return }

        if popover.isShown {
            popover.performClose(sender)
            return
        }

        updatePopoverContent()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.becomeKey()
    }

    private func openMainWindow() {
        popover.performClose(nil)
        revealApplication()

        if let window = NSApp.windows.first(where: { $0.title == "BitDream" }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            _ = NSApp.sendAction(Selector(("showAllWindows:")), to: nil, from: nil)
        }
    }

    private func openSettingsWindow() {
        popover.performClose(nil)
        revealApplication()

        if NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) == false {
            _ = NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }

    private func revealApplication() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.unhide(nil)
    }
}
#endif
