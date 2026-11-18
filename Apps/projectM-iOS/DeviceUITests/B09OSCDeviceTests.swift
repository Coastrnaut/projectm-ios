// B09OSCDeviceTests.swift — QA-011 owner session B09 ("Network"), automated with the Mac as the LAN controller:
// scripts/osc_device_driver.py follows this run's xcodebuild log and answers each `OSC-READY <scenario>` line by
// sending OSC to the device over Wi-Fi. Local Network access was answered once per device (the human testing group).
// OSC-001-T26: /projectm/test 0.42 → "Test value 0.42". OSC-007-T12: the badge shows while listening; Stop ends
// delivery and Settings shows off. OSC-009-T15: a 2,000 msg/s flood for 10 s: rendering continues, "Rate-limited"
// grows, the value ends at the last one sent. OSC-006-T11: a bundle 0.5 s ahead applies about half a second later;
// one 30 s ahead never applies.
import UIKit
import XCTest

@MainActor
final class B09OSCDeviceTests: DeviceAcceptanceCase {
    private var testValue: String {
        let e = app.descendants(matching: .any)["oscTestValue"].firstMatch
        return (e.value as? String).flatMap { $0.isEmpty ? nil : $0 } ?? e.label
    }
    private var rateLimited: Int {
        let e = app.descendants(matching: .any)["oscRateLimited"].firstMatch
        let text = (e.value as? String).flatMap { $0.isEmpty ? nil : $0 } ?? e.label
        return Int(text.filter(\.isNumber)) ?? -1
    }

    /// OSC on (port 9000), Settings open at the OSC section, then the driver is asked for `scenario`.
    private func listen(_ scenario: String) {
        launch(visual: "circularSpectrum", settings: ["settings.osc.enabled": true, "settings.osc.port": 9000],
               extra: ["-uitestSettingsSection", "osc"])
        let controls = app.otherElements["controls"], area = app.otherElements["visualizerTapArea"].firstMatch
        if !controls.exists { area.tap(); _ = wait(3) { controls.exists } }
        app.buttons["settings"].tap()
        XCTAssertTrue(wait(5) { self.app.navigationBars["Settings"].exists }, "Settings opens")
        let status = app.descendants(matching: .any)["oscStatus"].firstMatch
        XCTAssertTrue(wait(10) { (status.value as? String ?? "").localizedCaseInsensitiveContains("listening") },
                      "OSC listens: \(String(describing: status.value))")
        print("OSC-READY \(scenario)")
    }

    func testOSC001TestValueFromTheMac() {
        let task = "OSC-001-T26"
        listen("test")
        let arrived = wait(10) { self.testValue.contains("0.42") }
        report(task, "test value", ["arrived": arrived ? 1 : 0])
        XCTAssertTrue(arrived, "Test value 0.42: \(testValue)")
    }

    func testOSC007BadgeAndStop() {
        let task = "OSC-007-T12"
        listen("test")
        XCTAssertTrue(wait(10) { self.testValue.contains("0.42") }, "delivered while listening")
        app.navigationBars["Settings"].buttons["Done"].tap()
        let badge = app.descendants(matching: .any)["oscListenerBadge"].firstMatch
        XCTAssertTrue(wait(5) { badge.exists }, "the listener badge shows while listening")
        let stop = app.buttons["oscStopButton"].firstMatch
        XCTAssertTrue(wait(5) { stop.exists }, "Stop")
        stop.tap()
        XCTAssertTrue(wait(5) { !badge.exists }, "the badge goes with Stop")
        print("OSC-READY after")
        pause(3)
        let controls = app.otherElements["controls"], area = app.otherElements["visualizerTapArea"].firstMatch
        if !controls.exists { area.tap(); _ = wait(3) { controls.exists } }
        app.buttons["settings"].tap()
        let toggle = app.switches["oscReceiverToggle"].firstMatch
        XCTAssertTrue(wait(5) { toggle.exists }, "the OSC switch")
        report(task, "stop", ["switchOff": (toggle.value as? String) == "0" ? 1 : 0, "badgeGone": badge.exists ? 0 : 1])
        XCTAssertEqual(toggle.value as? String, "0", "Settings shows OSC off after Stop")
        // OSC-001-T26: turning OSC off stops changes; the driver sent 0.11 after Stop.
        let ignored = !testValue.contains("0.11")
        report("OSC-001-T26", "off stops changes", ["afterStopIgnored": ignored ? 1 : 0])
        XCTAssertTrue(ignored, "a value sent after Stop does not apply: \(testValue)")
    }

    func testOSC009FloodIsRateLimited() {
        let task = "OSC-009-T15"
        listen("flood")
        pause(12)
        XCTAssertTrue(wait(5) { self.testValue.contains("0.77") }, "the value ends at the last one sent: \(testValue)")
        let limited = rateLimited
        report(task, "flood", ["rateLimited": Double(limited)])
        XCTAssertGreaterThan(limited, 0, "Rate-limited grows")
        app.navigationBars["Settings"].buttons["Done"].tap()
        assertFrameRate(task, "after the flood")
    }

    func testOSC006BundleTimeTags() {
        let task = "OSC-006-T11"
        listen("bundle")
        // The plain 0.33 marks the send on the device's clock; the bundle 2 s ahead must apply about 2 s later.
        XCTAssertTrue(wait(30) { self.testValue.contains("0.33") }, "the plain message arrives: \(testValue)")
        let t1 = Date()
        let applied = wait(6) { self.testValue.contains("0.55") }
        let gap = Date().timeIntervalSince(t1)
        report(task, "bundle", ["secondsAfterThePlainMessage": gap])
        XCTAssertTrue(applied, "the bundle 2 s ahead applies: \(testValue)")
        XCTAssertEqual(gap, 2, accuracy: 0.6, "about 2 s after the send (the poll adds up to a few tenths)")
        pause(5)
        XCTAssertFalse(testValue.contains("0.66"), "the bundle 30 s ahead has not applied: \(testValue)")
    }
}
