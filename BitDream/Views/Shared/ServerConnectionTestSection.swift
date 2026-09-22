import SwiftUI

struct ServerConnectionTestSection: View {
    @Environment(\.serverServices) private var services
    @Bindable var form: ServerFormModel
    @State private var requestedValues: ServerFormModel.Values?
    @State private var result: String?
    @State private var isTesting = false

    var body: some View {
        Section {
            if isTesting {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Testing connection…")
                    Spacer()
                    Button("Cancel") { requestedValues = nil }
                }
            } else {
                Button("Test Connection") {
                    result = nil
                    requestedValues = form.values
                }
                .disabled(!form.isAddressValid || !form.isPortValid)
            }
            if let result { Text(result).font(.callout) }
        }
        .onChange(of: form.values) {
            requestedValues = nil
            result = nil
        }
        .task(id: requestedValues) {
            guard let values = requestedValues else { isTesting = false; return }
            isTesting = true
            defer { isTesting = false }
            do {
                let descriptor = TransmissionConnectionDescriptor(
                    scheme: values.isSSL ? "https" : "http", host: values.address,
                    port: values.port, username: values.username,
                    credentialSource: .resolvedPassword(values.password),
                    connectionRoute: values.connectionRoute, tailscaleAccountID: values.tailscaleAccountID
                )
                let response = try await services.testConnection(descriptor)
                try Task.checkCancellation()
                result = "Connected to Transmission \(response.version)."
            } catch {
                guard !Task.isCancelled else { return }
                if let error = error as? TailscaleError {
                    result = error.localizedDescription
                } else {
                    result = TransmissionErrorPresenter.presentation(
                        for: TransmissionErrorResolver.transmissionError(from: error)
                    ).message
                }
            }
            requestedValues = nil
        }
    }
}

#if DEBUG
#Preview("Connection Test") {
    @Previewable @State var form = ServerFormModel()
    Form {
        ServerConnectionTestSection(form: form)
    }
}
#endif
