import SwiftUI

#if os(iOS)
/// BitDream's tray slides the compact workspace aside and overlays a regular-width
/// workspace. The list and inspector keep their full layout while the tray is open.
struct iOSSidebarTray<Sidebar: View, Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var isOpen: Bool
    var allowsOpeningGesture = true
    @ViewBuilder let sidebar: Sidebar
    @ViewBuilder let content: Content
    @GestureState private var dragOffset: CGFloat = 0
    @State private var availableWidth: CGFloat = 0

    private var direction: CGFloat { layoutDirection == .rightToLeft ? -1 : 1 }
    private var overlaysWorkspace: Bool { horizontalSizeClass == .regular }

    var body: some View {
        let width = min(availableWidth * 0.77, 280)
        let offset = min(max((isOpen ? width : 0) + dragOffset, 0), width)
        let progress = width > 0 ? offset / width : 0

        ZStack(alignment: .leading) {
            sidebar
                .frame(width: width)
                .mask {
                    RoundedRectangle(cornerRadius: overlaysWorkspace ? 32 : 0)
                        .ignoresSafeArea(.container)
                }
                .shadow(color: .black.opacity(overlaysWorkspace ? 0.12 * progress : 0), radius: 12)
                .offset(x: reduceMotion ? 0 : -direction * width * (overlaysWorkspace ? 1 : 0.3) * (1 - progress))
                .opacity(overlaysWorkspace && reduceMotion ? progress : 1)
                .accessibilityHidden(!isOpen)
                .allowsHitTesting(isOpen)
                .zIndex(overlaysWorkspace ? 1 : 0)

            content
                .allowsHitTesting(!isOpen)
                .accessibilityHidden(isOpen)
                .overlay {
                    Button {
                        isOpen = false
                    } label: {
                        (colorScheme == .dark ? Color(white: 0.2) : Color(.systemBackground))
                            .opacity(0.55 * progress)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    // Match the card mask so system bars dim uniformly with the content.
                    .ignoresSafeArea(.container)
                    .accessibilityLabel("Close Menu")
                    .accessibilityHidden(!isOpen)
                    .allowsHitTesting(isOpen)
                    .simultaneousGesture(closeGesture(width: width))
                }
                .overlay(alignment: .leading) {
                    if !isOpen && allowsOpeningGesture {
                        Color.clear
                            .frame(width: 20)
                            .contentShape(.rect)
                            .gesture(openGesture(width: width))
                            .accessibilityHidden(true)
                    }
                }
                .mask {
                    // Include system bars outside the content safe area in the tray's card.
                    RoundedRectangle(cornerRadius: overlaysWorkspace ? 0 : 32 * progress)
                        .ignoresSafeArea(.container)
                }
                .shadow(color: .black.opacity(overlaysWorkspace ? 0 : 0.12 * progress), radius: 12)
                .offset(x: overlaysWorkspace ? 0 : direction * offset)
                .geometryGroup()
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .animation(reduceMotion ? nil : .snappy(duration: 0.32, extraBounce: 0), value: isOpen)
        .accessibilityAction(.escape) { isOpen = false }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
    }

    private func openGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .updating($dragOffset) { value, offset, _ in
                offset = max(0, direction * value.translation.width)
            }
            .onEnded { value in
                isOpen = direction * value.translation.width > width * 0.25
                    || direction * value.predictedEndTranslation.width > width * 0.5
            }
    }

    private func closeGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .updating($dragOffset) { value, offset, _ in
                offset = min(0, direction * value.translation.width)
            }
            .onEnded { value in
                if direction * value.translation.width < -width * 0.25
                    || direction * value.predictedEndTranslation.width < -width * 0.5 {
                    isOpen = false
                }
            }
    }
}

/// The original tray's two-line menu glyph.
struct SidebarToggleGlyph: View {
    private static let lineHeight: CGFloat = 2.5
    private static let spacing: CGFloat = 4.5

    var body: some View {
        Image(size: CGSize(width: 17, height: Self.lineHeight * 2 + Self.spacing)) { context in
            let top = Capsule().path(in: CGRect(x: 0, y: 0, width: 17, height: Self.lineHeight))
            let bottom = Capsule().path(in: CGRect(x: 0, y: Self.lineHeight + Self.spacing, width: 11, height: Self.lineHeight))
            context.fill(top, with: .color(.black))
            context.fill(bottom, with: .color(.black))
        }
        .renderingMode(.template)
    }
}

#if DEBUG
#Preview("Slide-out Tray") {
    @Previewable @State var isOpen = true

    iOSSidebarTray(isOpen: $isOpen) {
        VStack(alignment: .leading) {
            Text("BitDream").font(.title2.bold())
            Label("All Dreams", systemImage: "moon.zzz")
            Spacer()
        }
        .padding()
    } content: {
        NavigationStack {
            List {
                Text("The torrent list uses the available width")
            }
            .navigationTitle("All Dreams")
            .toolbar {
                Button("Menu", systemImage: "sidebar.leading") { isOpen.toggle() }
            }
        }
    }
}
#endif
#endif
