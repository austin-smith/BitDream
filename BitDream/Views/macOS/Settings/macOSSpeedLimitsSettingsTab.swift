import SwiftUI

#if os(macOS)
struct macOSSpeedLimitsSettingsTab: View {
    let config: TransmissionSessionResponseArguments
    let editModel: SettingsViewModel

    var body: some View {
        GroupBox {
            SpeedLimitsContent(config: config, editModel: editModel)
                .padding(16)
        }
    }
}
#endif
