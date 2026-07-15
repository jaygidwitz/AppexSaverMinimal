//
//  TelemetryTests.swift
//  Surrealism
//

import XCTest
@testable import Surrealism

@MainActor
final class TelemetryTests: XCTestCase {

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "test.\(UUID().uuidString)")!
    }

    private func makeTelemetry(defaults: UserDefaults? = nil,
                               secret: String = "test-secret",
                               sent: @escaping (URL, Data) -> Void) -> Telemetry {
        Telemetry(defaults: defaults ?? makeDefaults(), apiSecret: secret, transport: sent)
    }

    private func decode(_ data: Data) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    func testSend_buildsMeasurementProtocolPayload() {
        var captured: (url: URL, body: Data)?
        let t = makeTelemetry { captured = ($0, $1) }
        t.send("app_open")

        let url = captured?.url.absoluteString ?? ""
        XCTAssertTrue(url.contains("google-analytics.com/mp/collect"))
        XCTAssertTrue(url.contains("measurement_id=\(Telemetry.measurementID)"))
        XCTAssertTrue(url.contains("api_secret=test-secret"))

        let payload = decode(captured?.body ?? Data())
        XCTAssertNotNil(payload["client_id"] as? String)
        let event = (payload["events"] as? [[String: Any]])?.first
        XCTAssertEqual(event?["name"] as? String, "app_open")
        let params = event?["params"] as? [String: Any]
        XCTAssertEqual(params?["platform"] as? String, "macos")
        XCTAssertNotNil(params?["app_version"] as? String)
        XCTAssertEqual(params?["engagement_time_msec"] as? Int, 1)
    }

    func testSend_mergesCustomParams() {
        var body: Data?
        let t = makeTelemetry { body = $1 }
        t.send("app_loop_downloaded", params: ["loop_id": "loop-07", "is_sample": false])

        let event = (decode(body ?? Data())["events"] as? [[String: Any]])?.first
        let params = event?["params"] as? [String: Any]
        XCTAssertEqual(params?["loop_id"] as? String, "loop-07")
        XCTAssertEqual(params?["is_sample"] as? Bool, false)
        XCTAssertEqual(params?["platform"] as? String, "macos")
    }

    func testClientId_persistsAcrossInstances() {
        let defaults = makeDefaults()
        var first: String?, second: String?
        makeTelemetry(defaults: defaults) { _, d in first = self.decode(d)["client_id"] as? String }
            .send("app_open")
        makeTelemetry(defaults: defaults) { _, d in second = self.decode(d)["client_id"] as? String }
            .send("app_open")
        XCTAssertNotNil(first)
        XCTAssertEqual(first, second, "client_id must be stable per install")
    }

    func testDisabled_sendsNothing_andPersists() {
        let defaults = makeDefaults()
        var count = 0
        let t = makeTelemetry(defaults: defaults) { _, _ in count += 1 }
        t.setEnabled(false)
        t.send("app_open")
        XCTAssertEqual(count, 0)

        // A fresh instance on the same defaults stays off.
        let t2 = makeTelemetry(defaults: defaults) { _, _ in count += 1 }
        XCTAssertFalse(t2.enabled)
        t2.send("app_open")
        XCTAssertEqual(count, 0)

        t2.setEnabled(true)
        t2.send("app_open")
        XCTAssertEqual(count, 1)
    }

    func testPlaceholderSecret_sendsNothing() {
        var count = 0
        let t = makeTelemetry(secret: Telemetry.placeholderSecret) { _, _ in count += 1 }
        t.send("app_open")
        XCTAssertEqual(count, 0, "no network until a real MP secret is configured")
    }
}
