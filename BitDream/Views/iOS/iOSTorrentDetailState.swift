import SwiftUI

#if os(iOS)
/// Owned by the workspace, not a particular compact/expanded presentation.
@MainActor @Observable
final class iOSTorrentDetailState {
    let supplementalStore = TorrentDetailSupplementalStore()
    let files = iOSTorrentFileState()
    var peerSearchText = ""
    var showingDeleteConfirmation = false
    var labelDialog = false
    var labelInput = ""
    var renameDialog = false
    var renameInput = ""
    var moveDialog = false
    var movePath = ""
    var moveShouldMove = true
    var showingError = false
    var errorMessage = ""
}

@MainActor @Observable
final class iOSTorrentFileState {
    var mutableFileStats: [TorrentFileStats] = []
    var searchText = ""
    var sortProperty: FileSortProperty = .name
    var sortOrder: SortOrder = .ascending
    var showWantedFiles = true
    var showSkippedFiles = true
    var showCompleteFiles = true
    var showIncompleteFiles = true
    var showVideos = true
    var showAudio = true
    var showImages = true
    var showDocuments = true
    var showArchives = true
    var showOther = true
    var showFilterSheet = false
    var editMode: EditMode = .inactive
    var selectedFileIds: Set<String> = []
    var showingError = false
    var errorMessage = ""
}
#endif
