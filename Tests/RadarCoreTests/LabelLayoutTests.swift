import Foundation
import CoreGraphics
import Testing
import RadarCore

struct LabelLayoutTests {
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
