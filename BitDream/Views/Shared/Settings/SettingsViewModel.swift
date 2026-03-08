import Foundation
import SwiftUI

@MainActor
protocol SessionSettingsServing: AnyObject {
    var host: Host? { get }
    var settingsConnectionGeneration: UUID { get }
    var sessionConfiguration: TransmissionSessionResponseArguments? { get }

    func applySessionSettings(_ args: TransmissionSessionSetRequestArgs) async throws -> TransmissionSessionResponseArguments
    func checkFreeSpace(path: String) async throws -> FreeSpaceResponse
    func testPort(ipProtocol: String?) async throws -> PortTestResponse
    func updateBlocklist() async throws -> BlocklistUpdateResponse
}

extension TransmissionStore: SessionSettingsServing {}

enum SessionSettingsSaveState: Equatable {
    case idle
    case pending
    case saving
    case failed(TransmissionErrorPresentation)
}

struct SessionFreeSpaceSummary: Equatable {
    let freeSpace: String
    let totalSpace: String
    let percentUsed: String

    var message: String {
        "Free: \(freeSpace) of \(totalSpace) (\(percentUsed) used)"
    }
}

enum SessionFreeSpaceState: Equatable {
    case idle
    case checking(previous: SessionFreeSpaceSummary?)
    case result(SessionFreeSpaceSummary)
    case failed(TransmissionErrorPresentation)
}

enum SessionPortTestOutcome: Equatable {
    case open(protocolName: String)
    case closed(protocolName: String)
    case checkerUnavailable

    var message: String {
        switch self {
        case .open(let protocolName):
            return "Port is open (\(protocolName))"
        case .closed(let protocolName):
            return "Port is closed (\(protocolName))"
        case .checkerUnavailable:
            return "Port check site is down"
        }
    }

    var color: Color {
        switch self {
        case .open:
            return .green
        case .closed, .checkerUnavailable:
            return .orange
        }
    }
}

enum SessionPortTestState: Equatable {
    case idle
    case testing
    case result(SessionPortTestOutcome)
    case failed(TransmissionErrorPresentation)
}

enum SessionBlocklistUpdateState: Equatable {
    case idle
    case updating
    case success(ruleCount: Int)
    case failed(TransmissionErrorPresentation)

    var message: String? {
        switch self {
        case .idle, .updating:
            return nil
        case .success(let ruleCount):
            return "Updated blocklist: \(ruleCount) rules"
        case .failed(let presentation):
            return presentation.message
        }
    }
}

struct SettingsSaveStateView: View {
    let state: SessionSettingsSaveState

    var body: some View {
        switch state {
        case .idle:
            EmptyView()
        case .pending:
            Label("Saving changes soon…", systemImage: "clock")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .saving:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Saving changes…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .failed(let presentation):
            VStack(alignment: .leading, spacing: 4) {
                if let title = presentation.title {
                    Text(title)
                        .font(.caption.weight(.semibold))
                }
                Text(presentation.message)
                    .font(.caption)
            }
            .foregroundStyle(.orange)
        }
    }
}

extension View {
    @MainActor
    func bindSettingsViewModel(
        _ viewModel: SettingsViewModel,
        to store: TransmissionStore
    ) -> some View {
        self
            .onAppear {
                viewModel.bind(to: store)
            }
            .onChange(of: store.settingsConnectionGeneration) { _, _ in
                viewModel.bind(to: store)
            }
            .onChange(of: store.sessionConfiguration) { _, _ in
                viewModel.bind(to: store)
            }
    }
}

@MainActor
final class SettingsViewModel: ObservableObject {
    private struct InFlightSave {
        let revision: UInt64
    }

    @Published private(set) var saveState: SessionSettingsSaveState = .idle
    @Published private(set) var freeSpaceState: SessionFreeSpaceState = .idle
    @Published private(set) var portTestState: SessionPortTestState = .idle
    @Published private(set) var blocklistUpdateState: SessionBlocklistUpdateState = .idle

    private weak var store: (any SessionSettingsServing)?
    private let debounceInterval: TimeInterval
    private let sleep: @Sendable (TimeInterval) async throws -> Void

    private var baseline: TransmissionSessionResponseArguments?
    private var boundHostID: String?
    private var boundGeneration: UUID?

    private var draft = TransmissionSessionSetRequestArgs()
    private var dirtyFieldRevisions: [AnyKeyPath: UInt64] = [:]
    private var nextRevision: UInt64 = 0
    private var inFlightSave: InFlightSave?
    private var debounceTask: Task<Void, Never>?

    init(
        debounceInterval: TimeInterval = 1.0,
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void = SettingsViewModel.liveSleep
    ) {
        self.debounceInterval = debounceInterval
        self.sleep = sleep
    }

    deinit {
        debounceTask?.cancel()
    }

    func bind(to store: any SessionSettingsServing) {
        self.store = store
        synchronizeWithStore()
    }

    func synchronizeWithStore() {
        guard let store else { return }

        let nextHostID = store.host?.serverID
        let nextGeneration = store.settingsConnectionGeneration
        let nextBaseline = store.sessionConfiguration
        let didChangeContext = nextHostID != boundHostID || nextGeneration != boundGeneration

        if didChangeContext {
            cancelDebounce()
            draft = TransmissionSessionSetRequestArgs()
            dirtyFieldRevisions = [:]
            inFlightSave = nil
            saveState = .idle
            freeSpaceState = .idle
            portTestState = .idle
            blocklistUpdateState = .idle
        }

        boundHostID = nextHostID
        boundGeneration = nextGeneration
        baseline = nextBaseline

        if let nextBaseline {
            rebaseDirtyFields(using: nextBaseline)
        }

        refreshSaveStateAfterSynchronization()
    }

    func value<Value: Equatable>(
        for keyPath: WritableKeyPath<TransmissionSessionSetRequestArgs, Value?>,
        fallback: Value
    ) -> Value {
        draft[keyPath: keyPath] ?? fallback
    }

    func setValue<Value: Equatable>(
        _ keyPath: WritableKeyPath<TransmissionSessionSetRequestArgs, Value?>,
        _ value: Value,
        original: Value
    ) {
        if value == original {
            draft[keyPath: keyPath] = nil
            dirtyFieldRevisions.removeValue(forKey: keyPath)
        } else {
            nextRevision += 1
            draft[keyPath: keyPath] = value
            dirtyFieldRevisions[keyPath] = nextRevision
        }

        if dirtyFieldRevisions.isEmpty {
            cancelDebounce()
            refreshSaveStateAfterSynchronization()
        } else {
            scheduleAutosave()
        }
    }

    func checkFreeSpace() async {
        guard let store, let baseline else { return }

        let previousSummary: SessionFreeSpaceSummary?
        switch freeSpaceState {
        case .result(let summary):
            previousSummary = summary
        case .checking(let previous):
            previousSummary = previous
        case .idle, .failed:
            previousSummary = nil
        }

        freeSpaceState = .checking(previous: previousSummary)

        do {
            let response = try await store.checkFreeSpace(path: value(for: \.downloadDir, fallback: baseline.downloadDir))
            freeSpaceState = .result(Self.freeSpaceSummary(from: response))
        } catch {
            guard !Self.isCancellation(error) else { return }
            freeSpaceState = .failed(Self.presentation(for: error))
        }
    }

    func testPort(ipProtocol: String? = nil) async {
        guard let store else { return }

        portTestState = .testing

        do {
            try await flushPendingChanges()
            let response = try await store.testPort(ipProtocol: ipProtocol)
            portTestState = .result(Self.portTestOutcome(from: response))
        } catch {
            guard !Self.isCancellation(error) else { return }
            portTestState = .failed(Self.presentation(for: error))
        }
    }

    func updateBlocklist() async {
        guard let store else { return }

        blocklistUpdateState = .updating

        do {
            try await flushPendingChanges()
            let response = try await store.updateBlocklist()
            blocklistUpdateState = .success(ruleCount: response.blocklistSize)
        } catch {
            guard !Self.isCancellation(error) else { return }
            blocklistUpdateState = .failed(Self.presentation(for: error))
            return
        }

        bind(to: store)
    }

    func flushPendingChanges() async throws {
        cancelDebounce()
        try await savePendingChangesIfNeeded()
    }

    private func scheduleAutosave() {
        cancelDebounce()
        if inFlightSave == nil {
            saveState = .pending
        }

        debounceTask = Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                try await self.sleep(self.debounceInterval)
            } catch {
                return
            }

            do {
                try await self.savePendingChangesIfNeeded()
            } catch {
                guard !Self.isCancellation(error) else { return }
            }
        }
    }

    private func savePendingChangesIfNeeded() async throws {
        guard inFlightSave == nil else { return }
        guard !dirtyFieldRevisions.isEmpty else {
            refreshSaveStateAfterSynchronization()
            return
        }
        guard let store else { return }

        let saveRevision = dirtyFieldRevisions.values.max() ?? nextRevision
        inFlightSave = InFlightSave(revision: saveRevision)
        saveState = .saving

        do {
            let updatedConfiguration = try await store.applySessionSettings(draft)
            baseline = updatedConfiguration
            clearSavedFields(upTo: saveRevision)
            rebaseDirtyFields(using: updatedConfiguration)
            inFlightSave = nil
            refreshSaveStateAfterSynchronization()

            if !dirtyFieldRevisions.isEmpty {
                scheduleAutosave()
            }
        } catch {
            inFlightSave = nil
            if Self.isCancellation(error) {
                refreshSaveStateAfterSynchronization()
                throw error
            }

            saveState = .failed(Self.presentation(for: error))
            throw error
        }
    }

    private func clearSavedFields(upTo revision: UInt64) {
        clearSavedField(\.speedLimitDown, upTo: revision)
        clearSavedField(\.speedLimitDownEnabled, upTo: revision)
        clearSavedField(\.speedLimitUp, upTo: revision)
        clearSavedField(\.speedLimitUpEnabled, upTo: revision)
        clearSavedField(\.altSpeedDown, upTo: revision)
        clearSavedField(\.altSpeedUp, upTo: revision)
        clearSavedField(\.altSpeedEnabled, upTo: revision)
        clearSavedField(\.altSpeedTimeBegin, upTo: revision)
        clearSavedField(\.altSpeedTimeEnd, upTo: revision)
        clearSavedField(\.altSpeedTimeEnabled, upTo: revision)
        clearSavedField(\.altSpeedTimeDay, upTo: revision)
        clearSavedField(\.downloadDir, upTo: revision)
        clearSavedField(\.incompleteDir, upTo: revision)
        clearSavedField(\.incompleteDirEnabled, upTo: revision)
        clearSavedField(\.startAddedTorrents, upTo: revision)
        clearSavedField(\.trashOriginalTorrentFiles, upTo: revision)
        clearSavedField(\.renamePartialFiles, upTo: revision)
        clearSavedField(\.downloadQueueEnabled, upTo: revision)
        clearSavedField(\.downloadQueueSize, upTo: revision)
        clearSavedField(\.seedQueueEnabled, upTo: revision)
        clearSavedField(\.seedQueueSize, upTo: revision)
        clearSavedField(\.seedRatioLimited, upTo: revision)
        clearSavedField(\.seedRatioLimit, upTo: revision)
        clearSavedField(\.idleSeedingLimit, upTo: revision)
        clearSavedField(\.idleSeedingLimitEnabled, upTo: revision)
        clearSavedField(\.queueStalledEnabled, upTo: revision)
        clearSavedField(\.queueStalledMinutes, upTo: revision)
        clearSavedField(\.peerPort, upTo: revision)
        clearSavedField(\.peerPortRandomOnStart, upTo: revision)
        clearSavedField(\.portForwardingEnabled, upTo: revision)
        clearSavedField(\.dhtEnabled, upTo: revision)
        clearSavedField(\.pexEnabled, upTo: revision)
        clearSavedField(\.lpdEnabled, upTo: revision)
        clearSavedField(\.encryption, upTo: revision)
        clearSavedField(\.utpEnabled, upTo: revision)
        clearSavedField(\.peerLimitGlobal, upTo: revision)
        clearSavedField(\.peerLimitPerTorrent, upTo: revision)
        clearSavedField(\.blocklistEnabled, upTo: revision)
        clearSavedField(\.blocklistUrl, upTo: revision)
        clearSavedField(\.defaultTrackers, upTo: revision)
        clearSavedField(\.cacheSizeMb, upTo: revision)
        clearSavedField(\.scriptTorrentDoneEnabled, upTo: revision)
        clearSavedField(\.scriptTorrentDoneFilename, upTo: revision)
        clearSavedField(\.scriptTorrentAddedEnabled, upTo: revision)
        clearSavedField(\.scriptTorrentAddedFilename, upTo: revision)
        clearSavedField(\.scriptTorrentDoneSeedingEnabled, upTo: revision)
        clearSavedField(\.scriptTorrentDoneSeedingFilename, upTo: revision)
    }

    private func clearSavedField<Value>(
        _ keyPath: WritableKeyPath<TransmissionSessionSetRequestArgs, Value?>,
        upTo revision: UInt64
    ) {
        guard let fieldRevision = dirtyFieldRevisions[keyPath], fieldRevision <= revision else {
            return
        }

        dirtyFieldRevisions.removeValue(forKey: keyPath)
        draft[keyPath: keyPath] = nil
    }

    private func rebaseDirtyFields(using baseline: TransmissionSessionResponseArguments) {
        rebaseField(\.speedLimitDown, against: baseline.speedLimitDown)
        rebaseField(\.speedLimitDownEnabled, against: baseline.speedLimitDownEnabled)
        rebaseField(\.speedLimitUp, against: baseline.speedLimitUp)
        rebaseField(\.speedLimitUpEnabled, against: baseline.speedLimitUpEnabled)
        rebaseField(\.altSpeedDown, against: baseline.altSpeedDown)
        rebaseField(\.altSpeedUp, against: baseline.altSpeedUp)
        rebaseField(\.altSpeedEnabled, against: baseline.altSpeedEnabled)
        rebaseField(\.altSpeedTimeBegin, against: baseline.altSpeedTimeBegin)
        rebaseField(\.altSpeedTimeEnd, against: baseline.altSpeedTimeEnd)
        rebaseField(\.altSpeedTimeEnabled, against: baseline.altSpeedTimeEnabled)
        rebaseField(\.altSpeedTimeDay, against: baseline.altSpeedTimeDay)
        rebaseField(\.downloadDir, against: baseline.downloadDir)
        rebaseField(\.incompleteDir, against: baseline.incompleteDir)
        rebaseField(\.incompleteDirEnabled, against: baseline.incompleteDirEnabled)
        rebaseField(\.startAddedTorrents, against: baseline.startAddedTorrents)
        rebaseField(\.trashOriginalTorrentFiles, against: baseline.trashOriginalTorrentFiles)
        rebaseField(\.renamePartialFiles, against: baseline.renamePartialFiles)
        rebaseField(\.downloadQueueEnabled, against: baseline.downloadQueueEnabled)
        rebaseField(\.downloadQueueSize, against: baseline.downloadQueueSize)
        rebaseField(\.seedQueueEnabled, against: baseline.seedQueueEnabled)
        rebaseField(\.seedQueueSize, against: baseline.seedQueueSize)
        rebaseField(\.seedRatioLimited, against: baseline.seedRatioLimited)
        rebaseField(\.seedRatioLimit, against: baseline.seedRatioLimit)
        rebaseField(\.idleSeedingLimit, against: baseline.idleSeedingLimit)
        rebaseField(\.idleSeedingLimitEnabled, against: baseline.idleSeedingLimitEnabled)
        rebaseField(\.queueStalledEnabled, against: baseline.queueStalledEnabled)
        rebaseField(\.queueStalledMinutes, against: baseline.queueStalledMinutes)
        rebaseField(\.peerPort, against: baseline.peerPort)
        rebaseField(\.peerPortRandomOnStart, against: baseline.peerPortRandomOnStart)
        rebaseField(\.portForwardingEnabled, against: baseline.portForwardingEnabled)
        rebaseField(\.dhtEnabled, against: baseline.dhtEnabled)
        rebaseField(\.pexEnabled, against: baseline.pexEnabled)
        rebaseField(\.lpdEnabled, against: baseline.lpdEnabled)
        rebaseField(\.encryption, against: baseline.encryption)
        rebaseField(\.utpEnabled, against: baseline.utpEnabled)
        rebaseField(\.peerLimitGlobal, against: baseline.peerLimitGlobal)
        rebaseField(\.peerLimitPerTorrent, against: baseline.peerLimitPerTorrent)
        rebaseField(\.blocklistEnabled, against: baseline.blocklistEnabled)
        rebaseField(\.blocklistUrl, against: baseline.blocklistUrl)
        rebaseField(\.defaultTrackers, against: baseline.defaultTrackers)
    }

    private func rebaseField<Value: Equatable>(
        _ keyPath: WritableKeyPath<TransmissionSessionSetRequestArgs, Value?>,
        against baselineValue: Value
    ) {
        guard draft[keyPath: keyPath] == baselineValue else {
            return
        }

        dirtyFieldRevisions.removeValue(forKey: keyPath)
        draft[keyPath: keyPath] = nil
    }

    private func refreshSaveStateAfterSynchronization() {
        guard !dirtyFieldRevisions.isEmpty else {
            saveState = inFlightSave == nil ? .idle : .saving
            return
        }

        if inFlightSave != nil {
            saveState = .saving
        } else if case .failed = saveState {
            return
        } else {
            saveState = .pending
        }
    }

    private func cancelDebounce() {
        debounceTask?.cancel()
        debounceTask = nil
    }

    private static func presentation(for error: Error) -> TransmissionErrorPresentation {
        let transmissionError = TransmissionErrorResolver.transmissionError(from: error)
        return TransmissionErrorPresenter.presentation(for: transmissionError)
    }

    private static func isCancellation(_ error: Error) -> Bool {
        switch TransmissionErrorResolver.transmissionError(from: error) {
        case .cancelled:
            return true
        default:
            return false
        }
    }

    private static func freeSpaceSummary(from response: FreeSpaceResponse) -> SessionFreeSpaceSummary {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary

        let freeSpace = formatter.string(fromByteCount: response.sizeBytes)
        let totalSpace = formatter.string(fromByteCount: response.totalSize)
        let percentUsed = 100.0 - (Double(response.sizeBytes) / Double(response.totalSize) * 100.0)

        return SessionFreeSpaceSummary(
            freeSpace: freeSpace,
            totalSpace: totalSpace,
            percentUsed: String(format: "%.1f%%", percentUsed)
        )
    }

    private static func portTestOutcome(from response: PortTestResponse) -> SessionPortTestOutcome {
        if response.portIsOpen == true {
            return .open(protocolName: response.ipProtocol?.uppercased() ?? "IP")
        }

        if response.portIsOpen == false {
            return .closed(protocolName: response.ipProtocol?.uppercased() ?? "IP")
        }

        return .checkerUnavailable
    }

    private static func liveSleep(seconds: TimeInterval) async throws {
        let nanoseconds = UInt64(max(0, seconds) * 1_000_000_000)
        try await Task.sleep(nanoseconds: nanoseconds)
    }
}
