import SwiftUI

#if os(macOS)
struct macOSTorrentSettingsTab: View {
    let config: TransmissionSessionResponseArguments
    let editModel: SessionSettingsEditModel

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                settingsSection("File Management") {
                    FileManagementContent(config: config, editModel: editModel)
                }

                divider

                settingsSection("Queue Management") {
                    QueueManagementContent(config: config, editModel: editModel)
                }

                divider

                settingsSection("Seeding") {
                    SeedingContent(config: config, editModel: editModel)
                }
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.bottom, 4)
            content()
        }
    }

    private var divider: some View {
        Divider()
            .padding(.vertical, 4)
    }
}
#endif
