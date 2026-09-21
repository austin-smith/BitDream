import SwiftUI
import XCTest
@testable import BitDream

@MainActor
final class ConnectionPresentationTests: XCTestCase {
    func testRetryBannerKeepsItsHeightWithWrappedErrorsAndLargerText() throws {
        let environment = PreviewEnvironment(scenario: .empty)
        let store = environment.store
        for error in [TransmissionError.timeout, .tailscale(.peerUnavailable)] {
            for width: CGFloat in [320, 420, 720] {
                for textSize in [DynamicTypeSize.large, .accessibility3] {
                    store.connectionState = .failed(error, retryAt: .now.addingTimeInterval(30))
                    let waitingHeight = try bannerHeight(store: store, width: width, textSize: textSize)
                    store.connectionState = .retrying(error)
                    let retryingHeight = try bannerHeight(store: store, width: width, textSize: textSize)
                    XCTAssertEqual(waitingHeight, retryingHeight, "Retry activity must not change the banner height")
                }
            }
        }
    }

    func testStatisticsAppearAfterFirstSnapshotAndRemainDuringRecovery() throws {
        let environment = PreviewEnvironment(scenario: .connected)
        let store = environment.store
        store.lastRefreshAt = nil
        store.connectionState = .connecting
        XCTAssertEqual(try statisticsHeight(environment), 1)

        store.lastRefreshAt = .now
        store.connectionState = .connected
        let loadedHeight = try statisticsHeight(environment)
        XCTAssertGreaterThan(loadedHeight, 1)
        store.connectionState = .retrying(.timeout)
        XCTAssertEqual(try statisticsHeight(environment), loadedHeight)
    }

    private func bannerHeight(store: TransmissionStore, width: CGFloat, textSize: DynamicTypeSize) throws -> Int {
        #if os(iOS)
        let banner = iOSConnectionBannerView(store: store)
        #else
        let banner = macOSConnectionBannerView(store: store)
        #endif
        let renderer = ImageRenderer(content: banner.frame(width: width).environment(\.dynamicTypeSize, textSize))
        return try XCTUnwrap(renderer.cgImage).height
    }

    private func statisticsHeight(_ environment: PreviewEnvironment) throws -> Int {
        let renderer = ImageRenderer(content: VStack(spacing: 0) {
            StatsHeaderView(store: environment.store, onShowStatistics: {})
            Color.clear.frame(height: 1)
        }
        .frame(width: 320)
        .environmentObject(environment.themeManager))
        return try XCTUnwrap(renderer.cgImage).height
    }
}
