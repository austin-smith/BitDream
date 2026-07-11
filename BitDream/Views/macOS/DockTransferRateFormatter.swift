#if os(macOS)
import Foundation

struct DockTransferRateComponents: Equatable {
    let value: String
    let unit: String
}

enum DockTransferRateFormatter {
    private struct UnitScale {
        let divisor: Double
        let suffix: String
    }

    private static let units = [
        UnitScale(divisor: 1, suffix: "B"),
        UnitScale(divisor: 1_000, suffix: "k"),
        UnitScale(divisor: 1_000_000, suffix: "M"),
        UnitScale(divisor: 1_000_000_000, suffix: "G"),
        UnitScale(divisor: 1_000_000_000_000, suffix: "T"),
        UnitScale(divisor: 1_000_000_000_000_000, suffix: "P"),
        UnitScale(divisor: 1_000_000_000_000_000_000, suffix: "E")
    ]

    static func components(
        for bytesPerSecond: Int64,
        locale: Locale = .autoupdatingCurrent
    ) -> DockTransferRateComponents {
        let bytesPerSecond = max(0, bytesPerSecond)
        guard bytesPerSecond > 0 else { return DockTransferRateComponents(value: "0", unit: "B") }

        var unitIndex = units.lastIndex { Double(bytesPerSecond) >= $0.divisor } ?? 0
        var scaledValue = roundedScaledValue(bytesPerSecond, unitIndex: unitIndex)

        if scaledValue >= 1_000, unitIndex < units.index(before: units.endIndex) {
            unitIndex += 1
            scaledValue = roundedScaledValue(bytesPerSecond, unitIndex: unitIndex)
        }

        let fractionDigits = scaledValue < 100 ? 1 : 0
        let value = scaledValue.formatted(
            .number
                .locale(locale)
                .precision(.fractionLength(0...fractionDigits))
        )
        return DockTransferRateComponents(value: value, unit: units[unitIndex].suffix)
    }

    private static func roundedScaledValue(_ bytesPerSecond: Int64, unitIndex: Int) -> Double {
        let scaledValue = Double(bytesPerSecond) / units[unitIndex].divisor
        let roundingScale = scaledValue < 100 ? 10.0 : 1.0
        return (scaledValue * roundingScale).rounded() / roundingScale
    }
}
#endif
