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
        let controls = app.otherElements["controls"]
        if controls.exists { return }
        tapVisualizer(attempt: 0)   // below the probe readouts, never at the tap area's hit point (D1 r16)
        if !wait(2, { controls.exists }) { tapVisualizer(attempt: 1) }
        XCTAssertTrue(wait(5) { controls.exists }, "the controls are shown")
    }

    func openSettingsPanel() {
        if settingsAlreadyOpen() { return }
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
        tapSettingsDone()
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
    /// hittable and clear of the iPhone's floating search field). After the steps a hittable element still counts (one
    /// outside a list, a bottom toolbar's button, can never clear that chrome).
    ///
    /// Direction: `up` true searches towards the list's start first. While the element exists its frame decides (above
    /// the navigation bar: towards the start; under the bottom chrome: towards the end). When it does not exist (a
    /// lazy list builds no off-screen rows) and a step moved nothing (the list's end) or `swipes` steps found nothing,
    /// the search turns round once. D1 2026-11-23: MED-006's Slideshow switch sits above the seven picture rows and the
    /// Add buttons, so after two Files picks it was off screen above while every step went towards the end
    /// ("slideshowToggle is reachable"); FILE-010's storage rows were above the Clear Caches result the same way (every
    /// row read -1 after Clear Caches).
    ///
    /// A sheet must never be pulled down at its start (D1 r10b, 2026-11-23, FILE-010-T11): after Clear Caches the
    /// first step towards the start brought the Storage list to its top; "storage.photos" (the first row, under the
    /// expanded large title) still counted as above the navigation bar, so a second full-height drag towards the start
    /// pulled the Settings sheet down and closed it, and the next 60 steps dragged the visual behind it (every row read
    /// -1). An element already on screen is now brought clear with one short drag of the distance it lacks (too short
    /// to close a sheet), and the search stops when the list it was scrolling leaves the screen.
    @discardableResult
    func scrollTo(_ element: XCUIElement, up: Bool = false, swipes: Int = 10) -> Bool {
        var towardsEnd = !up, turned = false, scrolledList = false
        for step in 0..<(swipes * 2) {
            if reachable(element) { return true }
            // The list that holds the element when it exists (an iPad's browser sheet is not the first collection view).
            let list = app.listHolding(element.exists ? element : nil)
            if list.elementType == .window {
                // The list this search was scrolling has gone (a sheet closed): dragging the window behind it would
                // only move the visual or the app's other controls.
                if scrolledList {
                    print("DEVICE-ACCEPT-NOTE scrollTo: the list left the screen; stopping (a sheet closed?)")
                    break
                }
            } else {
                scrolledList = true
            }
            if element.exists, element.frame.height > 0 {
                let frame = element.frame, bar = app.navigationBars.firstMatch
                let top: CGFloat = bar.exists ? bar.frame.maxY : app.windows.firstMatch.frame.minY
                let bottom = app.bottomChromeTop
                // On screen but partly under the bar or the bottom chrome: one short, slow drag of what it lacks.
                let underBar = frame.minY < top, underChrome = frame.maxY > bottom
                if frame.maxY > top, frame.minY < bottom, underBar != underChrome, list.elementType != .window,
                   list.nudge(by: underBar ? top - frame.minY + 24 : -(frame.maxY - bottom + 24)) {
                    if reachable(element) { return true }
                    if element.exists, element.isHittable, element.frame.minY == frame.minY {
                        return true   // it did not move: the list is at that end; as far into view as it goes
                    }
                    continue
                }
                if frame.maxY > bottom { towardsEnd = true } else if frame.minY < top { towardsEnd = false }
            } else if !turned, step == swipes {
                towardsEnd.toggle()
                turned = true
            }
            let before = Self.listSignature(list)
            list.scrollStep(up: towardsEnd)   // inside the list, clear of the Home gesture (ListScrolling)
            if !element.exists, !before.isEmpty, Self.listSignature(list) == before {
                if turned { break }   // both ends reached
                towardsEnd.toggle()   // this end of the list: nothing moved
                turned = true
            }
        }
        return reachable(element) || (element.exists && element.isHittable)
    }

    /// The labels and positions of the list's first visible rows (one snapshot): unchanged after a step means the list
    /// did not move. Empty when no snapshot can be taken.
    static func listSignature(_ list: XCUIElement) -> String {
        guard let root = try? list.snapshot() else { return "" }
        var parts: [String] = [], pending: [any XCUIElementSnapshot] = root.children
        while !pending.isEmpty, parts.count < 8 {
            let node = pending.removeFirst()
            if !node.identifier.isEmpty || !node.label.isEmpty {
                parts.append("\(node.identifier)|\(node.label)@\(Int(node.frame.minY))")
            }
            pending.append(contentsOf: node.children)
        }
        return parts.joined(separator: ";")
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

    /// The glow the visual shows: the "effective" value of the MOD-002 DEBUG readout ("unbound, manual 0.50, effective
    /// 0.50", shown with `-uitestBindGlowToLevel`; the test taps Unbind first so OSC and MIDI writes are read
    /// unmodulated). MIDI-003 and OSC-003 write live values on top of the manual glow (`NativeSpectrumHost.externalValues`),
    /// so "manual" never moves with them: B09's OSC-003/OSC-004 read "manual" and saw 0.50 throughout on D1-D3 although
    /// the Mac's values arrived (OSC-004 learned the address), while B10 already read "effective" (2026-11-21).
    func liveGlow() -> Double? {
        let label = app.staticTexts["glowModulation"].firstMatch.label
        guard let range = label.range(of: "effective ") else { return nil }
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

