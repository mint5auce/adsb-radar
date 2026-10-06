import AppKit
import SwiftUI

/// Observe secondary clicks without intercepting the radar's drag, zoom or primary-click gestures.
struct MapSecondaryClick: NSViewRepresentable {
    let action: (CGPoint) -> Void
    func makeNSView(context: Context) -> SecondaryClickView { SecondaryClickView(action: action) }
    func updateNSView(_ view: SecondaryClickView, context: Context) { view.action = action }
    static func dismantleNSView(_ view: SecondaryClickView, coordinator: ()) { view.stopMonitoring() }
}

final class SecondaryClickView: NSView {
    var action: (CGPoint) -> Void
    private var monitor: Any?
    override var isFlipped: Bool { true }
    init(action: @escaping (CGPoint) -> Void) { self.action = action; super.init(frame: .zero) }
    required init?(coder: NSCoder) { nil }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopMonitoring()
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            let handled = MainActor.assumeIsolated {
                guard let self, let window = self.window, event.window === window else { return false }
                let point = self.convert(event.locationInWindow, from: nil)
                guard self.bounds.contains(point) else { return false }
                self.action(point)
                return true
            }
            return handled ? nil : event
        }
    }
    func stopMonitoring() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
