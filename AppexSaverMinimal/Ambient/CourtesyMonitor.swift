//
//  CourtesyMonitor.swift
//  Surrealism · Ambient
//
//  Battery/thermal courtesy for the desktop wallpaper (U5, R14): pause playback
//  when the Mac is on battery or thermally stressed, resume when plugged/cool.
//  On by default; a toggle disables it. The decision is a pure function so it's
//  unit-tested; the live inputs (power source, thermal state) are polled + notified.
//
//  Occlusion-based pausing is deferred — `occlusionState` for an all-Spaces
//  desktop-level window is unreliable across macOS versions (verify on-device
//  before wiring); the pure policy already takes an `occluded` input for later.
//

import AppKit
import IOKit.ps

@MainActor
final class CourtesyMonitor {

    /// Pure policy — pause when courtesy is on AND any stressor is present.
    nonisolated static func shouldPause(enabled: Bool, onBattery: Bool, occluded: Bool, thermalSerious: Bool) -> Bool {
        enabled && (onBattery || occluded || thermalSerious)
    }

    private let isEnabled: () -> Bool
    /// (pause, reason) — reason is a short human label for the paused state.
    private let onChange: (Bool, String?) -> Void
    private var timer: Timer?
    private var thermalObserver: NSObjectProtocol?

    /// Set by the wallpaper controller when all its windows are occluded (deferred).
    var occluded = false { didSet { evaluate() } }
    private(set) var isPausing = false

    init(isEnabled: @escaping () -> Bool, onChange: @escaping (Bool, String?) -> Void) {
        self.isEnabled = isEnabled
        self.onChange = onChange
    }

    func start() {
        evaluate()
        timer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.evaluate() }
        }
        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.evaluate() }
        }
    }

    func stop() {
        timer?.invalidate(); timer = nil
        if let o = thermalObserver { NotificationCenter.default.removeObserver(o); thermalObserver = nil }
        if isPausing { isPausing = false; onChange(false, nil) }
    }

    /// Re-evaluate now (e.g. when the courtesy toggle flips).
    func evaluate() {
        let onBattery = Self.onBattery()
        let thermalSerious = ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue
        let pause = Self.shouldPause(enabled: isEnabled(), onBattery: onBattery, occluded: occluded, thermalSerious: thermalSerious)
        guard pause != isPausing else { return }
        isPausing = pause
        let reason = !pause ? nil : (onBattery ? "on battery" : (thermalSerious ? "cooling down" : "hidden"))
        onChange(pause, reason)
    }

    /// Whether the Mac is currently drawing from the battery (not AC).
    static func onBattery() -> Bool {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(blob)?.takeRetainedValue() as String? else { return false }
        return type == (kIOPSBatteryPowerValue as String)
    }
}
