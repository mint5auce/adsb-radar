import AppKit
import RadarCore
import SwiftUI
import Testing
@testable import ADSBRadar

@Suite(.serialized)
struct ReceptionLayoutTests {
    @Test(arguments: [AircraftSourceKind.local, .combined], [800.0, 1200.0])
    @MainActor func receiverFailureDoesNotResizeTheMap(source: AircraftSourceKind, width: Double) async throws {
        let local = ReceptionLayoutSource()
        var settings = RadarSettings()
        settings.receiver = SyntheticSource.exampleLocation
        settings.source = source
        settings.enrichIdentities = false
        let model = RadarModel(sources: [.local: local, .online: ControlledSource(addresses: [], source: "adsb.fi")],
                               identityStorage: MemoryIdentityStorage(), initialSettings: settings, defaults: isolatedDefaults())
        let host = NSHostingView(rootView: RadarWindow(model: model).preferredColorScheme(.dark))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 560),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        model.start()
        try await eventually { model.statuses[.local] == .starting && model.viewportHeight != 600 }
        host.layoutSubtreeIfNeeded()
        let startingHeight = model.viewportHeight
        await local.fail()
        try await eventually { if case .failed = model.statuses[.local] { return true }; return false }
        try await Task.sleep(for: .milliseconds(100))
        host.layoutSubtreeIfNeeded()
        #expect(model.viewportHeight == startingHeight, "Receiver failure must not change the map frame")
        #expect(model.viewportWidth == width)
        await model.shutdown()
        window.contentView = nil
    }
}

private actor ReceptionLayoutSource: AircraftDataSource {
    private var failed = false
    func fail() { failed = true }
    func start(location: GeographicCoordinate?) async {}
    func stop() async {}
    func poll() async -> ReceptionReading {
        ReceptionReading(status: failed ? .failed("No RTL-SDR receiver found. Connect the dongle and retry.") : .starting)
    }
}
