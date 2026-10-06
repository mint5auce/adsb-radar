import Testing
import RadarCore

struct ControlVisibilityTests {
    @Test func changingModeImmediatelyResetsBarsButRetainsActiveInteraction() {
        var controls = RadarControlVisibility(mode: .caretButtons, now: 0)
        controls.advance(to: 15)
        controls.setMode(.alwaysVisible, now: 20)
        controls.advance(to: 100)
        #expect(controls.isVisible(.top) && controls.isVisible(.bottom))
        controls.setInteraction(.settings, active: true, bar: .top, now: 101)
        controls.setMode(.pointerAtEdge, now: 102)
        controls.advance(to: 117)
        #expect(controls.isVisible(.top) && !controls.isVisible(.bottom))
        controls.setInteraction(.settings, active: false, bar: .top, now: 120)
        controls.advance(to: 135)
        #expect(!controls.isVisible(.top))
        controls.setMode(.caretButtons, now: 140)
        controls.advance(to: 155)
        #expect(!controls.isVisible(.top) && !controls.isVisible(.bottom))
    }

    @Test func menusAndSheetsHoldTheTopBarUntilEveryInteractionEnds() {
        var controls = RadarControlVisibility(mode: .pointerAtEdge, now: 0)
        controls.setInteraction(.popover, active: true, bar: .top, now: 5)
        controls.setInteraction(.menu, active: true, bar: .top, now: 6)
        controls.setInteraction(.popover, active: false, bar: .top, now: 7)
        controls.setPointer(inside: true, bar: .top, now: 8)
        controls.setPointer(inside: false, bar: .top, now: 9)
        controls.advance(to: 100)
        #expect(controls.isVisible(.top) && !controls.isVisible(.bottom))
        controls.setInteraction(.menu, active: false, bar: .top, now: 100)
        controls.advance(to: 115)
        #expect(!controls.isVisible(.top))
        controls.setInteraction(.settings, active: true, bar: .top, now: 120)
        #expect(controls.isVisible(.top))
        controls.advance(to: 1000)
        #expect(controls.isVisible(.top))
    }

    @Test func caretPinsOnlyItsBarUntilExplicitlyClosed() {
        var controls = RadarControlVisibility(mode: .caretButtons, now: 0)
        controls.advance(to: 15)
        controls.setPointer(inside: true, bar: .top, now: 20)
        #expect(!controls.isVisible(.top))
        controls.toggle(.top)
        controls.setPointer(inside: false, bar: .top, now: 21)
        controls.advance(to: 1000)
        #expect(controls.isVisible(.top) && !controls.isVisible(.bottom))
        #expect(controls.nextDeadline == nil)
        controls.toggle(.top)
        #expect(!controls.isVisible(.top))
    }

    @Test func pointerRevealsOnlyItsBarAndHidesFifteenSecondsAfterLeaving() {
        var controls = RadarControlVisibility(mode: .pointerAtEdge, now: 0)
        controls.advance(to: 15)
        controls.setPointer(inside: true, bar: .top, now: 20)
        controls.advance(to: 100)
        #expect(controls.isVisible(.top) && !controls.isVisible(.bottom))
        controls.setPointer(inside: false, bar: .top, now: 100)
        controls.advance(to: 114.9)
        #expect(controls.isVisible(.top))
        controls.advance(to: 115)
        #expect(!controls.isVisible(.top))
    }

    @Test func startupHidesBothBarsAfterFifteenSecondsExceptAlwaysVisible() {
        for mode in ControlVisibilityMode.allCases {
            var controls = RadarControlVisibility(mode: mode, now: 100)
            #expect(controls.isVisible(.top) && controls.isVisible(.bottom))
            controls.advance(to: 114.9)
            #expect(controls.isVisible(.top) && controls.isVisible(.bottom))
            controls.advance(to: 115)
            #expect(controls.isVisible(.top) == (mode == .alwaysVisible))
            #expect(controls.isVisible(.bottom) == (mode == .alwaysVisible))
            #expect(controls.nextDeadline == nil)
        }
    }
}
