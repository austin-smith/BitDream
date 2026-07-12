import Foundation

struct CompactByteCountComponents {
    let value: String
    let unit: String
}

private let byteCountFormatStyle = ByteCountFormatStyle(
    style: .file,
    allowedUnits: [.kb, .mb, .gb, .tb],
    spellsOutZero: false,
    includesActualByteCount: false
)

/// Shared byte formatting helper using modern format style.
/// Round up 1 to 999 bytes to 1 kB.
public func formatByteCount(_ bytes: Int64) -> String {
    if bytes == 0 {
        return "0 kB"
    }
    return String(formattedByteCount(bytes).characters)
}

/// Shared speed formatting helper (bytes per second -> short string).
func formatSpeed(_ bytesPerSecond: Int64) -> String {
    let base = formatByteCount(bytesPerSecond)
    return "\(base)/s"
}

func formatCompactByteCount(_ bytes: Int64) -> CompactByteCountComponents {
    let formatted = formattedByteCount(bytes)
    var value = ""
    var unit = ""

    for run in formatted.runs {
        let text = String(formatted[run.range].characters)
        switch run.byteCount {
        case .value:
            value += text
        case let .unit(byteCountUnit):
            unit = compactSuffix(for: byteCountUnit)
        default:
            break
        }
    }

    return CompactByteCountComponents(value: value, unit: unit)
}

private func formattedByteCount(_ bytes: Int64) -> AttributedString {
    let normalizedBytes: Int64
    if bytes == 0 {
        normalizedBytes = 0
    } else if bytes > 0 && bytes < 1_000 {
        normalizedBytes = 1_000
    } else {
        normalizedBytes = bytes
    }
    return byteCountFormatStyle.attributed.format(normalizedBytes)
}

private func compactSuffix(
    for unit: AttributeScopes.FoundationAttributes.ByteCountAttribute.Unit
) -> String {
    switch unit {
    case .byte: "B"
    case .kb: "k"
    case .mb: "M"
    case .gb: "G"
    case .tb: "T"
    case .pb: "P"
    case .eb: "E"
    case .zb: "Z"
    case .yb: "Y"
    @unknown default: ""
    }
}
