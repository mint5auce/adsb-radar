import AppKit
import Combine
import RadarCore
import SwiftUI
import Testing
@testable import Phosphor

// Native menu tracking runs its own AppKit event loop and must run independently of other UI tests.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["PHOSPHOR_NATIVE_MENU_TEST"] == "1"))
struct PresentationMenuTests {
    @Test(arguments: [800.0, 1200.0])
    @MainActor func radarRedrawsPreserveTrackedSubmenus(width: Double) async throws {
        var settings = RadarSettings()
        settings.enrichIdentities = false
        let model = RadarModel(identityStorage: MemoryIdentityStorage(), initialSettings: settings, defaults: isolatedDefaults())
        let host = NSHostingView(rootView: RadarWindow(model: model))
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: width, height: 560),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.orderBack(nil)
        defer { window.orderOut(nil); window.contentView = nil }
        try await Task.sleep(for: .milliseconds(100))
        host.layoutSubtreeIfNeeded()
        func buttons(_ view: NSView) -> [NSPopUpButton] {
            (view as? NSPopUpButton).map { [$0] } ?? view.subviews.flatMap(buttons)
        }
        let button = try #require(buttons(host).first { $0.title == "VIEW" })
        func flattenedItems(_ menu: NSMenu) -> [NSMenuItem] {
            menu.items.flatMap { [$0] + ($0.submenu.map(flattenedItems) ?? []) }
        }
        var trackedMenu: NSMenu?
        var originalItems: [NSMenuItem] = []
        let observer = NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification).sink { notification in
            guard let menu = notification.object as? NSMenu else { return }
            trackedMenu = menu
            originalItems = flattenedItems(menu)
        }
        var ticks = 0
        var submenuChanges = 0
        let changes = NotificationCenter.default.publisher(for: NSMenu.didChangeItemNotification).sink { notification in
            guard ticks > 0, let menu = notification.object as? NSMenu, menu === trackedMenu,
                  let index = notification.userInfo?["NSMenuItemIndex"] as? Int,
                  menu.items.indices.contains(index), menu.items[index].submenu != nil else { return }
            submenuChanges += 1
        }
        // Main-actor Tasks cannot advance while performClick runs the menu's nested event loop.
        let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect().sink { _ in
            ticks += 1
            if ticks == 1 { model.camera.radiusNM += 1 }
            if ticks == 3 { trackedMenu?.cancelTracking() }
        }
        defer { observer.cancel(); timer.cancel(); changes.cancel() }
        button.performClick(nil)
        #expect(ticks >= 3, "The menu must stay open across a radar redraw")
        let menu = try #require(trackedMenu)
        #expect(submenuChanges == 0, "Radar redraws must not mutate tracked submenus and reset hover")
        #expect(flattenedItems(menu).count == originalItems.count)
        #expect(zip(originalItems, flattenedItems(menu)).allSatisfy { $0 === $1 })
    }
}
