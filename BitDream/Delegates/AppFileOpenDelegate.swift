#if os(macOS)
import AppKit
import Foundation
import Combine

final class AppFileOpenDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    @Published var pendingOpenFiles: [URL] = []
    var storeProvider: (() -> Store?)?
    private var hostCancellable: AnyCancellable?

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        enqueue(urls: [URL(fileURLWithPath: filename)])
        return true
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        enqueue(urls: filenames.map { URL(fileURLWithPath: $0) })
        sender.reply(toOpenOrPrint: .success)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        enqueue(urls: urls)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        flushIfPossible()
    }
    
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        return false
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        return flag
    }
    
    func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
        return false
    }

    private func enqueue(urls: [URL]) {
        let torrents = urls.filter { $0.pathExtension.lowercased() == "torrent" }
        guard !torrents.isEmpty else { return }
        if let store = storeProvider?(), store.host != nil {
            process(torrents, with: store)
        } else {
            pendingOpenFiles.append(contentsOf: torrents)
        }
    }

    private func flushIfPossible() {
        guard !pendingOpenFiles.isEmpty, let store = storeProvider?(), store.host != nil else { return }
        process(pendingOpenFiles, with: store)
        pendingOpenFiles.removeAll()
    }

    private func process(_ urls: [URL], with store: Store) {
        // Process files on background queue to avoid UI blocking
        DispatchQueue.global(qos: .userInitiated).async {
            for url in urls {
                do {
                    var didAccess = false
                    if url.isFileURL {
                        didAccess = url.startAccessingSecurityScopedResource()
                    }
                    defer {
                        if didAccess { url.stopAccessingSecurityScopedResource() }
                    }
                    let data = try Data(contentsOf: url)
                    
                    // Switch back to main queue for the actual add operation
                    DispatchQueue.main.async {
                        addTorrentFromFileData(data, store: store)
                    }
                } catch {
                    print("Failed to read torrent file \(url.lastPathComponent): \(error)")
                }
            }
        }
    }

    func configure(with store: Store) {
        self.storeProvider = { store }
        hostCancellable = store.$host.sink { [weak self] _ in
            self?.flushIfPossible()
        }
        flushIfPossible()
    }

    func notifyStoreAvailable() {
        flushIfPossible()
    }
}
#endif


