import SwiftUI

#if os(macOS)
struct macOSNetworkSettingsTab: View {
    let config: TransmissionSessionResponseArguments
    let editModel: SettingsViewModel

    var body: some View {
        GroupBox {
            NetworkContent(config: config, editModel: editModel)
                .padding(16)
        }
    }
}
#endif

#if os(macOS) && DEBUG
#Preview("macOS Network Settings", traits: .fixedLayout(width: 760, height: 700)) {
    @Previewable @StateObject var editModel = SettingsViewModel()
    macOSNetworkSettingsTab(config: PreviewFixtures.sessionConfiguration, editModel: editModel)
        .padding()
}
#endif
