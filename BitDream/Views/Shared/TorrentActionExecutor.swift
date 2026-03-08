import Foundation

@MainActor
func reAnnounceToTrackers(
    torrent: Torrent,
    store: TransmissionStore,
    onResponse: @MainActor @escaping (TransmissionResponse) -> Void = { _ in }
) {
    let info = makeConfig(store: store)
    reAnnounceTorrent(torrent: torrent, config: info.config, auth: info.auth, onResponse: onResponse)
}

@MainActor
func resumeTorrentNow(
    torrent: Torrent,
    store: TransmissionStore,
    onResponse: @MainActor @escaping (TransmissionResponse) -> Void = { _ in }
) {
    let info = makeConfig(store: store)
    startTorrentNow(torrent: torrent, config: info.config, auth: info.auth, onResponse: onResponse)
}

enum TorrentQueueMoveDirection {
    case top
    case upward
    case downward
    case bottom
}

enum TorrentActionExecutor {
    @MainActor
    static func pause(ids: [Int], store: TransmissionStore, onError: @escaping (String) -> Void) {
        perform(ids: ids, store: store, onError: onError) { ids, info, onResponse in
            pauseTorrents(ids: ids, info: info, onResponse: onResponse)
        }
    }

    @MainActor
    static func resume(ids: [Int], store: TransmissionStore, onError: @escaping (String) -> Void) {
        perform(ids: ids, store: store, onError: onError) { ids, info, onResponse in
            resumeTorrents(ids: ids, info: info, onResponse: onResponse)
        }
    }

    @MainActor
    static func setAllPlayback(start: Bool, store: TransmissionStore, onError: @escaping (String) -> Void) {
        guard !store.torrents.isEmpty else { return }

        let info = makeConfig(store: store)
        playPauseAllTorrents(start: start, info: info) { response in
            handleResponse(response, onError: onError)
        }
    }

    @MainActor
    static func resumeNow(torrents: [Torrent], store: TransmissionStore, onError: @escaping (String) -> Void) {
        perform(torrents: torrents, store: store, onError: onError) { torrent, store, onResponse in
            resumeTorrentNow(torrent: torrent, store: store, onResponse: onResponse)
        }
    }

    @MainActor
    static func reannounce(torrents: [Torrent], store: TransmissionStore, onError: @escaping (String) -> Void) {
        perform(torrents: torrents, store: store, onError: onError) { torrent, store, onResponse in
            reAnnounceToTrackers(torrent: torrent, store: store, onResponse: onResponse)
        }
    }

    @MainActor
    static func verify(torrents: [Torrent], store: TransmissionStore, onError: @escaping (String) -> Void) {
        guard !torrents.isEmpty else { return }

        let info = makeConfig(store: store)
        for torrent in torrents {
            verifyTorrent(torrent: torrent, config: info.config, auth: info.auth) { response in
                handleResponse(response, onError: onError)
            }
        }
    }

    @MainActor
    static func moveInQueue(
        _ direction: TorrentQueueMoveDirection,
        ids: [Int],
        store: TransmissionStore,
        onError: @escaping (String) -> Void
    ) {
        guard !ids.isEmpty else { return }

        let info = makeConfig(store: store)
        switch direction {
        case .top:
            queueMoveTop(ids: ids, info: info) { response in
                handleResponse(response, onError: onError)
            }
        case .upward:
            queueMoveUp(ids: ids, info: info) { response in
                handleResponse(response, onError: onError)
            }
        case .downward:
            queueMoveDown(ids: ids, info: info) { response in
                handleResponse(response, onError: onError)
            }
        case .bottom:
            queueMoveBottom(ids: ids, info: info) { response in
                handleResponse(response, onError: onError)
            }
        }
    }

    @MainActor
    private static func perform(
        ids: [Int],
        store: TransmissionStore,
        onError: @escaping (String) -> Void,
        action: (_ ids: [Int], _ info: (config: TransmissionConfig, auth: TransmissionAuth), _ onResponse: @MainActor @escaping (TransmissionResponse) -> Void) -> Void
    ) {
        guard !ids.isEmpty else { return }

        let info = makeConfig(store: store)
        action(ids, info) { response in
            handleResponse(response, onError: onError)
        }
    }

    @MainActor
    private static func perform(
        torrents: [Torrent],
        store: TransmissionStore,
        onError: @escaping (String) -> Void,
        action: (_ torrent: Torrent, _ store: TransmissionStore, _ onResponse: @MainActor @escaping (TransmissionResponse) -> Void) -> Void
    ) {
        guard !torrents.isEmpty else { return }

        for torrent in torrents {
            action(torrent, store) { response in
                handleResponse(response, onError: onError)
            }
        }
    }

    private static func handleResponse(_ response: TransmissionResponse, onError: @escaping (String) -> Void) {
        handleTransmissionResponse(response, onSuccess: {}, onError: onError)
    }
}
