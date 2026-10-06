import RadarCore
import SwiftUI

/// Keeps bar content mounted for keyboard shortcuts and popovers while sliding it off the map.
struct RadarControlBar<Content: View>: View {
    @Binding var visibility: RadarControlVisibility
    let bar: RadarControlVisibility.Bar
    let heightChanged: (CGFloat) -> Void
    @ViewBuilder let content: () -> Content
    @State private var height: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var visible: Bool { visibility.isVisible(bar) }
    private var isTop: Bool { bar == .top }
    private var alignment: Alignment { isTop ? .top : .bottom }

    var body: some View {
        ZStack(alignment: alignment) {
            content()
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .background(RadarStyle.background)
                .contentShape(Rectangle())
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0; heightChanged($0) }
                .onHover { pointer($0) }
                .offset(y: visible ? 0 : (isTop ? -height : height))
                .allowsHitTesting(visible)
                .accessibilityHidden(!visible)
            // A sibling of the hidden panel keeps its hit testing independent of that panel.
            if visibility.mode == .caretButtons {
                Button {
                    visibility.toggle(bar)
                } label: {
                    Image(systemName: (isTop == visible) ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 44, height: 22)
                        .background(RadarStyle.background)
                        .overlay(Rectangle().stroke(RadarStyle.line))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(visible ? "Hide" : "Show") \(isTop ? "top controls" : "status bar")")
                .offset(y: visible ? (isTop ? height : -height) : 0)
            } else if visibility.mode == .pointerAtEdge, !visible {
                Color.clear.frame(height: 12)
                    .contentShape(Rectangle())
                    .onHover { pointer($0) }
                    .accessibilityHidden(true)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: visible)
    }

    private func pointer(_ inside: Bool) {
        visibility.setPointer(inside: inside, bar: bar, now: ProcessInfo.processInfo.systemUptime)
    }
}
