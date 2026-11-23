// ControlSurfaceSupport.swift — shared steps for the QA-011 Batch 8 device tests (OSC, MIDI from the Mac, the fake
// external display, two devices): B09OSCDeviceTests, B09OSCPeerDeviceTests, B10MIDIDeviceTests, B11OutputDeviceTests.
// AirPlay and USB-cable steps (Airplane Mode, Wi-Fi outages) are not required (owner ruling 2026-11-18).
//
// * Mac hand-offs: a test prints `<KIND>-READY <scenario>` (OSC, MIDI, PEER); a Mac script follows the
//   xcodebuild log and acts (scripts/osc_device_driver.py, scripts/mac_driver/midi.py, scripts/mac_driver/peer.py).
//   The log reaches the Mac seconds late, so a test always waits on what it can see in the app, never on a time.
// * Values the Mac knows come in as environment variables: `xcodebuild … TEST_RUNNER_<NAME>=<value>` reaches the
//   runner as `<NAME>` (MAC_IP, PEER_IP, MIDI_SOURCE). A missing one skips the test with the command that sets
//   it; nothing waits on a person.
// * System UI (Files, share sheets, the Settings app) goes through Batch 1's SystemUI.swift; every call to it is in the
//   "SystemUI bridge" section below, so an API difference is fixed in one place.
import UIKit
import XCTest

@MainActor
class ControlSurfaceCase: DeviceAcceptanceCase {
    // MARK: Environment from the Mac

    /// `TEST_RUNNER_<name>` on the xcodebuild command line (nil when unset or empty).
    func runnerValue(_ name: String) -> String? {
        let value = ProcessInfo.processInfo.environment[name] ?? ""
        return value.isEmpty ? nil : value
    }

    /// A runner value or a skip that says how to provide it.
    func requireRunnerValue(_ name: String, _ why: String) throws -> String {
        guard let value = runnerValue(name) else {
            throw XCTSkip("\(why): set TEST_RUNNER_\(name)=<value> on the xcodebuild command (scripts/mac_driver/peer.py "
                          + "and the drivers print the value)")
        }
        return value
    }

    /// One line for a Mac script that follows the log (`OSC-READY glow`, `MIDI-READY cc21`, `PEER-READY lead`).
    func ready(_ kind: String, _ scenario: String) {
        print("\(kind)-READY \(scenario)")
    }

    // MARK: Elements and values

    func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    /// An element's accessibility value, or its label when the value is empty.
    func text(_ id: String) -> String {
        let e = element(id)
        guard e.exists else { return "" }
        return (e.value as? String).flatMap { $0.isEmpty ? nil : $0 } ?? e.label
    }

    /// The controls bar, shown with a fresh auto-hide.
    func showControlsBar() {
        let controls = app.otherElements["controls"], area = app.otherElements["visualizerTapArea"].firstMatch
        if controls.exists { return }
        area.tap()
        if !wait(2, { controls.exists }) { area.tap() }
        XCTAssertTrue(wait(5) { controls.exists }, "the controls are shown")
    }

    func openSettingsPanel() {
        showControlsBar()
        app.buttons["settings"].tap()
        XCTAssertTrue(wait(5) { self.app.navigationBars["Settings"].exists }, "Settings opens")
    }

    func closeSettingsPanel() {
        // Done lives only on the root Settings screen: from a pushed screen (Show Editor › Scene Folders) go back first,
        // or the panel stays open and covers the show controls (FILE-001-T19 on D3, 2026-11-23).
        for _ in 0..<4 where !app.navigationBars["Settings"].exists {
            // Only a real back button (never a sheet's Cancel or a toolbar item).
            let back = app.navigationBars.buttons.matching(identifier: "BackButton").firstMatch
            guard back.exists, back.isHittable else { break }
            back.tap()
            _ = wait(2) { self.app.navigationBars["Settings"].exists }
        }
        let done = app.navigationBars["Settings"].buttons["Done"]
        if done.exists { done.tap() }
        _ = wait(5) { !self.app.navigationBars["Settings"].exists }
    }

    /// Back one level in a pushed Settings screen.
    func goBack() {
        app.navigationBars.firstMatch.buttons.element(boundBy: 0).tap()
        pause(0.6)
    }

    /// Whether a tap on `element` reaches it: it exists, is hittable, and lies wholly between the navigation bar and the
    /// chrome pinned over the list's foot (`XCUIApplication.isClearOfChrome`).
    ///
    /// QA-011 D1 rerun (iPhone 15, iOS 27.0.1, 2026-11-23): on an iPhone iOS 27 floats Settings' and the preset
    /// browser's search field over the foot of the list. A row under it is inside the window, so `isHittable` was true
    /// and the tap went to the search field: MED-006's Slideshow switch (the tap opened the search, the list redrew and
    /// the switch was gone: "No matches found for slideshowToggle"), PRE-012 and PRE-014's My Presets row (the browser
    /// stayed at its home, so no Import Preset…). A row now counts as reachable only above that chrome.
    func reachable(_ element: XCUIElement) -> Bool {
        element.exists && element.isHittable && app.isClearOfChrome(element)
    }

    /// Swipes the frontmost list (slowly, never down at the top of a sheet) until `element` is reachable (`reachable`:
    /// hittable and clear of the iPhone's floating search field). After `swipes` steps a hittable element still counts
    /// (one outside a list, a bottom toolbar's button, can never clear that chrome).
    @discardableResult
    func scrollTo(_ element: XCUIElement, up: Bool = false, swipes: Int = 10) -> Bool {
        let list = app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch : app.tables.firstMatch
        for _ in 0..<swipes {
            if reachable(element) { return true }
            list.scrollStep(up: !up)   // inside the list, clear of the Home gesture (ListScrolling)
        }
        return element.exists && element.isHittable
    }

    /// Sets a SwiftUI Toggle row by tapping its switch (the row's centre is its label; autotester lesson). Reads the
    /// switch's value only while it exists: reading a missing element's value fails the test at once with "No matches
    /// found" instead of saying which step went wrong (MED-006 on D1, 2026-11-23).
    func setSwitch(_ id: String, on: Bool) {
        let toggle = app.switches[id].firstMatch
        let wanted = on ? "1" : "0"
        func isSet() -> Bool { toggle.exists && (toggle.value as? String) == wanted }
        XCTAssertTrue(scrollTo(toggle), "\(id) is reachable")
        guard toggle.exists else { return XCTFail("\(id): no such switch on screen") }
        guard !isSet() else { return }
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        if !wait(3, isSet), toggle.exists { toggle.switches.firstMatch.tap() }
        XCTAssertTrue(wait(3, isSet), "\(id) is \(on ? "on" : "off")\(toggle.exists ? "" : " (the switch left the screen)")")
    }

    /// The glow intensity the native host holds: "unbound, manual 0.50, effective 0.50" (MOD-002 DEBUG readout, shown
    /// with `-uitestBindGlowToLevel`; the test taps Unbind first so OSC and MIDI writes are read unmodulated).
    func manualGlow() -> Double? {
        let label = app.staticTexts["glowModulation"].firstMatch.label
        guard let range = label.range(of: "manual ") else { return nil }
        return Double(label[range.upperBound...].prefix(while: { $0.isNumber || $0 == "." }))
    }

    /// Launch arguments that show the glow readout unbound; call `unbindGlow()` after the launch.
    static let glowReadoutArguments: [String] = ["-uitestBindGlowToLevel"]
    static let glowSettings: [String: Any] = ["settings.circularSpectrum.glow": true]

    func unbindGlow() {
        let unbind = app.buttons["glowModulationUnbind"].firstMatch
        XCTAssertTrue(wait(10) { unbind.exists }, "the glow readout (-uitestBindGlowToLevel)")
        unbind.tap()
        XCTAssertTrue(wait(3) { self.app.staticTexts["glowModulation"].firstMatch.label.hasPrefix("unbound") },
                      "glow unbound: \(app.staticTexts["glowModulation"].firstMatch.label)")
    }

    /// The SHOW-001 seed's scene IDs (cue n shows scene n).
    static func seedSceneID(_ n: Int) -> String { "5CE7E000-0000-4000-8000-00000000000\(n)" }

    /// "<scene id>|<visual>" of the applied show scene (`showAppliedScene`, DEBUG).
    var appliedScene: String { text("showAppliedScene") }

    func appliedCue() -> Int? {
        for n in 1...5 where appliedScene.hasPrefix(Self.seedSceneID(n)) { return n }
        return nil
    }

    /// Next cue from the show controls (`showNextCue`).
    func stepNextCue() {
        showControlsBar()
        let next = app.buttons["showNextCue"].firstMatch
        XCTAssertTrue(wait(5) { next.exists }, "Next cue (show controls)")
        next.tap()
    }

    // MARK: SystemUI bridge (Batch 1's SystemUI.swift; adjust here only)

    /// Batch 1's system UI helpers for this test's app.
    var system: SystemUI { SystemUI(app: app) }

    /// A real share sheet's activity ("Save to Files").
    func bridgeShare(_ activity: String) {
        XCTAssertTrue(system.shareSheet(activity), "the share sheet offers \(activity)")
    }

    /// The Files save sheet: On My iPhone/iPad › projectM-iOS (the device-test host shares Documents, Batch 1).
    func bridgeSaveToDocuments() {
        XCTAssertTrue(system.filesSave(path: [Self.onMyDevice, SystemUI.appDisplayName]), "saved to On My … › projectM-iOS")
    }

    /// The Files open sheet: pick `name` from On My iPhone/iPad › projectM-iOS.
    func bridgePickFromDocuments(_ name: String) {
        XCTAssertTrue(system.filesPick(path: [Self.onMyDevice, SystemUI.appDisplayName], name: name), "picked \(name)")
    }

    /// The Settings app (App Privacy Report, Multitasking).
    var bridgePreferences: XCUIApplication { system.preferences }

    static var onMyDevice: String { UIDevice.current.userInterfaceIdiom == .pad ? "On My iPad" : "On My iPhone" }

    // MARK: The fake external display (DEBUG `-uitestExternalDisplay`; AirPlay is not required, owner ruling 2026-11-18)

    var outputMode: String { text("externalOutputMode") }
    var externalResolution: String { text("externalResolution") }
    var sourceStarts: String { text("sourceStarts") }

    /// Connects the DEBUG off-screen display through the coordinator calls a real external scene makes.
    func connectFakeDisplay(small: Bool = false) {
        let button = app.buttons[small ? "uitestConnectExternalSmall" : "uitestConnectExternal"].firstMatch
        XCTAssertTrue(wait(10) { button.exists }, "the fake display panel (-uitestExternalDisplay)")
        button.tap()
        XCTAssertTrue(wait(10) { self.outputMode.contains("target=external") }, "the visual is on the fake display: \(outputMode)")
    }

    func disconnectFakeDisplay() {
        app.buttons["uitestDisconnectExternal"].firstMatch.tap()
        XCTAssertTrue(wait(10) { self.outputMode.contains("target=device") }, "the visual is back: \(outputMode)")
    }

    /// "drawable=1920x1080" from the `externalResolution` probe.
    func externalDrawable() -> (Int, Int)? {
        guard let range = externalResolution.range(of: #"drawable=(\d+)x(\d+)"#, options: .regularExpression) else { return nil }
        let parts = externalResolution[range].dropFirst("drawable=".count).split(separator: "x").compactMap { Int($0) }
        return parts.count == 2 ? (parts[0], parts[1]) : nil
    }
}

