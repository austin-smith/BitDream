import SwiftUI

struct TailscaleMachinePicker: View {
    @Bindable var form: ServerFormModel
    @Bindable var model: TailscaleSetupModel

    private var canChooseMachine: Bool {
        model.isSignedIn && !form.hasTailscaleAccountMismatch(with: model.snapshot)
    }

    private var peers: [TailscalePeer] { canChooseMachine ? model.snapshot?.peers ?? [] : [] }

    private var selection: ServerFormModel.TailscaleDestination {
        canChooseMachine ? form.tailscaleDestination(in: peers) : .none
    }

    var body: some View {
        Picker("Machine", selection: Binding(
            get: { selection },
            set: { form.selectTailscaleDestination($0, from: peers) }
        )) {
            if selection == .none {
                Text(unselectedLabel)
                    .tag(ServerFormModel.TailscaleDestination.none)
                    .disabled(true)
            }
            ForEach(peers.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) { peer in
                Text(peer.name.isEmpty ? peer.address : peer.name)
                    .tag(ServerFormModel.TailscaleDestination.machine(peer.id))
                    .disabled(model.snapshot?.isReady != true)
            }
            Divider()
            Text(form.isEnteringTailscaleAddress ? "Manual Address" : "Enter Address Manually…")
                .tag(ServerFormModel.TailscaleDestination.manual)
        }
        .pickerStyle(.menu)
        .disabled(!canChooseMachine)
        .onChange(of: peers, initial: true) { _, peers in
            form.resolveTailscaleAddressEntry(in: peers)
        }
    }

    private var unselectedLabel: String {
        guard canChooseMachine else { return "Choose a Machine" }
        if !form.values.address.isEmpty { return form.values.address }
        return model.snapshot?.isReady == true && peers.isEmpty ? "No Machines Available" : "Choose a Machine"
    }
}

struct ServerConnectionHeader: View {
    let usesTailscale: Bool
    @State private var isShowingHelp = false

    var body: some View {
        HStack {
            Text("Connection")
            Spacer()
            if usesTailscale {
                Button("Tailscale Setup Help", systemImage: "questionmark.circle") {
                    isShowingHelp = true
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Tailscale setup help")
            }
        }
        .sheet(isPresented: $isShowingHelp) {
            TailscaleServerHelpView()
        }
    }
}

#if DEBUG
#Preview("Tailscale Destination") {
    @Previewable @State var form = ServerFormModel()
    @Previewable @State var model = TailscaleSetupModel()
    Form {
        Section {
            TailscaleMachinePicker(form: form, model: model)
            TextField("Address", text: $form.values.address)
                .disabled(!form.isEnteringTailscaleAddress)
            Toggle("Use SSL", isOn: $form.values.isSSL)
        } header: {
            ServerConnectionHeader(usesTailscale: true)
        }
    }
    .formStyle(.grouped)
}
#endif
