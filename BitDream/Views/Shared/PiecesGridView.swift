import SwiftUI

struct PiecesGridView: View {
    let pieceCount: Int
    let piecesBitfieldBase64: String
    var rows: Int = 10

    // Visual tuning for macOS
    private let cellSize: CGFloat = 6
    private let cellSpacing: CGFloat = 2

    var body: some View {
        let bitset = decodePiecesBitfield(base64String: piecesBitfieldBase64, pieceCount: pieceCount)

        GeometryReader { geometry in
            let columnsCount = computeColumns(availableWidth: geometry.size.width, cellSize: cellSize, cellSpacing: cellSpacing)
            let totalCells = max(1, rows * columnsCount)
            let buckets = bucketize(bitset: bitset, totalBuckets: totalCells)

            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(cellSize), spacing: cellSpacing, alignment: .leading), count: columnsCount),
                spacing: cellSpacing
            ) {
                ForEach(0..<totalCells, id: \.self) { index in
                    let fraction = index < buckets.count ? buckets[index] : 0
                    Rectangle()
                        .fill(colorForFraction(fraction))
                        .frame(width: cellSize, height: cellSize)
                        .cornerRadius(1.0)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: CGFloat(rows) * (cellSize + cellSpacing))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pieces progress")
    }
}

// MARK: - Helpers

func decodePiecesBitfield(base64String: String, pieceCount: Int) -> [Bool] {
    guard pieceCount > 0, let data = Data(base64Encoded: base64String) else {
        return []
    }

    var result: [Bool] = []
    result.reserveCapacity(pieceCount)

    for byte in data {
        // Big endian bit order: 0x80, 0x40, ..., 0x01
        for bit in stride(from: 7, through: 0, by: -1) {
            if result.count >= pieceCount { break }
            let mask = UInt8(1 << bit)
            result.append((byte & mask) != 0)
        }
        if result.count >= pieceCount { break }
    }

    return result
}

// Buckets the bitset into N buckets and returns a completion fraction per bucket [0,1]
func bucketize(bitset: [Bool], totalBuckets: Int) -> [Double] {
    guard totalBuckets > 0, !bitset.isEmpty else { return Array(repeating: 0, count: max(totalBuckets, 0)) }
    let totalPieces = bitset.count
    var fractions: [Double] = Array(repeating: 0, count: totalBuckets)

    for bucket in 0..<totalBuckets {
        let start = (bucket * totalPieces) / totalBuckets
        let end = ((bucket + 1) * totalPieces) / totalBuckets
        if end <= start { continue }
        var have = 0
        for i in start..<end {
            if bitset[i] { have += 1 }
        }
        let count = max(1, end - start)
        fractions[bucket] = Double(have) / Double(count)
    }
    return fractions
}

func colorForFraction(_ f: Double) -> Color {
    if f <= 0 { return Color.secondary.opacity(0.25) }
    let clamped = max(0.0, min(1.0, f))
    // Continuous accent opacity from 0.2 to 1.0 based on completion fraction
    let minOpacity = 0.2
    let opacity = minOpacity + clamped * (1.0 - minOpacity)
    return Color.accentColor.opacity(opacity)
}

// Compute how many columns fit within the available width (keeps width bounded to container)
private func computeColumns(availableWidth: CGFloat, cellSize: CGFloat, cellSpacing: CGFloat) -> Int {
    let unit = cellSize + cellSpacing
    guard unit > 0 else { return 8 }
    // Ensure at least 8 columns for visual density; width-bounded so it won't overflow
    return max(8, Int(floor((availableWidth + cellSpacing) / unit)))
}
