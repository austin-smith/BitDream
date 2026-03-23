//
//  SharedComponents.swift
//  BitDream
//
//  Reusable UI components shared across iOS and macOS
//

import SwiftUI

// MARK: - SpeedChip Component

enum SpeedDirection {
    case download
    case upload

    var icon: String {
        switch self {
        case .download: return "arrow.down"
        case .upload: return "arrow.up"
        }
    }

    var color: Color {
        switch self {
        case .download: return .blue
        case .upload: return .green
        }
    }

    var helpText: String {
        switch self {
        case .download: return "Download speed"
        case .upload: return "Upload speed"
        }
    }
}

enum SpeedChipStyle {
    case chip      // With background (for headers)
    case plain     // No background (alternative style if needed)
}

enum SpeedChipSize {
    case compact   // For headers and tight spaces
    case regular   // For detail views

    var font: Font {
        switch self {
        case .compact: return .system(.caption, design: .monospaced)
        case .regular: return .system(.footnote, design: .monospaced)
        }
    }

    var iconScale: Image.Scale {
        switch self {
        case .compact: return .small
        case .regular: return .medium
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .compact: return 8
        case .regular: return 10
        }
    }

    var verticalPadding: CGFloat {
        switch self {
        case .compact: return 4
        case .regular: return 6
        }
    }
}

struct SpeedChip: View {
    let speed: Int64
    let direction: SpeedDirection
    var style: SpeedChipStyle = .chip
    var size: SpeedChipSize = .compact

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: direction.icon)
                .imageScale(size.iconScale)
                .foregroundColor(direction.color)

            Text("\(formatByteCount(speed))/s")
                .monospacedDigit()
        }
        .font(size.font)
        .if(style == .chip) { view in
            view
                .padding(.horizontal, size.horizontalPadding)
                .padding(.vertical, size.verticalPadding)
                .background(Color.gray.opacity(0.1))
                .clipShape(Capsule())
        }
        .help(direction.helpText)
    }
}

// MARK: - RatioChip Component

struct RatioChip: View {
    private let ringProgress: Double
    private let displayText: String
    private let showsCompletionColor: Bool
    var size: SpeedChipSize = .compact
    var helpText: String?

    init(ratio: Double, size: SpeedChipSize = .compact, helpText: String? = nil) {
        self.ringProgress = min(ratio, 1.0)
        self.displayText = String(format: "%.2f", ratio)
        self.showsCompletionColor = ratio >= 1.0
        self.size = size
        self.helpText = helpText
    }

    init(uploadRatio: TorrentUploadRatio, size: SpeedChipSize = .compact, helpText: String? = nil) {
        // Torrent ratios can come through as raw sentinel values, so the chip
        // takes the already-interpreted state here.
        self.ringProgress = uploadRatio.ringProgressValue
        self.displayText = uploadRatio.displayText
        self.showsCompletionColor = uploadRatio.usesCompletionColor
        self.size = size
        self.helpText = helpText
    }

    private var progressRingSize: CGFloat {
        switch size {
        case .compact: return 14
        case .regular: return 18
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 2)
                    .frame(width: progressRingSize, height: progressRingSize)

                Circle()
                    .trim(from: 0, to: ringProgress)
                    .stroke(showsCompletionColor ? .green : .orange, lineWidth: 2)
                    .frame(width: progressRingSize, height: progressRingSize)
                    .rotationEffect(.degrees(-90))
            }

            Text(displayText)
                .monospacedDigit()
        }
        .font(size.font)
        .padding(.horizontal, size.horizontalPadding)
        .padding(.vertical, size.verticalPadding)
        .background(Color.gray.opacity(0.1))
        .clipShape(Capsule())
        .help(helpText ?? "Upload ratio")
    }
}

// MARK: - FileProgressView (shared)

/// Progress view with bar and percentage for consistent styling across platforms
struct FileProgressView: View {
    let percentDone: Double
    var showDetailedText: Bool = false
    var bytesCompleted: Int64 = 0
    var totalSize: Int64 = 0

    var body: some View {
        HStack(spacing: 6) {
            ProgressView(value: percentDone)
                .progressViewStyle(.linear)
                .tint(percentDone >= 1.0 ? .green : .blue)
                .frame(minWidth: showDetailedText ? 100 : 50)

            if showDetailedText {
                Text("\(String(format: "%.1f%%", percentDone * 100))")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
            } else {
                Text("\(Int(percentDone * 100))%")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 30, alignment: .trailing)
            }
        }
    }
}

// MARK: - Helper Extensions

extension View {
    /// Conditionally apply a transformation to the view
    @ViewBuilder
    func `if`<Transform: View>(_ condition: Bool, transform: (Self) -> Transform) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
