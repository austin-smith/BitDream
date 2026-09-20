import SwiftUI

struct TailscaleNoticesView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var notices = "Loading notices…"

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(notices)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle("Licenses")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task {
            guard let url = Bundle.main.url(forResource: "TailscaleNotices", withExtension: "txt") else {
                notices = "Notices could not be loaded."
                return
            }
            notices = await Task.detached(priority: .utility) {
                (try? String(contentsOf: url, encoding: .utf8)) ?? "Notices could not be loaded."
            }.value
        }
    }
}

#if DEBUG
#Preview("Licenses") {
    TailscaleNoticesView()
}
#endif
