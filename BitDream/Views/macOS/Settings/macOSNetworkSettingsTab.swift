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
