import AppKit
import SwiftUI

enum MapScrollMotion {
    case pan(dx: CGFloat, dy: CGFloat)
    case zoom(factor: Double)
}

/// SwiftUI has no map scroll gesture; observe native events without intercepting clicks or drags.
struct MapScrollInput: NSViewRepresentable {
    let accepts: (CGPoint) -> Bool
    let action: (CGPoint, MapScrollMotion) -> Void

    func makeNSView(context: Context) -> MapScrollView { MapScrollView(accepts: accepts, action: action) }
    func updateNSView(_ view: MapScrollView, context: Context) {
        view.accepts = accepts
        view.action = action
    }
    static func dismantleNSView(_ view: MapScrollView, coordinator: ()) { view.stopMonitoring() }
}

final class MapScrollView: NSView {
    var accepts: (CGPoint) -> Bool
    var action: (CGPoint, MapScrollMotion) -> Void
    private var monitor: Any?
    private var gestureStartedOnMap: Bool?
    override var isFlipped: Bool { true }

    init(accepts: @escaping (CGPoint) -> Bool, action: @escaping (CGPoint, MapScrollMotion) -> Void) {
        self.accepts = accepts
        self.action = action
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { nil }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopMonitoring()
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            let handled = MainActor.assumeIsolated { self?.handle(event) ?? false }
            return handled ? nil : event
        }
    }

    func handle(_ event: NSEvent) -> Bool {
        guard event.type == .scrollWheel else { return false }
        let startsGesture = event.phase.contains(.began) || event.phase.contains(.mayBegin)
        if startsGesture { gestureStartedOnMap = false }
        guard let window, event.window === window, window.attachedSheet == nil else { return false }
        let point = convert(event.locationInWindow, from: nil)
        let permitted = bounds.contains(point) && accepts(point)
        // A scroll beginning in an inspector or control must not become a map pan when the pointer moves.
        let trackpadGesture = event.hasPreciseScrollingDeltas && (!event.phase.isEmpty || !event.momentumPhase.isEmpty)
        if trackpadGesture {
            if startsGesture || gestureStartedOnMap == nil { gestureStartedOnMap = permitted }
            guard gestureStartedOnMap == true else { return false }
        }
        guard permitted else { return false }
        // Native deltas already incorporate macOS scroll direction; do not invert them again.
        if trackpadGesture {
            action(point, .pan(dx: event.scrollingDeltaX, dy: event.scrollingDeltaY))
        } else if event.scrollingDeltaY.isFinite, event.scrollingDeltaY != 0 {
            // Phase-less pixel events can come from high-resolution mouse wheels.
            let steps = event.scrollingDeltaY / (event.hasPreciseScrollingDeltas ? 10 : 1)
            action(point, .zoom(factor: pow(1.1, max(-100, min(100, steps)))))
        }
        return true
    }

    func stopMonitoring() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        gestureStartedOnMap = nil
    }
}
