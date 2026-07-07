//
//  DeviceID.swift
//  Surrealism · Commerce
//
//  A stable per-machine identifier sent with every license request so the
//  backend can enforce the 3-device activation cap. Derived from the hardware
//  IOPlatformUUID (stable across app reinstalls; changes only with a logic-board
//  swap), with a persisted random fallback if the registry read ever fails.
//

import Foundation
import IOKit

enum DeviceID {
    /// Stable identifier for this Mac.
    static let current: String = hardwareUUID() ?? persistedFallback()

    private static func hardwareUUID() -> String? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard let cf = IORegistryEntryCreateCFProperty(service, "IOPlatformUUID" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? String, !cf.isEmpty else { return nil }
        return cf
    }

    private static let fallbackKey = "app.surrealism.deviceIDFallback"
    private static func persistedFallback() -> String {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: fallbackKey) { return existing }
        let generated = UUID().uuidString
        defaults.set(generated, forKey: fallbackKey)
        return generated
    }
}
