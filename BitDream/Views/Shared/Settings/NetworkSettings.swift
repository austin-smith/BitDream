import SwiftUI

struct NetworkContent: View {
    let config: TransmissionSessionResponseArguments
    @ObservedObject var editModel: SessionSettingsEditModel
    var showHeadings: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 16) {
                if showHeadings {
                    Text("Connection")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 4)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Peer listening port")
                        Spacer()
                        TextField("Port", value: Binding(
                            get: { editModel.getValue("peerPort", fallback: config.peerPort) },
                            set: { editModel.setValue("peerPort", $0, original: config.peerPort) }
                        ), format: .number.grouping(.never))

                    }

                    Button("Check Port") {
                        checkPort(editModel: editModel, ipProtocol: nil)
                    }
                    .disabled(editModel.isTestingPort)

                    Text("Port number for incoming peer connections")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if editModel.isTestingPort {
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.3)
                                .frame(width: 8, height: 8)
                            Text("Testing port...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else if let portTestResult = editModel.portTestResult {
                        Text(portTestResult)
                            .font(.caption)
                            .foregroundColor(portTestResult.contains("open") ? .green : .orange)
                    }
                }

                Toggle("Randomize port on launch", isOn: Binding(
                    get: { editModel.getValue("peerPortRandomOnStart", fallback: config.peerPortRandomOnStart) },
                    set: { editModel.setValue("peerPortRandomOnStart", $0, original: config.peerPortRandomOnStart) }
                ))

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Encryption")
                        Spacer()
                        Picker("", selection: Binding(
                            get: { editModel.getValue("encryption", fallback: config.encryption) },
                            set: { editModel.setValue("encryption", $0, original: config.encryption) }
                        )) {
                            Text("Required").tag("required")
                            Text("Preferred").tag("preferred")
                            Text("Tolerated").tag("tolerated")
                        }
                        .pickerStyle(.menu)
                    }
                    Text("How strictly to enforce encrypted peer connections")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if showHeadings {
                Divider()
                    .padding(.vertical, 4)
            }

            VStack(alignment: .leading, spacing: 12) {
                if showHeadings {
                    Text("Peer Exchange")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 4)
                }

                Toggle("Enable port forwarding", isOn: Binding(
                    get: { editModel.getValue("portForwardingEnabled", fallback: config.portForwardingEnabled) },
                    set: { editModel.setValue("portForwardingEnabled", $0, original: config.portForwardingEnabled) }
                ))

                Toggle("Enable DHT (Distributed Hash Table)", isOn: Binding(
                    get: { editModel.getValue("dhtEnabled", fallback: config.dhtEnabled) },
                    set: { editModel.setValue("dhtEnabled", $0, original: config.dhtEnabled) }
                ))

                Toggle("Enable PEX (Peer Exchange)", isOn: Binding(
                    get: { editModel.getValue("pexEnabled", fallback: config.pexEnabled) },
                    set: { editModel.setValue("pexEnabled", $0, original: config.pexEnabled) }
                ))

                Toggle("Enable LPD (Local Peer Discovery)", isOn: Binding(
                    get: { editModel.getValue("lpdEnabled", fallback: config.lpdEnabled) },
                    set: { editModel.setValue("lpdEnabled", $0, original: config.lpdEnabled) }
                ))

                Toggle("Enable µTP (Micro Transport Protocol)", isOn: Binding(
                    get: { editModel.getValue("utpEnabled", fallback: config.utpEnabled) },
                    set: { editModel.setValue("utpEnabled", $0, original: config.utpEnabled) }
                ))
            }

            if showHeadings {
                Divider()
                    .padding(.vertical, 4)
            }

            VStack(alignment: .leading, spacing: 12) {
                if showHeadings {
                    Text("Peer Limits")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 4)
                }

                HStack {
                    Text("Maximum global peers")
                    Spacer()
                    TextField("", value: Binding(
                        get: { editModel.getValue("peerLimitGlobal", fallback: config.peerLimitGlobal) },
                        set: { editModel.setValue("peerLimitGlobal", $0, original: config.peerLimitGlobal) }
                    ), format: .number.grouping(.never))

                }

                HStack {
                    Text("Maximum per torrent peers")
                    Spacer()
                    TextField("", value: Binding(
                        get: { editModel.getValue("peerLimitPerTorrent", fallback: config.peerLimitPerTorrent) },
                        set: { editModel.setValue("peerLimitPerTorrent", $0, original: config.peerLimitPerTorrent) }
                    ), format: .number.grouping(.never))

                }
            }

            if showHeadings {
                Divider()
                    .padding(.vertical, 4)
            }

            VStack(alignment: .leading, spacing: 12) {
                if showHeadings {
                    Text("Blocklist")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 4)
                }

                Toggle("Enable blocklist", isOn: Binding(
                    get: { editModel.getValue("blocklistEnabled", fallback: config.blocklistEnabled) },
                    set: { editModel.setValue("blocklistEnabled", $0, original: config.blocklistEnabled) }
                ))

                if editModel.getValue("blocklistEnabled", fallback: config.blocklistEnabled) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Blocklist URL")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("URL", text: Binding(
                            get: { editModel.getValue("blocklistUrl", fallback: config.blocklistUrl) },
                            set: { editModel.setValue("blocklistUrl", $0, original: config.blocklistUrl) }
                        ))

                    }

                    HStack {
                        Text("Blocklist rules active")
                        Spacer()
                        if editModel.isUpdatingBlocklist {
                            ProgressView()
                                .scaleEffect(0.3)
                                .frame(width: 8, height: 8)
                            Text("Updating...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text(config.blocklistSize.formatted())
                                .foregroundColor(.secondary)
                                .font(.system(.body, design: .monospaced))
                        }
                    }

                    Button("Update Blocklist") {
                        updateBlocklist(editModel: editModel)
                    }
                    .disabled(editModel.isUpdatingBlocklist)

                    if let blocklistUpdateResult = editModel.blocklistUpdateResult {
                        Text(blocklistUpdateResult)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    }
                }
            }
        }
    }
}
