import Foundation
import Testing
import RadarCore

struct SyntheticSourceTests {
    @Test func slowSweepStillShowsTheWholeTestLifecycleWithShortFreshnessThresholds() async throws {
        let clock = SyntheticClock()
        var settings = RadarSettings()
        settings.receiver = SyntheticSource.exampleLocation
        settings.sweepSeconds = 30
        settings.staleSeconds = 3
        settings.removalSeconds = 6
        let source = SyntheticSource(scenario: .test, timing: settings, now: { clock.now })
        await source.start(location: settings.receiver)
        var session = RadarSession(startedAt: clock.now)
        var transitions: [String] = []
        for tick in 0...2000 {
            if tick.isMultiple(of: 10) { session.ingest(try #require(await source.poll().snapshot)) }
            let contact = session.advance(to: clock.now, settings: settings).first { $0.id == "f00001" }
            let state = contact.map { $0.stale ? "stale" : "fresh" } ?? "removed"
            if (contact != nil || !transitions.isEmpty), transitions.last != state { transitions.append(state) }
            clock.advance(0.1)
        }
        #expect(Array(transitions.prefix(4)) == ["fresh", "stale", "removed", "fresh"])
        await source.stop()
    }

    @Test func testScenarioExercisesRealPositionAgeThroughTheNormalSession() async throws {
        let clock = SyntheticClock()
        var settings = RadarSettings()
        settings.mode = .immediate
        settings.staleSeconds = 3
        settings.removalSeconds = 6
        let source = SyntheticSource(scenario: .test, timing: settings, now: { clock.now })
        await source.start(location: nil)
        var session = RadarSession(startedAt: clock.now)
        let first = try #require(await source.poll().snapshot)
        #expect(first.heardWithoutPosition == 1)
        #expect(first.observations.contains { $0.position != nil && $0.altitude == nil && $0.speedKnots == nil })
        session.ingest(first)
        #expect(session.advance(to: clock.now, settings: settings).count == 11)
        clock.advance(8)
        session.ingest(try #require(await source.poll().snapshot))
        let moving = try #require(session.advance(to: clock.now, settings: settings).first)
        #expect(moving.trail.count == 2)
        clock.advance(3)
        session.ingest(try #require(await source.poll().snapshot))
        let stale = try #require(session.advance(to: clock.now, settings: settings).first { $0.id == "f00001" })
        #expect(stale.stale)
        #expect(stale.positionAge == 3)
        #expect(stale.observation.position == moving.observation.position)
        clock.advance(3)
        session.ingest(try #require(await source.poll().snapshot))
        #expect(!session.advance(to: clock.now, settings: settings).contains { $0.id == "f00001" })
        clock.advance(8)
        session.ingest(try #require(await source.poll().snapshot))
        let recovered = try #require(session.advance(to: clock.now, settings: settings).first { $0.id == "f00001" })
        #expect(!recovered.stale)
        #expect(recovered.positionAge == 0)
        #expect(recovered.trail.count == 1)
        await source.stop()
    }

    @Test(arguments: [25, 100, 250]) func demoCountAndOriginAreConfigurable(_ count: Int) async throws {
        let origin = try #require(GeographicCoordinate(latitude: -33.9, longitude: 151.2))
        let source = SyntheticSource(scenario: .demo, demoCount: count)
        await source.start(location: origin)
        let snapshot = try #require(await source.poll().snapshot)
        #expect(snapshot.observations.count == count)
        #expect(Set(snapshot.observations.map(\.address)).count == count)
        for observation in snapshot.observations {
            let position = try #require(observation.position)
            let point = ReceiverProjection(origin: origin).project(position)
            #expect(hypot(point.east, point.north) < 85)
        }
        await source.stop()
    }

    @Test func demoMovesCleanAircraftAndRestartRepeatsRoutesWithCurrentTimestamps() async throws {
        let clock = SyntheticClock()
        let source = SyntheticSource(scenario: .demo, now: { clock.now })
        await source.start(location: nil)
        let first = try #require(await source.poll().snapshot)
        #expect(first.observations.count == 100)
        #expect(first.heardWithoutPosition == 0)
        #expect(first.observations.allSatisfy {
            $0.callsign != nil && $0.altitude != nil && $0.speedKnots != nil &&
            $0.directionDegrees != nil && $0.positionTime == clock.now && $0.source == "SYNTHETIC DEMO"
        })
        clock.advance(10)
        let moved = try #require(await source.poll().snapshot)
        #expect(moved.observations.first?.position != first.observations.first?.position)
        await source.stop()
        #expect(await source.poll().status == .stopped)
        await source.start(location: nil)
        let restarted = try #require(await source.poll().snapshot)
        #expect(restarted.observations.map(\.position) == first.observations.map(\.position))
        #expect(restarted.observations.first?.positionTime == clock.now)
    }
}

private final class SyntheticClock: @unchecked Sendable {
    private let lock = NSLock()
    private var time = Date(timeIntervalSince1970: 1000)
    var now: Date { lock.withLock { time } }
    func advance(_ seconds: Double) { lock.withLock { time.addTimeInterval(seconds) } }
}
