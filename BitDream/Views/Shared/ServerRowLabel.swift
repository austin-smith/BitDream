import SwiftUI

/// Row content describing a server: name, endpoint, default marker, and connection indicator.
struct ServerRowLabel: View {
    let host: Host
    let isConnected: Bool

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

            if isConnected {
                Image(systemName: "circle.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.green)
                    .help("Connected")
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        let defaultLabel = host.isDefault ? ", default server" : ""
        let connectedLabel = isConnected ? ", connected" : ""
        return "\(host.displayName), \(host.server ?? "Unknown host"), port \(host.port)\(defaultLabel)\(connectedLabel)"
    }
}

#if DEBUG
#Preview("Server Row", traits: .sizeThatFitsLayout) {
    PreviewContainer { environment in
        ServerRowLabel(host: environment.hosts[0], isConnected: true)
            .padding()
            .frame(width: 420)
    }
}
#endif
