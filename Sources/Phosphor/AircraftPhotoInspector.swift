import RadarCore
import SwiftUI

struct AircraftPhotoInspector: View {
    let lookup: AircraftPhotoLookup
    let address: String
    let registration: String?
    let enabled: Bool
    let fullColour: Bool
    let viewport: CGSize
    @Environment(\.scenePhase) private var scenePhase
    @State private var imageIntersectsViewport = false
    @State private var windowVisible = false

    private struct Request: Equatable {
        let address: String
        let registration: String?
        let enabled: Bool
    }
    private var heading: String {
        switch lookup.status {
        case .lookingUp: "PHOTO - LOOKING UP…"
        case .available: "PHOTO"
        case .unavailable: "PHOTO - UNAVAILABLE"
        case .disabled: "PHOTO - DISABLED"
        }
    }

    var body: some View {
        DisclosureGroup(isExpanded: Binding(get: { lookup.isExpanded }, set: { lookup.setExpanded($0) })) {
            if let photo = lookup.photo {
                VStack(alignment: .leading, spacing: 8) {
                    imageArea(photo)
                    Text("© " + photo.photographer)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(RadarStyle.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text(explanation)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(RadarStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } label: {
            Text(heading).font(.system(size: 10, design: .monospaced))
                .tracking(1).foregroundStyle(RadarStyle.muted)
        }
        .disclosureGroupStyle(RadarRouteDisclosureStyle())
        .task(id: Request(address: address, registration: registration, enabled: enabled)) {
            lookup.select(address: address, registration: registration, enabled: enabled)
        }
        .onChange(of: scenePhase) { _, _ in updateVisibility() }
        .background(PhotoWindowVisibility { visible in
            windowVisible = visible
            updateVisibility()
        })
        .onDisappear { lookup.reset() }
    }

    private var explanation: String {
        switch lookup.status {
        case .disabled: "Enable Enrich aircraft details online in Settings to load aircraft photos."
        case .lookingUp: "Looking for a photograph of this aircraft."
        case .unavailable: "No photograph is available. The aircraft may have no matching photo, or the service may be offline."
        case .available: "Loading photograph…"
        }
    }

    private func imageArea(_ photo: AircraftPhoto) -> some View {
        let height = min(180, max(1, viewport.width - 48) * CGFloat(photo.height) / CGFloat(photo.width))
        return Group {
            if let image = lookup.image {
                AircraftPhotoImage(image: image, photo: photo, fullColour: fullColour)
            } else {
                Text("Loading photograph…").font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(RadarStyle.muted).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(height: height)
        .background {
            GeometryReader { geometry in
                let intersects = geometry.frame(in: .named("photoViewport")).intersects(CGRect(origin: .zero, size: viewport))
                Color.clear.onChange(of: intersects, initial: true) { _, value in
                    imageIntersectsViewport = value
                    updateVisibility()
                }
            }
        }
        .onDisappear {
            imageIntersectsViewport = false
            lookup.setVisible(false)
        }
    }

    private func updateVisibility() {
        lookup.setVisible(imageIntersectsViewport && windowVisible && scenePhase != .background)
    }
}

struct AircraftPhotoImage: View {
    let image: NSImage
    let photo: AircraftPhoto
    let fullColour: Bool
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false
    @FocusState private var focused: Bool
    private var showsColour: Bool { fullColour || hovered || focused }

    var body: some View {
        Button { openURL(photo.pageURL) } label: {
            Image(nsImage: image).resizable().scaledToFit()
                .saturation(showsColour ? 1 : 0)
                .colorMultiply(showsColour ? .white : RadarStyle.green)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onHover { hovered = $0 }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: showsColour)
        .overlay { Rectangle().stroke(focused ? RadarStyle.bright : RadarStyle.line, lineWidth: 1).allowsHitTesting(false) }
        .accessibilityLabel("Aircraft photograph by " + photo.photographer)
        .accessibilityHint("Opens the original photograph on Planespotters.net.")
        .help(fullColour ? "Open original photo on Planespotters.net" : "Hover or keyboard-focus for colour. Click to open original photo on Planespotters.net.")
    }
}

/// SwiftUI scene phase alone does not describe macOS window occlusion or minimization.
private struct PhotoWindowVisibility: NSViewRepresentable {
    let changed: (Bool) -> Void
    func makeNSView(context: Context) -> VisibilityView { VisibilityView() }
    func updateNSView(_ view: VisibilityView, context: Context) {
        view.changed = changed
        view.reportVisibility()
    }

    final class VisibilityView: NSView {
        var changed: ((Bool) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            let center = NotificationCenter.default
            center.removeObserver(self)
            if let window {
                center.addObserver(self, selector: #selector(reportVisibility), name: NSWindow.didChangeOcclusionStateNotification, object: window)
                center.addObserver(self, selector: #selector(reportVisibility), name: NSApplication.didHideNotification, object: nil)
                center.addObserver(self, selector: #selector(reportVisibility), name: NSApplication.didUnhideNotification, object: nil)
            }
            reportVisibility()
        }

        @objc func reportVisibility() {
            // Defer observation updates until SwiftUI has finished the current layout pass.
            Task { @MainActor [weak self] in
                guard let self else { return }
                changed?(window?.occlusionState.contains(.visible) == true && !NSApp.isHidden)
            }
        }
        deinit { NotificationCenter.default.removeObserver(self) }
    }
}
