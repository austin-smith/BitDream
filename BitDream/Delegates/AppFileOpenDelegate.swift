#if os(macOS)
import AppKit
import Foundation
import Combine

@MainActor
final class AppFileOpenDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    @Published var pendingOpenFiles: [URL] = []
    var storeProvider: (() -> Store?)?
    private var hostCancellable: AnyCancellable?
    private var isProcessingOpenFiles = false
    
    private struct OpenFailure: Sendable {
        let filename: String
        let message: String
    }

    private enum OpenAction: Sendable {
        case magnet(String)
        case torrentData(Data)
    }

    private struct OpenBatchResult: Sendable {
        let actions: [OpenAction]
        let failures: [OpenFailure]
    }

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
        pendingOpenFiles.append(contentsOf: accepted)
        flushIfPossible()
    }

    private func flushIfPossible() {
        guard !isProcessingOpenFiles else { return }
        guard !pendingOpenFiles.isEmpty, let store = storeProvider?(), store.host != nil else { return }

        let batch = pendingOpenFiles
        pendingOpenFiles.removeAll()
        isProcessingOpenFiles = true

        Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await Self.prepareOpenBatch(from: batch)
            apply(result, to: store)
            isProcessingOpenFiles = false
            flushIfPossible()
        }
    }

    @MainActor
    private func apply(_ result: OpenBatchResult, to store: Store) {
        for action in result.actions {
            switch action {
            case .magnet(let magnetString):
                store.enqueueMagnet(magnetString)
            case .torrentData(let data):
                addTorrentFromFileData(data, store: store)
            }
        }

        guard !result.failures.isEmpty else { return }

        let count = result.failures.count
        if count == 1, let first = result.failures.first {
            store.debugBrief = "Failed to open '\(first.filename)'"
            store.debugMessage = first.message
        } else {
            store.debugBrief = "Failed to open \(count) torrent files"
            let maxListed = 10
            let listed = result.failures.prefix(maxListed)
            let details = listed.map { "- \($0.filename): \($0.message)" }.joined(separator: "\n")
            let remainder = count - listed.count
            let suffix = remainder > 0 ? "\n...and \(remainder) more" : ""
            store.debugMessage = details + suffix
        }
        store.isError = true
    }

    private nonisolated static func prepareOpenBatch(from urls: [URL]) async -> OpenBatchResult {
        await Task(priority: .userInitiated) {
            var actions: [OpenAction] = []
            var failures: [OpenFailure] = []

            for url in urls {
                do {
                    if url.scheme?.lowercased() == "magnet" {
                        let magnetString = url.absoluteString
                        guard isValidMagnet(magnetString) else {
                            throw NSError(domain: "com.bitdream", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid magnet link"])
                        }
                        actions.append(.magnet(magnetString))
                    } else {
                        var didAccess = false
                        if url.isFileURL {
                            didAccess = url.startAccessingSecurityScopedResource()
                        }
                        defer {
                            if didAccess { url.stopAccessingSecurityScopedResource() }
                        }
                        let data = try Data(contentsOf: url)
                        actions.append(.torrentData(data))
                    }
                } catch {
                    failures.append(OpenFailure(filename: failureLabel(for: url), message: error.localizedDescription))
                }
            }

            return OpenBatchResult(actions: actions, failures: failures)
        }.value
    }

    private nonisolated static func failureLabel(for url: URL) -> String {
        if url.isFileURL {
            return url.lastPathComponent
        }
        let magnet = url.absoluteString
        return magnet.isEmpty ? "magnet link" : magnet
    }

    // Basic magnet validation per spec: scheme and xt=urn:btih
    private nonisolated static func isValidMagnet(_ magnet: String) -> Bool {
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
