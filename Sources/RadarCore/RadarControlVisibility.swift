import Foundation

public enum ControlVisibilityMode: String, Codable, CaseIterable, Sendable {
    case pointerAtEdge, alwaysVisible, caretButtons

    public var title: String {
        switch self {
        case .pointerAtEdge: "Pointer at edge"
        case .alwaysVisible: "Always visible"
        case .caretButtons: "Caret buttons"
        }
    }
}

/// Presentation timing driven by a monotonic clock, independent of aircraft reception.
public struct RadarControlVisibility: Sendable {
    public enum Bar: CaseIterable, Sendable { case top, bottom }
    public enum Interaction: Hashable, Sendable { case popover, menu, settings }
    public private(set) var mode: ControlVisibilityMode
    private var top = BarState()
    private var bottom = BarState()

    private struct BarState: Sendable {
        var visible = true
        var deadline: TimeInterval?
        var pointerInside = false
        var pinned = false
        var interactions: Set<Interaction> = []

        mutating func scheduleHide(mode: ControlVisibilityMode, now: TimeInterval) {
            deadline = visible && mode != .alwaysVisible && !pinned && !pointerInside && interactions.isEmpty ? now + 15 : nil
        }
    }

    public init(mode: ControlVisibilityMode, now: TimeInterval) {
        self.mode = mode
        top.deadline = mode == .alwaysVisible ? nil : now + 15
        bottom.deadline = top.deadline
    }

    public func isVisible(_ bar: Bar) -> Bool { bar == .top ? top.visible : bottom.visible }
    public var nextDeadline: TimeInterval? { [top.deadline, bottom.deadline].compactMap { $0 }.min() }

    public mutating func setMode(_ mode: ControlVisibilityMode, now: TimeInterval) {
        guard self.mode != mode else { return }
        self.mode = mode
        for bar in Bar.allCases {
            update(bar) { state in
                state.visible = true
                state.pinned = false
                state.scheduleHide(mode: mode, now: now)
            }
        }
    }

    public mutating func setPointer(inside: Bool, bar: Bar, now: TimeInterval) {
        let mode = mode
        update(bar) { state in
            guard state.pointerInside != inside else { return }
            state.pointerInside = inside
            if inside {
                if mode == .pointerAtEdge { state.visible = true }
            }
            state.scheduleHide(mode: mode, now: now)
        }
    }

    public mutating func toggle(_ bar: Bar) {
        guard mode == .caretButtons else { return }
        update(bar) { state in
            guard state.interactions.isEmpty else { return }
            state.visible.toggle()
            state.pinned = state.visible
            state.deadline = nil
        }
    }

    public mutating func setInteraction(_ interaction: Interaction, active: Bool, bar: Bar, now: TimeInterval) {
        let mode = mode
        update(bar) { state in
            guard state.interactions.contains(interaction) != active else { return }
            if active {
                state.interactions.insert(interaction)
                state.visible = true
            } else {
                state.interactions.remove(interaction)
            }
            state.scheduleHide(mode: mode, now: now)
        }
    }

    public mutating func advance(to now: TimeInterval) {
        for bar in Bar.allCases {
            update(bar) { state in
                if let deadline = state.deadline, now >= deadline {
                    state.visible = false
                    state.deadline = nil
                }
            }
        }
    }

    private mutating func update(_ bar: Bar, _ change: (inout BarState) -> Void) {
        switch bar {
        case .top: change(&top)
        case .bottom: change(&bottom)
        }
    }
}
