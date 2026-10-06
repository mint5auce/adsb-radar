import Foundation
import CoreGraphics
import Testing
import RadarCore

struct LabelLayoutTests {
    @Test func selectedLabelFindsSpaceBeyondADenseGridWithoutCoveringMarkers() throws {
        let layout = AircraftLabelLayout()
        var candidates: [AircraftLabelCandidate] = []
        for x in -4...4 {
            for y in -4...4 {
                let point = CGPoint(x: Double(220 + x * 16), y: Double(170 + y * 16))
                candidates.append(AircraftLabelCandidate(id: "\(x):\(y)", point: point,
                    size: CGSize(width: 80, height: 24), selected: x == 0 && y == 0))
            }
        }
        for mode in AircraftLabelMode.allCases {
            let labels = layout.place(candidates, in: CGRect(x: 0, y: 0, width: 440, height: 340), mode: mode)
            let selected = try #require(labels["0:0"])
            #expect(candidates.allSatisfy { !selected.insetBy(dx: -4, dy: -3).contains($0.point) })
        }
    }
    @Test func automaticLabelsKeepTheSelectedContactReadableInADenseCluster() {
        let layout = AircraftLabelLayout()
        let candidates = (0..<12).map {
            AircraftLabelCandidate(id: "\($0)", point: CGPoint(x: 100, y: 100), size: CGSize(width: 70, height: 24), selected: $0 == 11)
        }
        let labels = layout.place(candidates, in: CGRect(x: 0, y: 0, width: 240, height: 200), mode: .automatic)
        #expect(labels["11"] != nil)
        #expect(labels.count < candidates.count)
        let rectangles = Array(labels.values)
        for i in rectangles.indices {
            for j in rectangles.indices where j > i { #expect(!rectangles[i].intersects(rectangles[j])) }
        }
    }

    @Test func labelModesAndPlacementContinuityDoNotDependOnInputOrder() {
        let layout = AircraftLabelLayout()
        let candidates = [
            AircraftLabelCandidate(id: "selected", point: CGPoint(x: 195, y: 145), size: CGSize(width: 70, height: 24), selected: true),
            AircraftLabelCandidate(id: "other", point: CGPoint(x: 50, y: 50), size: CGSize(width: 70, height: 24))
        ]
        let viewport = CGRect(x: 0, y: 0, width: 200, height: 150)
        let first = layout.place(candidates, in: viewport, mode: .automatic)
        #expect(first.count == 2)
        #expect(first == layout.place(candidates.reversed(), in: viewport, mode: .automatic))
        #expect(first["selected"].map { viewport.contains($0) } == true)
        #expect(Set(layout.place(candidates, in: viewport, mode: .selectedOnly).keys) == ["selected"])
        #expect(layout.place(candidates, in: viewport, mode: .all).count == 2)
    }

    @Test func selectedLabelsAvoidReservedMapControls() throws {
        let reserved = [CGRect(x: 0, y: 20, width: 240, height: 40), CGRect(x: 120, y: 150, width: 120, height: 40)]
        let candidates = [AircraftLabelCandidate(id: "selected", point: CGPoint(x: 225, y: 40), size: CGSize(width: 70, height: 24), selected: true)]
        let viewport = CGRect(x: 0, y: 0, width: 240, height: 200)
        let label = try #require(AircraftLabelLayout().place(candidates, in: viewport, mode: .automatic, reserved: reserved)["selected"])
        #expect(viewport.contains(label))
        #expect(reserved.allSatisfy { !$0.intersects(label) })
    }

    @Test func freshLabelsWinContestedSpaceAndZoomRevealsMoreWithoutShrinkingText() {
        let layout = AircraftLabelLayout()
        let size = CGSize(width: 80, height: 24)
        let candidates = [
            AircraftLabelCandidate(id: "stale", point: CGPoint(x: 90, y: 40), size: size, stale: true, homeDistance: 1),
            AircraftLabelCandidate(id: "far", point: CGPoint(x: 90, y: 40), size: size, homeDistance: 50),
            AircraftLabelCandidate(id: "near", point: CGPoint(x: 90, y: 40), size: size, homeDistance: 5)
        ]
        let labels = layout.place(candidates, in: CGRect(x: 0, y: 0, width: 180, height: 75), mode: .automatic)
        #expect(Set(labels.keys) == ["near"])
        let zoomed = [
            AircraftLabelCandidate(id: "stale", point: CGPoint(x: 180, y: 140), size: size, stale: true),
            AircraftLabelCandidate(id: "far", point: CGPoint(x: 270, y: 50), size: size),
            AircraftLabelCandidate(id: "near", point: CGPoint(x: 90, y: 50), size: size)
        ]
        let expanded = layout.place(zoomed, in: CGRect(x: 0, y: 0, width: 360, height: 200), mode: .automatic)
        #expect(expanded.count == 3)
        #expect(expanded.values.allSatisfy { $0.size == size })
    }

    @Test @MainActor func presentationChoicesSurviveRelaunchAndOlderPreferencesKeepTheirValues() throws {
        let name = "label-preferences-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(Data(#"{"mode":"immediate","trailSeconds":90}"#.utf8), forKey: "radar-settings")
        let preferences = RadarPreferences(defaults: defaults)
        var settings = preferences.load()
        #expect(settings.labelMode == .automatic && settings.trailMode == .selected && settings.directionVectors)
        #expect(settings.mode == .immediate && settings.trailSeconds == 90)
        settings.labelMode = .selectedOnly; settings.trailMode = .none; settings.directionVectors = false
        preferences.save(settings)
        #expect(RadarPreferences(defaults: defaults).load() == settings)
        #expect(!AircraftTrailMode.selected.shows(selected: false))
        #expect(AircraftTrailMode.all.shows(selected: false))
    }
}
