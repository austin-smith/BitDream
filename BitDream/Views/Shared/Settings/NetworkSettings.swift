import SwiftUI

struct NetworkContent: View {
    let config: TransmissionSessionResponseArguments
    @ObservedObject var editModel: SettingsViewModel
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
                            get: { editModel.value(for: \.peerPort, fallback: config.peerPort) },
                            set: { editModel.setValue(\.peerPort, $0, original: config.peerPort) }
                        ), format: .number.grouping(.never))

                    }

                    Button("Check Port") {
                        Task {
                            await editModel.testPort(ipProtocol: nil)
                        }
                    }
                    .disabled({
                        if case .testing = editModel.portTestState {
                            return true
                        }
                        return false
                    }())

                    Text("Port number for incoming peer connections")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    switch editModel.portTestState {
                    case .testing:
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.3)
                                .frame(width: 8, height: 8)
                            Text("Testing port...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    case .result(let outcome):
                        Text(outcome.message)
                            .font(.caption)
                            .foregroundColor(outcome.color)
                    case .failed(let presentation):
                        Text(presentation.message)
                            .font(.caption)
                            .foregroundColor(.orange)
                    case .idle:
                        EmptyView()
                    }
                }

                Toggle("Randomize port on launch", isOn: Binding(
                    get: { editModel.value(for: \.peerPortRandomOnStart, fallback: config.peerPortRandomOnStart) },
                    set: { editModel.setValue(\.peerPortRandomOnStart, $0, original: config.peerPortRandomOnStart) }
                ))

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Encryption")
                        Spacer()
                        Picker("", selection: Binding(
                            get: { editModel.value(for: \.encryption, fallback: config.encryption) },
                            set: { editModel.setValue(\.encryption, $0, original: config.encryption) }
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
                    get: { editModel.value(for: \.portForwardingEnabled, fallback: config.portForwardingEnabled) },
                    set: { editModel.setValue(\.portForwardingEnabled, $0, original: config.portForwardingEnabled) }
                ))

                Toggle("Enable DHT (Distributed Hash Table)", isOn: Binding(
                    get: { editModel.value(for: \.dhtEnabled, fallback: config.dhtEnabled) },
                    set: { editModel.setValue(\.dhtEnabled, $0, original: config.dhtEnabled) }
                ))

                Toggle("Enable PEX (Peer Exchange)", isOn: Binding(
                    get: { editModel.value(for: \.pexEnabled, fallback: config.pexEnabled) },
                    set: { editModel.setValue(\.pexEnabled, $0, original: config.pexEnabled) }
                ))

                Toggle("Enable LPD (Local Peer Discovery)", isOn: Binding(
                    get: { editModel.value(for: \.lpdEnabled, fallback: config.lpdEnabled) },
                    set: { editModel.setValue(\.lpdEnabled, $0, original: config.lpdEnabled) }
                ))

                Toggle("Enable µTP (Micro Transport Protocol)", isOn: Binding(
                    get: { editModel.value(for: \.utpEnabled, fallback: config.utpEnabled) },
                    set: { editModel.setValue(\.utpEnabled, $0, original: config.utpEnabled) }
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
                        get: { editModel.value(for: \.peerLimitGlobal, fallback: config.peerLimitGlobal) },
                        set: { editModel.setValue(\.peerLimitGlobal, $0, original: config.peerLimitGlobal) }
                    ), format: .number.grouping(.never))

                }

                HStack {
                    Text("Maximum per torrent peers")
                    Spacer()
                    TextField("", value: Binding(
                        get: { editModel.value(for: \.peerLimitPerTorrent, fallback: config.peerLimitPerTorrent) },
                        set: { editModel.setValue(\.peerLimitPerTorrent, $0, original: config.peerLimitPerTorrent) }
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
                    get: { editModel.value(for: \.blocklistEnabled, fallback: config.blocklistEnabled) },
                    set: { editModel.setValue(\.blocklistEnabled, $0, original: config.blocklistEnabled) }
                ))

                if editModel.value(for: \.blocklistEnabled, fallback: config.blocklistEnabled) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Blocklist URL")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("URL", text: Binding(
                            get: { editModel.value(for: \.blocklistUrl, fallback: config.blocklistUrl) },
                            set: { editModel.setValue(\.blocklistUrl, $0, original: config.blocklistUrl) }
                        ))

                    }

                    HStack {
                        Text("Blocklist rules active")
                        Spacer()
                        if case .updating = editModel.blocklistUpdateState {
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
                        Task {
                            await editModel.updateBlocklist()
                        }
                    }
                    .disabled({
                        if case .updating = editModel.blocklistUpdateState {
                            return true
                        }
                        return false
                    }())

                    if let blocklistUpdateMessage = editModel.blocklistUpdateState.message {
                        Text(blocklistUpdateMessage)
                            .font(.caption)
                            .foregroundColor({
                                if case .failed = editModel.blocklistUpdateState {
                                    return .orange
                                }
                                return .secondary
                            }())
                            .padding(.top, 4)
                    }
                }
            }
        }
    }
}
