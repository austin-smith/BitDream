#if os(macOS)
import AppKit
import Combine
import SwiftUI

// AppKit bridge is intentional here.
// A status-item-attached NSMenu matches standard macOS menu bar behavior.
@MainActor
final class MenuBarStatusItemBridge: NSObject, ObservableObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var contentMenuItem: NSMenuItem?
    private var contentHostingView: NSHostingView<AnyView>?
    private weak var store: AppStore?
    private var storeChangeCancellable: AnyCancellable?
    private var pendingRelayoutTask: Task<Void, Never>?
    private var isMenuOpen = false
    private let panelWidth: CGFloat = 380

    func configure(isEnabled: Bool, store: AppStore) {
        if self.store !== store {
            self.store = store
            observeStoreChanges(store)
        } else {
            self.store = store
            if storeChangeCancellable == nil {
                observeStoreChanges(store)
            }
        }

        if isEnabled {
            installStatusItemIfNeeded()
            updateMenuContent()
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
        button.toolTip = "BitDream Torrents"

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self

        item.menu = menu
        statusItem = item
        statusMenu = menu
        installMenuStructureIfNeeded()
    }

    private func tearDownStatusItem() {
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
        statusMenu = nil
        contentMenuItem = nil
        contentHostingView = nil
        storeChangeCancellable = nil
        pendingRelayoutTask?.cancel()
        pendingRelayoutTask = nil
        isMenuOpen = false
    }

    private func installMenuStructureIfNeeded() {
        guard let statusMenu, contentMenuItem == nil else { return }

        let item = NSMenuItem()
        item.isEnabled = true
        statusMenu.addItem(item)
        contentMenuItem = item
    }

    private func updateMenuContent() {
        guard let store else { return }
        installMenuStructureIfNeeded()
        guard let contentMenuItem else { return }

        let rootView = macOSMenuBarTorrentWidget(
            onOpenMainWindow: { [weak self] in
                self?.openMainWindow()
            }
        )
        .environmentObject(store)

        let anyView = AnyView(rootView)
        if let contentHostingView {
            contentHostingView.rootView = anyView
        } else {
            let hostingView = NSHostingView(rootView: anyView)
            contentHostingView = hostingView
            contentMenuItem.view = hostingView
        }
        scheduleMenuRelayout()
    }

    private func sizeContentView() {
        guard let contentHostingView else { return }
        let measuredHeight = max(1, ceil(contentHostingView.fittingSize.height))
        contentHostingView.frame = NSRect(x: 0, y: 0, width: panelWidth, height: measuredHeight)
    }

    func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
        updateMenuContent()
    }

    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
    }

    private func dismissMenu() {
        statusMenu?.cancelTracking()
    }

    private func observeStoreChanges(_ store: AppStore) {
        storeChangeCancellable = store.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.isMenuOpen else { return }
                self.scheduleMenuRelayout()
            }
    }

    private func scheduleMenuRelayout() {
        sizeContentView()
        statusMenu?.update()

        pendingRelayoutTask?.cancel()
        pendingRelayoutTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, self.isMenuOpen else { return }
            self.sizeContentView()
            self.statusMenu?.update()
        }
    }

    private func openMainWindow() {
        dismissMenu()
        revealApplication()

        if let window = NSApp.windows.first(where: { $0.title == "BitDream" }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            _ = NSApp.sendAction(Selector(("showAllWindows:")), to: nil, from: nil)
        }
    }

    private func revealApplication() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.unhide(nil)
    }
}
#endif
