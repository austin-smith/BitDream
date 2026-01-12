import SwiftUI

#if os(macOS)
struct macOSConnectionDebugView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Form {
                Section("Status") {
                    keyValueRow("Connection", statusText)
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

    private var statusText: String {
        store.isReconnecting ? "Reconnecting" : "Connected"
    }

    private var nextRetryRow: some View {
        HStack {
            Text("Next Retry")
            Spacer(minLength: 16)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(nextRetryText(at: context.date))
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
    }

    private func nextRetryText(at date: Date) -> String {
        guard let retryAt = store.nextRetryAt else { return "-" }
        let remaining = max(0, Int(retryAt.timeIntervalSince(date)))
        if remaining > 0 {
            return "\(remaining)s"
        }
        return store.isReconnecting ? "Retrying now…" : "-"
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
