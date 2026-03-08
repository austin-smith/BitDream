import Foundation

/// Shared byte formatting helper using modern format style.
/// Round up 1 to 999 bytes to 1 kB.
public func formatByteCount(_ bytes: Int64) -> String {
    if bytes == 0 {
        return "0 kB"
    }
    if bytes > 0 && bytes < 1_000 {
        return "1 kB"
    }
    return bytes.formatted(
        ByteCountFormatStyle(
            style: .file,
            allowedUnits: [.kb, .mb, .gb, .tb],
            spellsOutZero: false,
            includesActualByteCount: false
        )
    )
}

/// Shared speed formatting helper (bytes per second -> short string).
func formatSpeed(_ bytesPerSecond: Int64) -> String {
    let base = formatByteCount(bytesPerSecond)
    return "\(base)/s"
}
