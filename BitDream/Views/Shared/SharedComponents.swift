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
            
            Text("\(byteCountFormatter.string(fromByteCount: speed))/s")
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
    let ratio: Double
    var size: SpeedChipSize = .compact
    var helpText: String? = nil
    
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
                    .trim(from: 0, to: min(ratio, 1.0))
                    .stroke(ratio >= 1.0 ? .green : .orange, lineWidth: 2)
                    .frame(width: progressRingSize, height: progressRingSize)
                    .rotationEffect(.degrees(-90))
            }
            
            Text(String(format: "%.2f", ratio))
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
