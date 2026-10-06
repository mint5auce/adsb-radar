import AppKit
import RadarCore
import SwiftUI
import Testing
@testable import Phosphor

@Suite(.serialized)
struct RadarInteractionTests {
    @Test(arguments: NavigationControl.allCases, [0.0, 60.0])
    @MainActor func navigationPreservesSelection(control: NavigationControl, bottomInset: Double) async throws {
        try await withSurface(bottomInset: bottomInset) { model, host, window in
            model.camera.offset = RadarPoint(east: 20, north: 10)
            model.selectedAddress = "abc123"
            try await settle(host)
            let expected = control.applying(to: model.camera)
            try click(control.point(bottomInset: bottomInset), in: host, window: window)
            try await settle(host)
            #expect(model.camera == expected, "The click must activate its navigation control")
            #expect(model.selectedAddress == "abc123", "Navigation must preserve the selected aircraft")
        }
    }

    @Test(arguments: [NavigationControl.zoomOut, .zoomIn])
    @MainActor func zoomDoesNotSelectAnAircraftUnderTheButton(control: NavigationControl) async throws {
        let camera = RadarCamera()
        let point = control.point()
        // Cover either gesture/button execution order with a contact under the same pixel at both zoom levels.
        let positions = [camera, control.applying(to: camera)].map {
            let scale = $0.pixelsPerNM(width: 800, height: 600)
            return RadarPoint(east: (point.x - 400) / scale, north: (300 - point.y) / scale)
        }
        try await withSurface(positions: positions) { model, host, window in
            #expect(model.aircraftCandidates(at: point).count == 1)
            try click(point, in: host, window: window)
            try await settle(host)
            #expect(model.camera == control.applying(to: camera))
            #expect(model.aircraftCandidates(at: point).count == 1)
            #expect(model.selection == nil, "An aircraft beneath a zoom button must not be selected")
        }
    }

    @Test @MainActor func buttonPaddingDoesNotClickThrough() async throws {
        try await withSurface { model, host, window in
            model.selectedAddress = "abc123"
            try await settle(host)
            let point = CGPoint(x: 731, y: 570) // Inside Zoom out's padding, between the visible symbols.
            let expected = model.camera.zoomed(by: 0.8)
            try click(point, in: host, window: window)
            try await settle(host)
            #expect(model.camera == expected)
            #expect(model.selectedAddress == "abc123")
        }
    }

    @Test @MainActor func uncoveredMapStillSelectsClearsAndPans() async throws {
        try await withSurface { model, host, window in
            try click(CGPoint(x: 400, y: 300), in: host, window: window)
            try await settle(host)
            #expect(model.selectedAddress == "abc123")
            try click(CGPoint(x: 200, y: 300), in: host, window: window)
            try await settle(host)
            #expect(model.selection == nil)
            let camera = model.camera
            try drag(from: CGPoint(x: 200, y: 300), to: CGPoint(x: 300, y: 300), in: host, window: window)
            try await settle(host)
            #expect(model.camera == camera.panned(dx: 100, dy: 0, width: 800, height: 600))
        }
    }

    @Test @MainActor func draggingFromNavigationDoesNotPanTheMap() async throws {
        try await withSurface { model, host, window in
            let camera = model.camera
            try drag(from: NavigationControl.zoomIn.point(), to: CGPoint(x: 500, y: 300), in: host, window: window)
            try await settle(host)
            #expect(model.camera == camera)
        }
    }

    @MainActor private func withSurface(positions: [RadarPoint] = [RadarPoint()], bottomInset: Double = 0,
        perform: (RadarModel, NSView, NSWindow) async throws -> Void) async throws {
        var settings = RadarSettings()
        settings.receiver = SyntheticSource.exampleLocation
        settings.mode = .immediate
        settings.enrichIdentities = false
        settings.mapLayers.routes = false
        settings.mapLayers.airspace = false
        settings.mapLayers.airports = false
        let model = RadarModel(source: NavigationSource(positions: positions),
                               identityStorage: MemoryIdentityStorage(), initialSettings: settings, defaults: isolatedDefaults())
        let host = NSHostingView(rootView: RadarSurface(model: model, bottomInset: bottomInset, openSettings: {}).preferredColorScheme(.dark))
        // An ordered window is required for native SwiftUI event delivery; keep it offscreen and never activate it.
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 800, height: 600),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.orderBack(nil)
        defer { window.orderOut(nil); window.contentView = nil }
        model.start()
        do {
            try await eventually { model.contacts.count == positions.count }
            try await settle(host)
            try await perform(model, host, window)
        } catch {
            await model.shutdown()
            throw error
        }
        await model.shutdown()
    }

    @MainActor private func settle(_ host: NSView) async throws {
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
    }

    @MainActor private func click(_ point: CGPoint, in host: NSView, window: NSWindow) throws {
        try send(.leftMouseDown, at: point, in: host, window: window)
        try send(.leftMouseUp, at: point, in: host, window: window)
    }

    @MainActor private func drag(from start: CGPoint, to end: CGPoint, in host: NSView, window: NSWindow) throws {
        try send(.leftMouseDown, at: start, in: host, window: window)
        try send(.leftMouseDragged, at: end, in: host, window: window)
        try send(.leftMouseUp, at: end, in: host, window: window)
    }

    @MainActor private func send(_ type: NSEvent.EventType, at point: CGPoint, in host: NSView, window: NSWindow) throws {
        let location = host.convert(point, to: nil)
        let event = try #require(NSEvent.mouseEvent(with: type, location: location, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1))
        NSApplication.shared.sendEvent(event)
    }

    enum NavigationControl: CaseIterable {
        case home, zoomOut, zoomIn

        func point(bottomInset: Double = 0) -> CGPoint {
            let offset: Double = switch self { case .home: 100; case .zoomOut: 60; case .zoomIn: 20 }
            return CGPoint(x: 800 - 24 - offset, y: 600 - bottomInset - 24 - 18)
        }

        func applying(to camera: RadarCamera) -> RadarCamera {
            switch self {
            case .home: RadarCamera()
            case .zoomOut: camera.zoomed(by: 0.8)
            case .zoomIn: camera.zoomed(by: 1.25)
            }
        }
    }
}

private actor NavigationSource: AircraftDataSource {
    let positions: [RadarPoint]
    init(positions: [RadarPoint]) { self.positions = positions }
    func start(location: GeographicCoordinate?) async {}
    func stop() async {}
    func poll() async -> ReceptionReading {
        let projection = ReceiverProjection(origin: SyntheticSource.exampleLocation)
        let observations = positions.enumerated().map { index, point in
            AircraftObservation(address: String(format: "%06x", 0xabc123 + index),
                position: projection.coordinate(at: point), positionTime: .now, source: "LOCAL")
        }
        return ReceptionReading(status: .receiving, snapshot: ReceiverSnapshot(observations: observations))
    }
}
