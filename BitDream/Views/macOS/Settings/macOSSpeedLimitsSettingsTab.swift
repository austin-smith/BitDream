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

#if os(macOS) && DEBUG
#Preview("macOS Speed Limit Settings", traits: .fixedLayout(width: 760, height: 620)) {
    @Previewable @StateObject var editModel = SettingsViewModel()
    macOSSpeedLimitsSettingsTab(config: PreviewFixtures.sessionConfiguration, editModel: editModel)
        .padding()
}
#endif
