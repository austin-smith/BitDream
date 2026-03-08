#if os(iOS)
import SwiftUI

struct iOSNetworkSettingsView: View {
    @ObservedObject var store: TransmissionStore
    @StateObject private var editModel = SessionSettingsEditModel()

    var body: some View {
        Group {
            if let config = store.sessionConfiguration {
                Form {
                    Section(header: Text("Connection")) {
                        HStack {
                            Text("Peer listening port")
                            Spacer()
                            TextField("", value: Binding(
                                get: { editModel.getValue("peerPort", fallback: config.peerPort) },
                                set: { editModel.setValue("peerPort", $0, original: config.peerPort) }
                            ), format: .number.grouping(.never))
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                        }

                        Button("Check Port") {
                            checkPort(editModel: editModel, ipProtocol: nil)
                        }
                        .disabled(editModel.isTestingPort)

                        if editModel.isTestingPort {
                            HStack {
                                Text("Testing port...")
                                Spacer()
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        } else if let portTestResult = editModel.portTestResult {
                            HStack {
                                Text("Port Status")
                                Spacer()
                                Text(portTestResult)
                                    .foregroundColor(portTestResult.contains("open") ? .green : .orange)
                            }
                        }

                        Toggle("Randomize port on launch", isOn: Binding(
                            get: { editModel.getValue("peerPortRandomOnStart", fallback: config.peerPortRandomOnStart) },
                            set: { editModel.setValue("peerPortRandomOnStart", $0, original: config.peerPortRandomOnStart) }
                        ))

                        Picker("Encryption", selection: Binding(
                            get: { editModel.getValue("encryption", fallback: config.encryption) },
                            set: { editModel.setValue("encryption", $0, original: config.encryption) }
                        )) {
                            Text("Required").tag("required")
                            Text("Preferred").tag("preferred")
                            Text("Tolerated").tag("tolerated")
                        }
                    }

                    Section(header: Text("Peer Exchange")) {
                        Toggle("Enable port forwarding", isOn: Binding(
                            get: { editModel.getValue("portForwardingEnabled", fallback: config.portForwardingEnabled) },
                            set: { editModel.setValue("portForwardingEnabled", $0, original: config.portForwardingEnabled) }
                        ))

                        Toggle("Enable DHT", isOn: Binding(
                            get: { editModel.getValue("dhtEnabled", fallback: config.dhtEnabled) },
                            set: { editModel.setValue("dhtEnabled", $0, original: config.dhtEnabled) }
                        ))

                        Toggle("Enable PEX", isOn: Binding(
                            get: { editModel.getValue("pexEnabled", fallback: config.pexEnabled) },
                            set: { editModel.setValue("pexEnabled", $0, original: config.pexEnabled) }
                        ))

                        Toggle("Enable LPD", isOn: Binding(
                            get: { editModel.getValue("lpdEnabled", fallback: config.lpdEnabled) },
                            set: { editModel.setValue("lpdEnabled", $0, original: config.lpdEnabled) }
                        ))

                        Toggle("Enable µTP", isOn: Binding(
                            get: { editModel.getValue("utpEnabled", fallback: config.utpEnabled) },
                            set: { editModel.setValue("utpEnabled", $0, original: config.utpEnabled) }
                        ))
                    }

                    Section(header: Text("Peer Limits")) {
                        HStack {
                            Text("Maximum global peers")
                            Spacer()
                            TextField("", value: Binding(
                                get: { editModel.getValue("peerLimitGlobal", fallback: config.peerLimitGlobal) },
                                set: { editModel.setValue("peerLimitGlobal", $0, original: config.peerLimitGlobal) }
                            ), format: .number.grouping(.never))
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                        }

                        HStack {
                            Text("Maximum per torrent peers")
                            Spacer()
                            TextField("", value: Binding(
                                get: { editModel.getValue("peerLimitPerTorrent", fallback: config.peerLimitPerTorrent) },
                                set: { editModel.setValue("peerLimitPerTorrent", $0, original: config.peerLimitPerTorrent) }
                            ), format: .number.grouping(.never))
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                        }
                    }

                    Section(header: Text("Blocklist")) {
                        Toggle("Enable blocklist", isOn: Binding(
                            get: { editModel.getValue("blocklistEnabled", fallback: config.blocklistEnabled) },
                            set: { editModel.setValue("blocklistEnabled", $0, original: config.blocklistEnabled) }
                        ))

                        HStack {
                            Text("Blocklist URL")
                            Spacer()
                            TextField("URL", text: Binding(
                                get: { editModel.getValue("blocklistUrl", fallback: config.blocklistUrl) },
                                set: { editModel.setValue("blocklistUrl", $0, original: config.blocklistUrl) }
                            ))
                            .multilineTextAlignment(.trailing)
                            .disabled(!editModel.getValue("blocklistEnabled", fallback: config.blocklistEnabled))
                            .foregroundColor(editModel.getValue("blocklistEnabled", fallback: config.blocklistEnabled) ? .primary : .secondary)
                        }

                        HStack {
                            Text("Rules active")
                            Spacer()
                            if editModel.isUpdatingBlocklist {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Text("\(config.blocklistSize)")
                                    .foregroundColor(.secondary)
                            }
                        }

                        Button("Update Blocklist") {
                            updateBlocklist(editModel: editModel)
                        }
                        .disabled(editModel.isUpdatingBlocklist || !editModel.getValue("blocklistEnabled", fallback: config.blocklistEnabled))

                        if let blocklistUpdateResult = editModel.blocklistUpdateResult {
                            Text(blocklistUpdateResult)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .navigationTitle("Network")
                .onAppear {
                    editModel.setup(store: store)
                }
            } else {
                ContentUnavailableView(
                    "No Server Connected",
                    systemImage: "network",
                    description: Text("Network settings will appear when connected to a server.")
                )
            }
        }
    }
}
#endif
