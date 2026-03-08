#if os(iOS)
import SwiftUI

struct iOSTorrentsSettingsView: View {
    @ObservedObject var store: TransmissionStore
    @StateObject private var editModel = SessionSettingsEditModel()

    var body: some View {
        Group {
            if let config = store.sessionConfiguration {
                Form {
                    Section(header: Text("File Management")) {
                        HStack {
                            Text("Download Directory")
                            Spacer()
                            Text(editModel.getValue("downloadDir", fallback: config.downloadDir))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        Button("Check Free Space") {
                            checkDirectoryFreeSpace(
                                path: editModel.getValue("downloadDir", fallback: config.downloadDir),
                                editModel: editModel
                            )
                        }

                        if let freeSpaceInfo = editModel.freeSpaceInfo {
                            HStack {
                                Text("Available Space")
                                Spacer()
                                if editModel.isCheckingSpace {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                } else {
                                    Text(freeSpaceInfo)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }

                        Toggle("Use separate incomplete directory", isOn: Binding(
                            get: { editModel.getValue("incompleteDirEnabled", fallback: config.incompleteDirEnabled) },
                            set: { editModel.setValue("incompleteDirEnabled", $0, original: config.incompleteDirEnabled) }
                        ))

                        Toggle("Start transfers when added", isOn: Binding(
                            get: { editModel.getValue("startAddedTorrents", fallback: config.startAddedTorrents) },
                            set: { editModel.setValue("startAddedTorrents", $0, original: config.startAddedTorrents) }
                        ))

                        Toggle("Delete original .torrent files", isOn: Binding(
                            get: { editModel.getValue("trashOriginalTorrentFiles", fallback: config.trashOriginalTorrentFiles) },
                            set: { editModel.setValue("trashOriginalTorrentFiles", $0, original: config.trashOriginalTorrentFiles) }
                        ))

                        Toggle("Append .part to incomplete files", isOn: Binding(
                            get: { editModel.getValue("renamePartialFiles", fallback: config.renamePartialFiles) },
                            set: { editModel.setValue("renamePartialFiles", $0, original: config.renamePartialFiles) }
                        ))
                    }

                    Section(header: Text("Queue Management")) {
                        Toggle("Download queue", isOn: Binding(
                            get: { editModel.getValue("downloadQueueEnabled", fallback: config.downloadQueueEnabled) },
                            set: { editModel.setValue("downloadQueueEnabled", $0, original: config.downloadQueueEnabled) }
                        ))

                        HStack {
                            Text("Maximum active downloads")
                            Spacer()
                            TextField("", value: Binding(
                                get: { editModel.getValue("downloadQueueSize", fallback: config.downloadQueueSize) },
                                set: { editModel.setValue("downloadQueueSize", $0, original: config.downloadQueueSize) }
                            ), format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .disabled(!editModel.getValue("downloadQueueEnabled", fallback: config.downloadQueueEnabled))
                            .foregroundColor(editModel.getValue("downloadQueueEnabled", fallback: config.downloadQueueEnabled) ? .primary : .secondary)
                        }

                        Toggle("Seed queue", isOn: Binding(
                            get: { editModel.getValue("seedQueueEnabled", fallback: config.seedQueueEnabled) },
                            set: { editModel.setValue("seedQueueEnabled", $0, original: config.seedQueueEnabled) }
                        ))

                        HStack {
                            Text("Maximum active seeds")
                            Spacer()
                            TextField("", value: Binding(
                                get: { editModel.getValue("seedQueueSize", fallback: config.seedQueueSize) },
                                set: { editModel.setValue("seedQueueSize", $0, original: config.seedQueueSize) }
                            ), format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .disabled(!editModel.getValue("seedQueueEnabled", fallback: config.seedQueueEnabled))
                            .foregroundColor(editModel.getValue("seedQueueEnabled", fallback: config.seedQueueEnabled) ? .primary : .secondary)
                        }

                        Toggle("Consider idle torrents as stalled", isOn: Binding(
                            get: { editModel.getValue("queueStalledEnabled", fallback: config.queueStalledEnabled) },
                            set: { editModel.setValue("queueStalledEnabled", $0, original: config.queueStalledEnabled) }
                        ))

                        HStack {
                            Text("Stalled after (minutes)")
                            Spacer()
                            TextField("", value: Binding(
                                get: { editModel.getValue("queueStalledMinutes", fallback: config.queueStalledMinutes) },
                                set: { editModel.setValue("queueStalledMinutes", $0, original: config.queueStalledMinutes) }
                            ), format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .disabled(!editModel.getValue("queueStalledEnabled", fallback: config.queueStalledEnabled))
                            .foregroundColor(editModel.getValue("queueStalledEnabled", fallback: config.queueStalledEnabled) ? .primary : .secondary)
                        }
                    }

                    Section(header: Text("Seeding")) {
                        Toggle("Stop seeding at ratio", isOn: Binding(
                            get: { editModel.getValue("seedRatioLimited", fallback: config.seedRatioLimited) },
                            set: { editModel.setValue("seedRatioLimited", $0, original: config.seedRatioLimited) }
                        ))

                        HStack {
                            Text("Seed ratio limit")
                            Spacer()
                            TextField("", value: Binding(
                                get: { editModel.getValue("seedRatioLimit", fallback: config.seedRatioLimit) },
                                set: { editModel.setValue("seedRatioLimit", $0, original: config.seedRatioLimit) }
                            ), format: .number.precision(.fractionLength(2)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .disabled(!editModel.getValue("seedRatioLimited", fallback: config.seedRatioLimited))
                            .foregroundColor(editModel.getValue("seedRatioLimited", fallback: config.seedRatioLimited) ? .primary : .secondary)
                        }

                        Toggle("Stop seeding when inactive", isOn: Binding(
                            get: { editModel.getValue("idleSeedingLimitEnabled", fallback: config.idleSeedingLimitEnabled) },
                            set: { editModel.setValue("idleSeedingLimitEnabled", $0, original: config.idleSeedingLimitEnabled) }
                        ))

                        HStack {
                            Text("Inactive for (minutes)")
                            Spacer()
                            TextField("", value: Binding(
                                get: { editModel.getValue("idleSeedingLimit", fallback: config.idleSeedingLimit) },
                                set: { editModel.setValue("idleSeedingLimit", $0, original: config.idleSeedingLimit) }
                            ), format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .disabled(!editModel.getValue("idleSeedingLimitEnabled", fallback: config.idleSeedingLimitEnabled))
                            .foregroundColor(editModel.getValue("idleSeedingLimitEnabled", fallback: config.idleSeedingLimitEnabled) ? .primary : .secondary)
                        }
                    }
                }
                .navigationTitle("Torrents")
                .onAppear {
                    editModel.setup(store: store)
                }
            } else {
                ContentUnavailableView(
                    "No Server Connected",
                    systemImage: "arrow.down.circle",
                    description: Text("Torrent settings will appear when connected to a server.")
                )
            }
        }
    }
}
#endif
