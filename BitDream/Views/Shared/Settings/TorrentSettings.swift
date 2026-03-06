import SwiftUI

struct QueueManagementContent: View {
    let config: TransmissionSessionResponseArguments
    @ObservedObject var editModel: SessionSettingsEditModel
    var showHeadings: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Toggle("Download queue size", isOn: Binding(
                get: { editModel.getValue("downloadQueueEnabled", fallback: config.downloadQueueEnabled) },
                set: { editModel.setValue("downloadQueueEnabled", $0, original: config.downloadQueueEnabled) }
            ))

            if editModel.getValue("downloadQueueEnabled", fallback: config.downloadQueueEnabled) {
                HStack {
                    Text("Maximum active downloads")
                    Spacer()
                    TextField("", value: Binding(
                        get: { editModel.getValue("downloadQueueSize", fallback: config.downloadQueueSize) },
                        set: { editModel.setValue("downloadQueueSize", $0, original: config.downloadQueueSize) }
                    ), format: .number)

                }
            }

            Toggle("Seed queue size", isOn: Binding(
                get: { editModel.getValue("seedQueueEnabled", fallback: config.seedQueueEnabled) },
                set: { editModel.setValue("seedQueueEnabled", $0, original: config.seedQueueEnabled) }
            ))

            if editModel.getValue("seedQueueEnabled", fallback: config.seedQueueEnabled) {
                HStack {
                    Text("Maximum active seeds")
                    Spacer()
                    TextField("", value: Binding(
                        get: { editModel.getValue("seedQueueSize", fallback: config.seedQueueSize) },
                        set: { editModel.setValue("seedQueueSize", $0, original: config.seedQueueSize) }
                    ), format: .number)

                }
            }

            Toggle("Consider idle torrents as stalled after", isOn: Binding(
                get: { editModel.getValue("queueStalledEnabled", fallback: config.queueStalledEnabled) },
                set: { editModel.setValue("queueStalledEnabled", $0, original: config.queueStalledEnabled) }
            ))

            if editModel.getValue("queueStalledEnabled", fallback: config.queueStalledEnabled) {
                HStack {
                    Text("Stalled after")
                    Spacer()
                    TextField("", value: Binding(
                        get: { editModel.getValue("queueStalledMinutes", fallback: config.queueStalledMinutes) },
                        set: { editModel.setValue("queueStalledMinutes", $0, original: config.queueStalledMinutes) }
                    ), format: .number)

                    Text("minutes")
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

struct FileManagementContent: View {
    let config: TransmissionSessionResponseArguments
    @ObservedObject var editModel: SessionSettingsEditModel
    var showHeadings: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                if showHeadings {
                    Text("Download Directory")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                TextField("Path", text: Binding(
                    get: { editModel.getValue("downloadDir", fallback: config.downloadDir) },
                    set: { editModel.setValue("downloadDir", $0, original: config.downloadDir) }
                ))

                Button("Check Space") {
                    checkDirectoryFreeSpace(
                        path: editModel.getValue("downloadDir", fallback: config.downloadDir),
                        editModel: editModel
                    )
                }

                if let freeSpaceInfo = editModel.freeSpaceInfo {
                    HStack(spacing: 6) {
                        Text(freeSpaceInfo)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if editModel.isCheckingSpace {
                            ProgressView()
                                .scaleEffect(0.3)
                                .frame(width: 8, height: 8)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Toggle("Use separate incomplete directory", isOn: Binding(
                    get: { editModel.getValue("incompleteDirEnabled", fallback: config.incompleteDirEnabled) },
                    set: { editModel.setValue("incompleteDirEnabled", $0, original: config.incompleteDirEnabled) }
                ))

                if editModel.getValue("incompleteDirEnabled", fallback: config.incompleteDirEnabled) {
                    TextField("Incomplete directory path", text: Binding(
                        get: { editModel.getValue("incompleteDir", fallback: config.incompleteDir) },
                        set: { editModel.setValue("incompleteDir", $0, original: config.incompleteDir) }
                    ))

                }
            }

            Toggle("Start transfers when added", isOn: Binding(
                get: { editModel.getValue("startAddedTorrents", fallback: config.startAddedTorrents) },
                set: { editModel.setValue("startAddedTorrents", $0, original: config.startAddedTorrents) }
            ))

            Toggle(isOn: Binding(
                get: { editModel.getValue("trashOriginalTorrentFiles", fallback: config.trashOriginalTorrentFiles) },
                set: { editModel.setValue("trashOriginalTorrentFiles", $0, original: config.trashOriginalTorrentFiles) }
            )) {
                HStack(spacing: 0) {
                    Text("Delete original ")
                    Text(".torrent")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.15))
                        .cornerRadius(2)
                    Text(" files")
                }
            }

            Toggle(isOn: Binding(
                get: { editModel.getValue("renamePartialFiles", fallback: config.renamePartialFiles) },
                set: { editModel.setValue("renamePartialFiles", $0, original: config.renamePartialFiles) }
            )) {
                HStack(spacing: 0) {
                    Text("Append ")
                    Text(".part")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.15))
                        .cornerRadius(2)
                    Text(" to incomplete files")
                }
            }
        }
    }
}

struct SeedingContent: View {
    let config: TransmissionSessionResponseArguments
    @ObservedObject var editModel: SessionSettingsEditModel
    var showHeadings: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("Stop seeding at ratio", isOn: Binding(
                get: { editModel.getValue("seedRatioLimited", fallback: config.seedRatioLimited) },
                set: { editModel.setValue("seedRatioLimited", $0, original: config.seedRatioLimited) }
            ))

            if editModel.getValue("seedRatioLimited", fallback: config.seedRatioLimited) {
                HStack {
                    Text("Seed ratio limit")
                    Spacer()
                    TextField("", value: Binding(
                        get: { editModel.getValue("seedRatioLimit", fallback: config.seedRatioLimit) },
                        set: { editModel.setValue("seedRatioLimit", $0, original: config.seedRatioLimit) }
                    ), format: .number.precision(.fractionLength(2)))

                }
            }

            Toggle("Stop seeding when inactive for", isOn: Binding(
                get: { editModel.getValue("idleSeedingLimitEnabled", fallback: config.idleSeedingLimitEnabled) },
                set: { editModel.setValue("idleSeedingLimitEnabled", $0, original: config.idleSeedingLimitEnabled) }
            ))

            if editModel.getValue("idleSeedingLimitEnabled", fallback: config.idleSeedingLimitEnabled) {
                HStack {
                    Text("Inactive for")
                    Spacer()
                    TextField("", value: Binding(
                        get: { editModel.getValue("idleSeedingLimit", fallback: config.idleSeedingLimit) },
                        set: { editModel.setValue("idleSeedingLimit", $0, original: config.idleSeedingLimit) }
                    ), format: .number)

                    Text("minutes")
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}
