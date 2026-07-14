//
//  WallpaperController.swift
//  Surrealism · Ambient
//
//  Owns the desktop-wallpaper surface (U3): one WallpaperWindow + VideoPlayerController
//  per display, live-driven by the shared PlaybackSettings, kept in sync as displays
//  are connected/disconnected. Stopping closes only our windows — the user's system
//  wallpaper is never read or written (R16); this file calls no NSWorkspace desktop
//  APIs by design.
//

import AppKit

@MainActor
final class WallpaperController {

    private struct Surface {
        let displayID: CGDirectDisplayID
        let window: WallpaperWindow
        let controller: VideoPlayerController
        let propagator: PlaybackPropagator
    }

    private var surfaces: [Surface] = []
    private let settings: PlaybackSettings
    private let library: () -> [URL]
    private var screenObserver: NSObjectProtocol?

    init(settings: PlaybackSettings, library: @escaping () -> [URL]) {
        self.settings = settings
        self.library = library
    }

    var isActive: Bool { !surfaces.isEmpty }
    /// The per-display controllers — the active set for the shared PlaybackCommands.
    var controllers: [VideoPlayerController] { surfaces.map(\.controller) }

    func start() {
        guard surfaces.isEmpty, !library().isEmpty else { return }
        reconcile()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reconcile() }
        }
    }

    func stop() {
        if let o = screenObserver { NotificationCenter.default.removeObserver(o); screenObserver = nil }
        surfaces.forEach(teardown)
        surfaces = []
    }

    /// Pure set-difference for the display set — unit-tested without real screens.
    static func plan(current: [CGDirectDisplayID], existing: [CGDirectDisplayID])
        -> (add: [CGDirectDisplayID], remove: [CGDirectDisplayID]) {
        let cur = Set(current), ex = Set(existing)
        return (add: current.filter { !ex.contains($0) },
                remove: existing.filter { !cur.contains($0) })
    }

    // MARK: - Reconciliation

    private func reconcile() {
        let screensByID = Self.screenMap()
        let (add, remove) = Self.plan(current: Array(screensByID.keys), existing: surfaces.map(\.displayID))

        for id in remove {
            if let i = surfaces.firstIndex(where: { $0.displayID == id }) {
                teardown(surfaces[i]); surfaces.remove(at: i)
            }
        }
        // Reposition only when a screen's frame actually changed — the screen-params
        // notification fires often, and a redundant setFrame is wasteful churn.
        for s in surfaces {
            if let scr = screensByID[s.displayID], s.window.frame != scr.frame {
                s.window.reposition(to: scr)
            }
        }
        for id in add { if let scr = screensByID[id] { surfaces.append(makeSurface(displayID: id, screen: scr)) } }
    }

    private func makeSurface(displayID: CGDirectDisplayID, screen: NSScreen) -> Surface {
        let active = RotationResolver.activeURLs(rotation: settings.rotation, library: library())
        let vpc = VideoPlayerController(videos: active, shuffle: settings.shuffle)
        vpc.setFadeDuration(settings.crossFadeSeconds)
        vpc.setRate(Float(settings.playbackRate))
        vpc.setVideoGravity(.resizeAspectFill)   // fill the screen (no desktop bars)
        let win = WallpaperWindow(screen: screen)
        win.mount(vpc)
        win.orderFrontRegardless()
        vpc.start()
        let prop = PlaybackPropagator(settings: settings, engine: vpc, library: library)
        return Surface(displayID: displayID, window: win, controller: vpc, propagator: prop)
    }

    private func teardown(_ s: Surface) {
        s.controller.stop()
        s.window.orderOut(nil)
    }

    /// Map each live display to its NSScreen via the CoreGraphics display id.
    private static func screenMap() -> [CGDirectDisplayID: NSScreen] {
        var map: [CGDirectDisplayID: NSScreen] = [:]
        for scr in NSScreen.screens {
            if let n = scr.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                map[CGDirectDisplayID(n.uint32Value)] = scr
            }
        }
        return map
    }
}
