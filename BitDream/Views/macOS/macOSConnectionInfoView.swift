import SwiftUI

#if os(macOS)
struct macOSConnectionInfoView: View {
    @EnvironmentObject var store: TransmissionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Form {
                Section("Status") {
                    connectionRow
                    lastRefreshRow
                }

                Section("Errors") {
                    nextRetryRow
                    keyValueRow("Last Error Message", lastErrorText)
                }
            }
            .formStyle(.grouped)
        }
        .padding(16)
        .frame(minWidth: 420, minHeight: 320)
    }

    private var connectionRow: some View {
        HStack(spacing: 12) {
            Text("Connection")
            Spacer(minLength: 16)
            if store.connectionStatus == TransmissionStore.ConnectionStatus.reconnecting {
                Button(
                    action: {
                        store.retryNow()
                    },
                    label: {
                        Image(systemName: "arrow.clockwise")
                            .imageScale(.small)
                    }
                )
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Retry now")
                .accessibilityLabel("Retry now")
            }
            Text(connectionStatusTitle(for: store.connectionStatus))
                .font(.system(.body, design: .monospaced))
                .foregroundColor(connectionStatusColor(for: store.connectionStatus))
        }
    }

    private var nextRetryRow: some View {
        HStack {
            Text("Next Retry")
            Spacer(minLength: 16)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(connectionRetryText(status: store.connectionStatus, retryAt: store.nextRetryAt, at: context.date, style: .compact))
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
    }

    private var lastErrorText: String {
        store.lastErrorMessage.isEmpty ? "-" : store.lastErrorMessage
    }

    private var lastRefreshRow: some View {
        HStack {
            Text("Last Refresh")
            Spacer(minLength: 16)
            if let date = store.lastRefreshAt {
                Text(date, style: .relative)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
            } else {
                Text("-")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private func keyValueRow(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key)
            Spacer(minLength: 16)
            Text(value)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.secondary)
        }
    }
}
#endif
