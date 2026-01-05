#if os(macOS)
import AppKit
import Foundation
import Combine

final class AppFileOpenDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    @Published var pendingOpenFiles: [URL] = []
    var storeProvider: (() -> Store?)?
    private var hostCancellable: AnyCancellable?

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        // Handle both file paths and magnet URLs passed as strings
        if filename.lowercased().hasPrefix("magnet:"), let url = URL(string: filename) {
            enqueue(urls: [url])
        } else {
            enqueue(urls: [URL(fileURLWithPath: filename)])
        }
        return true
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        // Convert any magnet strings to URLs; leave others as file URLs
        let urls: [URL] = filenames.compactMap { name in
            if name.lowercased().hasPrefix("magnet:"), let url = URL(string: name) {
                return url
            }
            return URL(fileURLWithPath: name)
        }
        enqueue(urls: urls)
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
        // Accept either .torrent files or magnet: URLs
        let accepted: [URL] = urls.filter { url in
            if url.isFileURL {
                return url.pathExtension.lowercased() == "torrent"
            }
            return url.scheme?.lowercased() == "magnet"
        }
        guard !accepted.isEmpty else { return }
        if let store = storeProvider?(), store.host != nil {
            process(accepted, with: store)
        } else {
            pendingOpenFiles.append(contentsOf: accepted)
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
            var failures: [(filename: String, message: String)] = []
            for url in urls {
                do {
                    if url.scheme?.lowercased() == "magnet" {
                        let magnetString = url.absoluteString
                        guard Self.isValidMagnet(magnetString) else {
                            throw NSError(domain: "com.bitdream", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid magnet link"])
                        }
                        DispatchQueue.main.async {
                            // Use global queueing to support sequential prompts
                            store.enqueueMagnet(magnetString)
                        }
                    } else {
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
                    }
                } catch {
                    failures.append((filename: url.lastPathComponent, message: error.localizedDescription))
                }
            }

            // Present a single aggregated error dialog if any files failed
            if !failures.isEmpty {
                DispatchQueue.main.async {
                    let count = failures.count
                    if count == 1, let first = failures.first {
                        store.debugBrief = "Failed to open '\(first.filename)'"
                        store.debugMessage = first.message
                    } else {
                        store.debugBrief = "Failed to open \(count) torrent files"
                        let maxListed = 10
                        let listed = failures.prefix(maxListed)
                        let details = listed.map { "- \($0.filename): \($0.message)" }.joined(separator: "\n")
                        let remainder = count - listed.count
                        let suffix = remainder > 0 ? "\n...and \(remainder) more" : ""
                        store.debugMessage = details + suffix
                    }
                    store.isError = true
                }
            }
        }
    }

    // Basic magnet validation per spec: scheme and xt=urn:btih
    private static func isValidMagnet(_ magnet: String) -> Bool {
        guard magnet.count <= 4096 else { return false }
        guard let url = URL(string: magnet), url.scheme?.lowercased() == "magnet" else { return false }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false), let items = components.queryItems else { return false }
        if let xt = items.first(where: { $0.name.lowercased() == "xt" })?.value?.lowercased() {
            return xt.hasPrefix("urn:btih:")
        }
        return false
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
