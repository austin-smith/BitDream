import SwiftUI

/// Row content describing a server: name, endpoint, default marker, and connection indicator.
struct ServerRowLabel: View {
    let host: Host
    let connectionState: TransmissionConnectionState?

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(host.displayName)
                    .lineLimit(1)

                Text(host.endpointDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if host.isDefault {
                Text("Default")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let connectionState {
                ServerConnectionIndicator(state: connectionState)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(connectionState?.serverStatusLabel ?? "")
    }

    private var accessibilityLabel: String {
        let defaultLabel = host.isDefault ? ", default server" : ""
        let currentLabel = connectionState != nil ? ", current server" : ""
        return "\(host.displayName), \(host.server ?? "Unknown host"), port \(host.port)\(defaultLabel)\(currentLabel)"
    }
}

#if DEBUG
#Preview("Server Row", traits: .sizeThatFitsLayout) {
    PreviewContainer { environment in
        ServerRowLabel(host: environment.hosts[0], connectionState: .connected)
            .padding()
            .frame(width: 420)
    }
}
#endif
