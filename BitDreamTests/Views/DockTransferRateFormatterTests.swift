import Foundation
import XCTest
@testable import BitDream

#if os(macOS)
final class DockTransferRateFormatterTests: XCTestCase {
    private let locale = Locale(identifier: "en_US_POSIX")

    func testComponentsUseCompactDecimalUnits() {
        XCTAssertEqual(components(1), DockTransferRateComponents(value: "1", unit: "B"))
        XCTAssertEqual(components(999), DockTransferRateComponents(value: "999", unit: "B"))
        XCTAssertEqual(components(1_000), DockTransferRateComponents(value: "1", unit: "k"))
        XCTAssertEqual(components(19_200_000), DockTransferRateComponents(value: "19.2", unit: "M"))
        XCTAssertEqual(components(4_100_000_000), DockTransferRateComponents(value: "4.1", unit: "G"))
        XCTAssertEqual(components(Int64.max), DockTransferRateComponents(value: "9.2", unit: "E"))
    }

    func testComponentsPromoteValuesThatRoundIntoTheNextUnit() {
        XCTAssertEqual(components(999_500), DockTransferRateComponents(value: "1", unit: "M"))
        XCTAssertEqual(components(999_499), DockTransferRateComponents(value: "999", unit: "k"))
    }

    func testComponentsHonorLocale() {
        let result = DockTransferRateFormatter.components(
            for: 19_200_000,
            locale: Locale(identifier: "fr_FR")
        )

        XCTAssertEqual(result, DockTransferRateComponents(value: "19,2", unit: "M"))
    }

    func testComponentsClampNonpositiveRatesToZero() {
        XCTAssertEqual(components(0), DockTransferRateComponents(value: "0", unit: "B"))
        XCTAssertEqual(components(-1), DockTransferRateComponents(value: "0", unit: "B"))
    }

    private func components(_ bytesPerSecond: Int64) -> DockTransferRateComponents {
        DockTransferRateFormatter.components(for: bytesPerSecond, locale: locale)
    }
}
#endif
