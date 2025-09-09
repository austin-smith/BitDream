//
//  TorrentExtensions.swift
//  BitDream
//
//  Extensions for Torrent action validation
//

import Foundation

// MARK: - Torrent Action Extensions

extension Collection where Element == Torrent {
    /// Whether pause action should be disabled for this collection of torrents
    var shouldDisablePause: Bool {
        return count == 1 && first?.status == TorrentStatus.stopped.rawValue
    }
    
    /// Whether resume actions should be disabled for this collection of torrents
    var shouldDisableResume: Bool {
        return count == 1 && first?.status != TorrentStatus.stopped.rawValue
    }
}

extension Set where Element == Torrent {
    /// Whether pause action should be disabled (includes empty check)
    var shouldDisablePauseAction: Bool {
        return isEmpty || shouldDisablePause
    }
    
    /// Whether resume actions should be disabled (includes empty check)
    var shouldDisableResumeAction: Bool {
        return isEmpty || shouldDisableResume
    }
}
