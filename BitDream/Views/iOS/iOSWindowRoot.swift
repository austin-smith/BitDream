import SwiftUI
import SwiftData

#if os(iOS)
/// State is owned inside WindowGroup so each scene has its own workspace.
struct iOSWindowRoot: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @State private var session: iOSWindowSession

    init(session: iOSWindowSession = iOSWindowSession()) {
        _session = State(initialValue: session)
    }

    private var isInMemory: Bool {
        modelContext.container.configurations.allSatisfy(\.isStoredInMemoryOnly)
    }

    var body: some View {
        iOSHapticFeedbackHost {
            ContentView()
                .environmentObject(session.store)
                .onOpenURL(perform: openWidgetURL)
                .task {
                    guard !isInMemory else { return }
                    await HostRepository.shared.bootstrap()
                    guard !Task.isCancelled else { return }
                    ensureStartupConnectionBehaviorApplied(store: session.store, modelContext: modelContext)
                    BackgroundRefreshManager.schedule()
                }
                .onChange(of: scenePhase) { _, phase in
                    guard !isInMemory else { return }
                    if phase == .active, session.store.host?.connectionRoute == "tailscale" {
                        session.store.reconnect()
                    }
                    if phase == .background {
                        BackgroundRefreshManager.schedule()
                    }
                }
        }
    }

    private func openWidgetURL(_ url: URL) {
        guard let serverID = DeepLinkBuilder.serverID(from: url) else { return }
        let descriptor = FetchDescriptor<Host>(predicate: #Predicate { $0.serverID == serverID })
        if let host = try? modelContext.fetch(descriptor).first {
            session.store.setHost(host: host)
        }
    }
}

#if DEBUG
#Preview("Window Workspace") {
    PreviewContainer { environment in
        iOSWindowRoot(session: iOSWindowSession(store: environment.store))
    }
}
#endif
#endif
