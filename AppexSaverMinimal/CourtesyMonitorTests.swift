//
//  CourtesyMonitorTests.swift
//  Surrealism
//
//  U5: the pure battery/thermal/occlusion courtesy policy. Live power/thermal
//  transitions are verified on-device.
//

import XCTest
@testable import Surrealism

final class CourtesyMonitorTests: XCTestCase {

    func testShouldPause_truthTable() {
        // Courtesy off → never pause, whatever the stressors.
        XCTAssertFalse(CourtesyMonitor.shouldPause(enabled: false, onBattery: true, occluded: true, thermalSerious: true))

        // Enabled, no stressor → play.
        XCTAssertFalse(CourtesyMonitor.shouldPause(enabled: true, onBattery: false, occluded: false, thermalSerious: false))

        // Enabled + any single stressor → pause.
        XCTAssertTrue(CourtesyMonitor.shouldPause(enabled: true, onBattery: true, occluded: false, thermalSerious: false))
        XCTAssertTrue(CourtesyMonitor.shouldPause(enabled: true, onBattery: false, occluded: true, thermalSerious: false))
        XCTAssertTrue(CourtesyMonitor.shouldPause(enabled: true, onBattery: false, occluded: false, thermalSerious: true))
    }
}
