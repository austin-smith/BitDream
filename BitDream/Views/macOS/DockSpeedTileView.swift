#if os(macOS)
import AppKit
import SwiftUI

struct DockSpeedTileContent: Equatable {
    let downloadSpeed: Int64?
    let uploadSpeed: Int64?
}

@MainActor
final class DockSpeedTileHostingView: NSHostingView<DockSpeedTileView> {
    private var content = DockSpeedTileContent(downloadSpeed: nil, uploadSpeed: nil)

    init(frame: NSRect) {
        let initialContent = DockSpeedTileContent(downloadSpeed: nil, uploadSpeed: nil)
        super.init(rootView: DockSpeedTileView(content: initialContent))
        self.frame = frame
    }

    @available(*, unavailable)
    required init(rootView: DockSpeedTileView) {
        fatalError("Use init(frame:)")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Use init(frame:)")
    }

    func update(content: DockSpeedTileContent) -> Bool {
        guard self.content != content else { return false }
        self.content = content
        rootView = DockSpeedTileView(content: content)
        return true
    }
}

struct DockSpeedTileView: View {
    let content: DockSpeedTileContent

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: geometry.size.width, height: geometry.size.height)

                VStack(spacing: 2) {
                    Spacer(minLength: 0)
                    if let uploadSpeed = content.uploadSpeed {
                        DockSpeedBadge(speed: uploadSpeed, direction: .upload, width: geometry.size.width)
                    }
                    if let downloadSpeed = content.downloadSpeed {
                        DockSpeedBadge(speed: downloadSpeed, direction: .download, width: geometry.size.width)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        let rates = [
            content.downloadSpeed.map { "Download speed, \(formatSpeed($0))" },
            content.uploadSpeed.map { "Upload speed, \(formatSpeed($0))" }
        ].compactMap { $0 }
        return (["BitDream"] + rates).joined(separator: ". ")
    }
}

private struct DockSpeedBadge: View {
    let speed: Int64
    let direction: SpeedDirection
    let width: CGFloat

    var body: some View {
        let formattedSpeed = DockTransferRateFormatter.components(for: speed)

        ZStack {
            Capsule()
                .fill(backgroundColor)

            HStack(spacing: 5) {
                Image(systemName: direction.icon)
                    .font(.system(size: 16, weight: .heavy))
                    .frame(width: 18)

                HStack(spacing: 2) {
                    Text(formattedSpeed.value)
                    Text(formattedSpeed.unit)
                }
                .font(.system(size: 25, weight: .bold, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
        }
        .frame(width: width, height: 30)
        .accessibilityLabel("\(direction.helpText), \(formatSpeed(speed))")
    }

    private var backgroundColor: Color {
        switch direction {
        case .download:
            return Color(red: 0 / 255, green: 116 / 255, blue: 232 / 255)
        case .upload:
            return Color(red: 32 / 255, green: 140 / 255, blue: 64 / 255)
        }
    }
}
#endif
