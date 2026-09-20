import AuthenticationServices
import SwiftUI

@MainActor
@Observable
final class TailscaleSetupModel {
    private(set) var snapshot: TailscaleSnapshot?
    private(set) var isWorking = false
    var authorizationURL: URL?
    var errorMessage: String?
    private let service: EmbeddedTailscaleService

    init(service: EmbeddedTailscaleService = .shared) { self.service = service }

    var isSignedIn: Bool { snapshot?.isSignedIn == true }

    // Restore the app’s saved node identity even when this server has no account yet.
    func refresh() async {
        guard !isWorking else { return }
        do {
            let value = try await service.status(startIfNeeded: true)
            snapshot = value
            errorMessage = nil
            if value.isReady { authorizationURL = nil }
            if authorizationURL != nil, let url = value.authorizationURL { authorizationURL = url }
        } catch is CancellationError {
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signIn() async {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            var value = try await service.beginLogin()
            let deadline = ContinuousClock.now.advanced(by: .seconds(20))
            while value.authorizationURL == nil && !value.isReady {
                guard ContinuousClock.now < deadline else { throw TailscaleError.unavailable }
                try await Task.sleep(for: .milliseconds(500))
                value = try await service.status()
            }
            snapshot = value
            authorizationURL = value.authorizationURL
        } catch is CancellationError {
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() async {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
        authorizationURL = nil
        defer { isWorking = false }
        do {
            try await service.signOut()
            snapshot = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct TailscaleConnectionSection: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @Bindable var form: ServerFormModel
    @Bindable var model: TailscaleSetupModel
    @State private var isConfirmingSignOut = false
    @State private var action: Action?

    private struct PollingContext: Equatable {
        let route: String
        let phase: ScenePhase
        let isAuthorizing: Bool
    }

    private enum Action: Equatable { case signIn, signOut }

    var body: some View {
        Section {
            Picker("Connect using", selection: $form.values.connectionRoute) {
                Text("System Network").tag("system")
                Text("Tailscale").tag("tailscale")
            }
            if form.values.connectionRoute == "tailscale" {
                tailscaleControls
            }
        } header: {
            Text("Network")
        }
        .task(id: PollingContext(route: form.values.connectionRoute, phase: scenePhase,
                                 isAuthorizing: model.authorizationURL != nil)) {
            guard form.values.connectionRoute == "tailscale",
                  scenePhase == .active || model.authorizationURL != nil else { return }
            while !Task.isCancelled {
                await model.refresh()
                if form.values.tailscaleAccountID == nil, model.snapshot?.isReady == true {
                    form.values.tailscaleAccountID = model.snapshot?.accountID
                }
                do { try await Task.sleep(for: .seconds(model.authorizationURL == nil ? 5 : 1)) } catch { return }
            }
        }
        .task(id: action) {
            guard let action else { return }
            switch action {
            case .signIn: await model.signIn()
            case .signOut:
                await model.signOut()
                if model.errorMessage == nil { form.values.tailscaleAccountID = nil }
            }
            self.action = nil
        }
        .task(id: model.authorizationURL) {
            guard let url = model.authorizationURL else { return }
            do {
                _ = try await webAuthenticationSession.authenticate(
                    using: url, callback: .customScheme("bitdream"),
                    preferredBrowserSession: .shared, additionalHeaderFields: [:]
                )
            } catch {
                guard !Task.isCancelled else { return }
                // Authentication completion is observed from the node, not an
                // invented redirect. Closing the browser does not prove failure.
                model.authorizationURL = nil
                await model.refresh()
            }
        }
        .confirmationDialog("Sign out of Tailscale?", isPresented: $isConfirmingSignOut) {
            Button("Sign Out", role: .destructive) { action = .signOut }
        } message: {
            Text("This disconnects every server using BitDream’s Tailscale identity on this device. Your saved servers remain. Device removal is managed in the Tailscale admin console.")
        }
    }

    @ViewBuilder
    private var tailscaleControls: some View {
        if !model.isSignedIn {
            HStack(spacing: 8) {
                Button {
                    action = .signIn
                } label: {
                    Text("Sign in to Tailscale")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                }
                    #if os(iOS)
                    .buttonStyle(.automatic)
                    #else
                    .buttonStyle(.borderless)
                    #endif
                    .disabled(action != nil || model.isWorking || model.authorizationURL != nil)
                if model.isWorking && action == .signIn {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                        .accessibilityLabel("Preparing sign-in")
                }
            }
        }
        if let snapshot = model.snapshot, snapshot.isSignedIn {
            if let name = snapshot.accountName {
                LabeledContent("Tailnet") {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(name)
                            .foregroundStyle(.primary)
                        Text(snapshot.statusDescription)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
                }
                #if os(macOS)
                .labeledContentStyle(TailnetLabeledContentStyle())
                #endif
                .accessibilityElement(children: .combine)
            } else {
                LabeledContent("Status", value: snapshot.statusDescription)
            }
            accountControls
                .disabled(model.isWorking || model.snapshot?.isReady != true)
            HStack(spacing: 8) {
                Button(role: .destructive) {
                    isConfirmingSignOut = true
                } label: {
                    Text("Sign Out…")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                }
                    #if os(iOS)
                    .buttonStyle(.automatic)
                    #else
                    .buttonStyle(.borderless)
                    .tint(.red)
                    #endif
                    .disabled(action != nil || model.isWorking)
                if model.isWorking && action == .signOut {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                        .accessibilityLabel("Signing out")
                }
            }
        }
        if let message = model.errorMessage {
            Text(message).foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var accountControls: some View {
        if let accountID = model.snapshot?.accountID, accountID != form.values.tailscaleAccountID {
            Button("Use This Tailscale Identity for This Server") {
                form.values.tailscaleAccountID = accountID
            }
        }
    }
}

#if os(macOS)
private struct TailnetLabeledContentStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center) {
            configuration.label
            Spacer()
            configuration.content
        }
    }
}
#endif

#if DEBUG
#Preview("Network") {
    @Previewable @State var form = ServerFormModel()
    @Previewable @State var model = TailscaleSetupModel()
    Form {
        TailscaleConnectionSection(form: form, model: model)
    }
}
#endif
