import Foundation
import XCTest
@testable import BitDream

final class FormattingTests: XCTestCase {

    // MARK: - formatCompactByteCount

    func testZeroFallsBackToByteUnit() {
        let components = formatCompactByteCount(0)
        XCTAssertEqual(components.value, "0")
        XCTAssertEqual(components.unit, "B")
    }

    func testSubKilobyteValuesRoundUpToOneKilobyte() {
        for bytes: Int64 in [1, 500, 999] {
            let components = formatCompactByteCount(bytes)
            XCTAssertEqual(components.value, "1", "expected \(bytes) bytes to round up to 1 k")
            XCTAssertEqual(components.unit, "k")
        }
    }

    func testWholeKilobyteValues() {
        XCTAssertEqual(formatCompactByteCount(1_000).value, "1")
        XCTAssertEqual(formatCompactByteCount(1_000).unit, "k")
        XCTAssertEqual(formatCompactByteCount(33_000).value, "33")
        XCTAssertEqual(formatCompactByteCount(33_000).unit, "k")
        XCTAssertEqual(formatCompactByteCount(311_000).value, "311")
        XCTAssertEqual(formatCompactByteCount(311_000).unit, "k")
    }

    func testRollsOverToMegabytesNearUnitBoundary() {
        let components = formatCompactByteCount(999_500)
        XCTAssertEqual(components.value, "1")
        XCTAssertEqual(components.unit, "M")
    }

    func testFractionalValuesUseLocaleDecimalSeparator() {
        let separator = Locale.current.decimalSeparator ?? "."
        XCTAssertEqual(formatCompactByteCount(1_700_000).value, "1\(separator)7")
        XCTAssertEqual(formatCompactByteCount(1_700_000).unit, "M")
    }

    func testLargerUnitSuffixes() {
        let separator = Locale.current.decimalSeparator ?? "."
        XCTAssertEqual(formatCompactByteCount(2_500_000_000).value, "2\(separator)5")
        XCTAssertEqual(formatCompactByteCount(2_500_000_000).unit, "G")
        XCTAssertEqual(formatCompactByteCount(3_200_000_000_000).value, "3\(separator)2")
        XCTAssertEqual(formatCompactByteCount(3_200_000_000_000).unit, "T")
    }

    // MARK: - formatByteCount / formatSpeed

    func testZeroUsesKilobyteUnit() {
        XCTAssertEqual(formatByteCount(0), "0 kB")
        XCTAssertEqual(formatSpeed(0), "0 kB/s")
    }

    func testFormatByteCountRoundsSubKilobyteUpToOneKilobyte() {
        XCTAssertEqual(formatByteCount(500), formatByteCount(1_000))
    }

    func testFormatSpeedAppendsPerSecondSuffix() {
        XCTAssertTrue(formatSpeed(33_000).hasSuffix("/s"))
        XCTAssertTrue(formatSpeed(33_000).hasPrefix(formatByteCount(33_000)))
    }

    // MARK: - Statistics formatting

    func testTransferRatioUsesTwoFractionDigits() {
        let separator = Locale.current.decimalSeparator ?? "."

        XCTAssertEqual(
            formatTransferRatio(uploadedBytes: 3, downloadedBytes: 2),
            "1\(separator)50"
        )
    }

    func testTransferRatioIsZeroWithoutDownloadedBytes() {
        let separator = Locale.current.decimalSeparator ?? "."

        XCTAssertEqual(
            formatTransferRatio(uploadedBytes: 10, downloadedBytes: 0),
            "0\(separator)00"
        )
    }

    func testActiveDurationClampsNegativeValuesToZero() {
        XCTAssertEqual(formatActiveDuration(-1), "0s")
        XCTAssertEqual(formatActiveDuration(0), "0s")
    }

    func testActiveDurationPreservesAbbreviatedDateComponentsStyle() {
        XCTAssertEqual(formatActiveDuration(90_061), "1d 1h 1m 1s")
    }
}
