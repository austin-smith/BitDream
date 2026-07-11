import Foundation
import SwiftUI

struct HostRepositoryProvider: Sendable {
    let resolve: @MainActor @Sendable () -> any HostPersisting

    static let live = Self(resolve: { HostRepository.shared })
}

extension EnvironmentValues {
    @Entry var appUserDefaults: UserDefaults = .standard
    @Entry var hostRepositoryProvider: HostRepositoryProvider = .live
}
