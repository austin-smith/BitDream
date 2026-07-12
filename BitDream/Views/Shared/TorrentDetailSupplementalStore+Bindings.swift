import SwiftUI

@MainActor
extension TorrentDetailSupplementalStore {
    func load(
        for identity: TorrentDetailIdentity,
        using store: TransmissionStore,
        showingError: Binding<Bool>,
        errorMessage: Binding<String>
    ) async -> RefreshOutcome {
        await load(
            for: identity,
            using: store,
            onError: makeTransmissionBindingErrorHandler(
                isPresented: showingError,
                message: errorMessage
            )
        )
    }

    func refresh(
        for identity: TorrentDetailIdentity,
        using store: TransmissionStore,
        showingInitialLoadError: Binding<Bool>,
        errorMessage: Binding<String>
    ) async -> RefreshOutcome {
        await refresh(
            for: identity,
            using: store,
            onInitialLoadError: makeTransmissionBindingErrorHandler(
                isPresented: showingInitialLoadError,
                message: errorMessage
            )
        )
    }

    func observeRefreshes(
        for identity: TorrentDetailIdentity,
        using store: TransmissionStore,
        showingInitialLoadError: Binding<Bool>,
        errorMessage: Binding<String>
    ) async {
        await observeRefreshes(
            for: identity,
            using: store,
            onInitialLoadError: makeTransmissionBindingErrorHandler(
                isPresented: showingInitialLoadError,
                message: errorMessage
            )
        )
    }

    func replaceLoad(
        for identity: TorrentDetailIdentity,
        using store: TransmissionStore,
        showingError: Binding<Bool>,
        errorMessage: Binding<String>
    ) {
        replaceLoad(
            for: identity,
            using: store,
            onError: makeTransmissionBindingErrorHandler(
                isPresented: showingError,
                message: errorMessage
            )
        )
    }

    func loadIfIdle(
        for identity: TorrentDetailIdentity,
        using store: TransmissionStore,
        showingError: Binding<Bool>,
        errorMessage: Binding<String>
    ) async -> RefreshOutcome {
        await loadIfIdle(
            for: identity,
            using: store,
            onError: makeTransmissionBindingErrorHandler(
                isPresented: showingError,
                message: errorMessage
            )
        )
    }
}
