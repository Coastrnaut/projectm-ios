// B09OSCDeviceTests.swift — QA-011 owner session B09 ("Network"), automated with the Mac as the LAN controller:
// scripts/osc_device_driver.py follows this run's xcodebuild log and answers each `OSC-READY <scenario>` line by
// sending OSC to the device over Wi-Fi. Local Network access was answered once per device (the human testing group).
// OSC-001-T26: /projectm/test 0.42 → "Test value 0.42". OSC-007-T12: the badge shows while listening; Stop ends
// delivery and Settings shows off. OSC-009-T15: a 2,000 msg/s flood for 10 s: rendering continues, "Rate-limited"
// grows, the value ends at the last one sent. OSC-006-T11: a bundle 0.5 s ahead applies about half a second later;
// one 30 s ahead never applies.
// QA-011 Batch 8 (2026-11-18):
// OSC-003-T15: `/projectm/param/glow.intensity` 0.2 then 0.9 from the Mac moves the glow (MOD-002's readout, unbound).
// OSC-004-T14: Learn on Glow intensity; the Mac sends a new address; the alias is listed and its values move the glow.
// OSC-005-T16: Send OSC to the Mac (`TEST_RUNNER_MAC_IP`, port 9100); the driver's listener checks the addresses.
// OSC-010-T09: Export routes… › Save to Files › On My iPhone › projectM-iOS; the driver copies the file off the device
// and checks every route on screen is in it and no address or port is.
// FILE-012-T11: after OSC traffic, Settings › Privacy & Security › App Privacy Report lists no domain for projectM-iOS.
// Two-device tests (OSC-008-T13, OSC-011-T19, OSC-012-T22) are B09OSCPeerDeviceTests, run by scripts/mac_driver/peer.py.
import UIKit
import XCTest

@MainActor
final class B09OSCDeviceTests: ControlSurfaceCase {
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
    private func listen(_ scenario: String, settings: [String: Any] = [:], extra: [String] = []) {
        var values: [String: Any] = ["settings.osc.enabled": true, "settings.osc.port": 9000]
        values.merge(settings) { (_: Any, given: Any) -> Any in given }
        launch(visual: "circularSpectrum", settings: values, extra: ["-uitestSettingsSection", "osc"] + extra)
        let controls = app.otherElements["controls"], area = app.otherElements["visualizerTapArea"].firstMatch
        if !controls.exists { area.tap(); _ = wait(3) { controls.exists } }
        app.buttons["settings"].tap()
        XCTAssertTrue(wait(5) { self.app.navigationBars["Settings"].exists }, "Settings opens")
        let status = app.descendants(matching: .any)["oscStatus"].firstMatch
        XCTAssertTrue(wait(10) { (status.value as? String ?? "").localizedCaseInsensitiveContains("listening") },
                      "OSC listens: \(String(describing: status.value))")
        if !scenario.isEmpty { print("OSC-READY \(scenario)") }
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
        // OSC-001-T26: turning OSC off stops changes; the driver sent 0.11 after Stop. Off hides the test-value
        // row, so turn OSC back on (nothing is sent now) and read it: still the 0.42 from before Stop.
        // A SwiftUI Toggle row's centre is its label; tap the switch at the trailing edge.
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        if !wait(3, { (toggle.value as? String) == "1" }) { toggle.switches.firstMatch.tap() }
        XCTAssertTrue(wait(10) { self.app.descendants(matching: .any)["oscTestValue"].firstMatch.exists },
                      "the test value row returns with OSC on (switch \(String(describing: toggle.value)))")
        pause(2)
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

    // MARK: Batch 8

    /// OSC on, Settings closed, the glow readout unbound: a route's value is read from "manual …".
    private func launchForGlow() {
        launch(visual: "circularSpectrum",
               settings: Self.glowSettings.merging(["settings.osc.enabled": true, "settings.osc.port": 9000]) { a, _ in a },
               extra: Self.glowReadoutArguments)
        unbindGlow()
        XCTAssertTrue(wait(10) { self.element("oscListenerBadge").exists }, "OSC listens (the listener badge)")
    }

    /// Waits until the glow readout settles on a value different from `from` (OSC applies on the main actor).
    private func glowChange(from: Double?, within seconds: Double) -> Double? {
        var seen: Double?
        let changed = wait(seconds) {
            seen = self.manualGlow()
            guard let v = seen else { return false }
            return from.map { abs(v - $0) > 0.005 } ?? true
        }
        pause(1)   // the driver sends each value three times 50 ms apart
        return changed ? manualGlow() : nil
    }

    /// OSC-003-T15: the standard route moves the glow: 0.2 gives a lower value than 0.9 (normalized over the
    /// parameter's range, OSC-003-R4).
    func testOSC003GlowFollowsParamRoute() {
        let task = "OSC-003-T15"
        launchForGlow()
        let start = manualGlow()
        print("OSC-READY glow-low")
        let low = glowChange(from: start, within: 30)
        print("OSC-READY glow-high")
        let high = glowChange(from: low, within: 20)
        report(task, "glow route", ["start": start ?? -1, "low": low ?? -1, "high": high ?? -1])
        XCTAssertNotNil(low, "0.2 to /projectm/param/glow.intensity changes the glow (start \(start ?? -1))")
        XCTAssertNotNil(high, "0.9 changes it again")
        if let low, let high { XCTAssertGreaterThan(high, low + 0.05, "0.9 gives more glow than 0.2") }
    }

    /// OSC-004-T14: Learn on Glow intensity; the driver sends `/b8/fader/9` (an address no route has); the alias is
    /// listed on, and its later values move the glow.
    func testOSC004Learn() {
        let task = "OSC-004-T14"
        listen("", settings: Self.glowSettings, extra: Self.glowReadoutArguments)
        let link = app.buttons["oscRoutesLink"].firstMatch
        XCTAssertTrue(scrollTo(link), "OSC Routes is in the OSC section")
        link.tap()
        XCTAssertTrue(wait(5) { self.app.navigationBars["OSC Routes"].exists })
        let learn = app.buttons["oscLearn.effect.bloom.intensity"].firstMatch
        XCTAssertTrue(wait(5) { learn.exists && learn.isEnabled }, "Learn is enabled while the receiver listens")
        learn.tap()
        let status = app.staticTexts["oscLearnStatus"].firstMatch
        XCTAssertTrue(wait(5) { ((status.value as? String) ?? "").hasPrefix("Send a message") }, "learning")
        print("OSC-READY learn")
        let learned = wait(30) { (status.value as? String) == "Glow intensity now listens to /b8/fader/9." }
        report(task, "learn", ["learned": learned ? 1 : 0])
        XCTAssertTrue(learned, "status: \(String(describing: status.value))")
        let row = app.switches["oscRoute_b8_fader_9"].firstMatch
        XCTAssertTrue(scrollTo(row), "the learned alias is listed")
        XCTAssertEqual(row.value as? String, "1", "on")
        closeSettingsPanel()
        unbindGlow()
        let start = manualGlow()
        print("OSC-READY learn-low")
        let low = glowChange(from: start, within: 30)
        print("OSC-READY learn-high")
        let high = glowChange(from: low, within: 20)
        report(task, "learned values", ["low": low ?? -1, "high": high ?? -1])
        XCTAssertNotNil(low, "the learned address drives the glow")
        if let low, let high { XCTAssertGreaterThan(high, low + 0.05, "0.95 gives more glow than 0.1") }
    }

    /// OSC-005-T16: Send OSC to the Mac. The driver's listener (`--listen-port 9100`) records what arrives between
    /// `OSC-READY listen` and `OSC-READY listen-done` and fails the run unless /projectm/status and two
    /// /projectm/scene messages came; the device checks its own counter ("N sent, 0 dropped").
    func testOSC005Send() throws {
        let task = "OSC-005-T16"
        let mac = try requireRunnerValue("MAC_IP", "Send OSC needs the Mac's LAN address")
        listen("listen", settings: ["settings.osc.send.enabled": true, "settings.osc.send.host": mac,
                                    "settings.osc.send.port": 9100, "settings.osc.send.kinds": ["scene", "status"]],
               extra: ["-uitestShowSeed"])
        closeSettingsPanel()
        pause(4)   // the log reaches the driver a few seconds late; its listener is already up (started with the driver)
        for _ in 0..<3 { stepNextCue(); pause(2) }
        print("OSC-READY listen-done")
        openSettingsPanel()
        let link = app.buttons["oscSendLink"].firstMatch
        XCTAssertTrue(scrollTo(link), "Send OSC is in the OSC section")
        link.tap()
        XCTAssertTrue(wait(5) { self.app.navigationBars["Send OSC"].exists })
        let status = text("oscSendStatus"), counts = text("oscSendCounts")
        let sent = Int(counts.split(separator: " ").first ?? "") ?? -1
        report(task, "send", ["sent": Double(sent), "sendingToMac": status.contains(mac) ? 1 : 0])
        XCTAssertTrue(status.hasPrefix("Sending to"), "Send OSC is active: \(status)")
        XCTAssertGreaterThanOrEqual(sent, 3, "the status and three cue steps were sent: \(counts)")
        XCTAssertTrue(counts.hasSuffix("0 dropped"), counts)
    }

    /// OSC-010-T09: every route on screen, then Export routes… through the real share sheet into the app's Documents
    /// (Files › On My iPhone › projectM-iOS); the driver (`--device`) copies the newest export off the device and
    /// compares it with the `OSC-ROUTES` line.
    func testOSC010ExportRoutes() {
        let task = "OSC-010-T09"
        launch(visual: "circularSpectrum", settings: ["settings.osc.enabled": false], extra: ["-uitestSettingsSection", "osc"])
        openSettingsPanel()
        let link = app.buttons["oscRoutesLink"].firstMatch
        XCTAssertTrue(scrollTo(link), "OSC Routes is in the OSC section")
        link.tap()
        XCTAssertTrue(wait(5) { self.app.navigationBars["OSC Routes"].exists })
        var addresses = Set<String>()
        let export = app.buttons["oscSchemaExport"].firstMatch
        let rows = app.switches.matching(NSPredicate(format: "identifier BEGINSWITH 'oscRoute_'"))
        for _ in 0..<30 {
            for row in rows.allElementsBoundByIndex where row.exists {
                let address = String(row.label.prefix(while: { $0 != "," }))
                if address.hasPrefix("/") { addresses.insert(address) }
            }
            if export.exists && export.isHittable { break }
            app.collectionViews.firstMatch.swipeUp(velocity: .slow)
        }
        let json = (try? JSONSerialization.data(withJSONObject: addresses.sorted()))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        print("OSC-ROUTES \(json)")
        report(task, "routes on screen", ["routes": Double(addresses.count)])
        XCTAssertGreaterThan(addresses.count, 2, "the routes list was read")
        XCTAssertTrue(export.exists && export.isHittable, "Export routes… is the last section")
        export.tap()
        bridgeShare("Save to Files")
        bridgeSaveToDocuments()
        XCTAssertTrue(wait(10) { self.app.state == .runningForeground && self.app.navigationBars["OSC Routes"].exists },
                      "back in OSC Routes after saving")
        print("OSC-READY exported")
        pause(8)   // the driver copies the file and prints OSC-EXPORT-CHECK; the run's exit status carries it
    }

    /// FILE-012-T11: OSC traffic (the Mac's test value), then the App Privacy Report's page for projectM-iOS lists no
    /// website or domain. Skips when App Privacy Report is off: turning it on is a device setting (owner, once).
    func testFILE012AppPrivacyReport() throws {
        let task = "FILE-012-T11"
        listen("test")
        XCTAssertTrue(wait(10) { self.testValue.contains("0.42") }, "OSC traffic arrived")
        app.terminate()
        let settings = bridgePreferences
        settings.launch()
        func open(_ label: String) -> Bool {
            let cell = settings.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
            for _ in 0..<12 where !(cell.exists && cell.isHittable) { settings.swipeUp(velocity: .slow) }
            guard cell.exists && cell.isHittable else { return false }
            cell.tap()
            pause(1)
            return true
        }
        XCTAssertTrue(open("Privacy & Security"), "Settings › Privacy & Security")
        XCTAssertTrue(open("App Privacy Report"), "App Privacy Report")
        if settings.buttons["Turn On App Privacy Report"].exists {
            settings.terminate()
            throw XCTSkip("App Privacy Report is off on this device: the owner turns it on once (a device setting); "
                          + "then rerun after some OSC traffic")
        }
        let page = open("projectM-iOS") || open("projectM")
        let texts = settings.staticTexts.allElementsBoundByIndex.map(\.label)
        let domain = try NSRegularExpression(pattern: #"\b[a-z0-9-]+\.(com|net|org|io|app|dev|cloud|apple)\b"#, options: [.caseInsensitive])
        let domains = texts.filter { domain.firstMatch(in: $0, range: NSRange($0.startIndex..., in: $0)) != nil }
        report(task, "app privacy report", ["appListed": page ? 1 : 0, "domains": Double(domains.count)])
        XCTAssertTrue(domains.isEmpty, "projectM-iOS contacted no domain: \(domains)")
        settings.terminate()
    }
}

/// Two-device OSC (D1 + D2 on the Mac's Wi-Fi), started by scripts/mac_driver/peer.py, which sets `TEST_RUNNER_PEER_IP`
/// (the other device's address) and `TEST_RUNNER_MAC_IP`, starts the waiting role first and the acting role on its
/// `PEER-READY` line. Each role checks what it can see itself; peer.py pairs the `PEER-STEP`/`PEER-SEEN` lines.
/// OSC-008-T13 (receiver on D1, sender on D2), OSC-011-T19 (find on D1, announce on D2), OSC-012-T22 (lead on D1,
/// follow on D2; its Wi-Fi outage part is not required, owner ruling 2026-11-18).
@MainActor
final class B09OSCPeerDeviceTests: ControlSurfaceCase {
    private var testValue: String { text("oscTestValue") }

    private func launchPeer(_ settings: [String: Any], showSeed: Bool = false, section: Bool = true) {
        var values: [String: Any] = ["settings.osc.enabled": true, "settings.osc.port": 9000]
        values.merge(settings) { (_: Any, given: Any) -> Any in given }
        launch(visual: "circularSpectrum", settings: values,
               extra: (showSeed ? ["-uitestShowSeed"] : []) + (section ? ["-uitestSettingsSection", "osc"] : []))
    }

    private func openOSCScreen(_ link: String, title: String) {
        if !app.navigationBars["Settings"].exists { openSettingsPanel() }
        let row = app.buttons[link].firstMatch
        XCTAssertTrue(scrollTo(row), "\(link) is in the OSC section")
        row.tap()
        XCTAssertTrue(wait(5) { self.app.navigationBars[title].exists }, title)
    }

    /// The "Recently blocked" rows' addresses (Approved Devices).
    private func blockedHosts() -> [String] {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'oscBlockedPeer_'"))
            .allElementsBoundByIndex.map(\.label)
    }

    // MARK: OSC-008-T13

    /// D1: only D2 approved, so the Mac's 0.42 is blocked and listed; then only the Mac, so the Mac's 0.43 applies and
    /// D2 (still sending) is listed as blocked.
    func testOSC008AllowlistReceiver() throws {
        let task = "OSC-008-T13"
        let peer = try requireRunnerValue("PEER_IP", "the sender device's address"), mac = try requireRunnerValue("MAC_IP", "the Mac's address")
        launchPeer(["settings.osc.peerAllowlist.enabled": true, "settings.osc.approvedPeers": [peer]])
        openSettingsPanel()
        ready("PEER", "osc008-receiver")
        print("OSC-READY test")
        pause(12)
        XCTAssertFalse(testValue.contains("0.42"), "the Mac is not approved: its 0.42 does not apply (\(testValue))")
        openOSCScreen("oscPeersLink", title: "Approved Devices")
        let macBlocked = wait(20) { self.blockedHosts().contains { $0.contains(mac) } }
        let peerBlockedA = blockedHosts().contains { $0.contains(peer) }
        report(task, "only D2 approved", ["macBlocked": macBlocked ? 1 : 0, "peerBlocked": peerBlockedA ? 1 : 0])
        XCTAssertTrue(macBlocked, "the Mac is listed as blocked: \(blockedHosts())")
        XCTAssertFalse(peerBlockedA, "D2 is approved, never blocked: \(blockedHosts())")
        // Only the Mac: remove D2, allow the Mac from Recently blocked.
        let remove = app.buttons["oscRemovePeer_0"].firstMatch
        XCTAssertTrue(scrollTo(remove, up: true), "D2's Remove")
        remove.tap()
        let rows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'oscBlockedPeer_'"))
        if let index = rows.allElementsBoundByIndex.firstIndex(where: { $0.label.contains(mac) }) {
            let allow = app.buttons["oscAllowPeer_\(index)"].firstMatch
            XCTAssertTrue(scrollTo(allow), "Allow beside the Mac")
            allow.tap()
        }
        goBack()
        print("OSC-READY test2")
        let applied = wait(20) { self.testValue.contains("0.43") }
        openOSCScreen("oscPeersLink", title: "Approved Devices")
        let peerBlocked = wait(25) { self.blockedHosts().contains { $0.contains(peer) } }
        report(task, "only the Mac approved", ["macApplied": applied ? 1 : 0, "peerBlocked": peerBlocked ? 1 : 0])
        XCTAssertTrue(applied, "the approved Mac's 0.43 applies: \(testValue)")
        XCTAssertTrue(peerBlocked, "D2, no longer approved, is blocked: \(blockedHosts())")
        ready("PEER", "osc008-done")
    }

    /// D2: Send OSC to D1 (scene and status messages), stepping the show every 3 s for about two minutes.
    func testOSC008AllowlistSender() throws {
        let peer = try requireRunnerValue("PEER_IP", "the receiver device's address")
        launchPeer(["settings.osc.send.enabled": true, "settings.osc.send.host": peer, "settings.osc.send.port": 9000,
                    "settings.osc.send.kinds": ["scene", "status"]], showSeed: true, section: false)
        ready("PEER", "osc008-sender")
        sendSteps(seconds: 110)
    }

    /// Cue steps up and back down the five-cue seed (each step is one /projectm/scene message).
    private func sendSteps(seconds: Double, every interval: Double = 3, log: Bool = false) {
        let end = Date().addingTimeInterval(seconds)
        var up = true, n = 1
        while Date() < end {
            showControlsBar()
            let button = app.buttons[up ? "showNextCue" : "showPreviousCue"].firstMatch
            if button.exists { button.tap() }
            n += up ? 1 : -1
            if n >= 5 { up = false } else if n <= 1 { up = true }
            if log { print("PEER-STEP cue=\(appliedCue() ?? -1) t=\(Date().timeIntervalSince1970)") }
            pause(interval)
        }
    }

    // MARK: OSC-011-T19

    /// D2: announce, with "Only approved devices" on and nobody approved: D1's datagrams are listed under Recently
    /// blocked with D1's address, which proves they arrived (and that discovery never trusts a found device).
    func testOSC011Announce() throws {
        let task = "OSC-011-T19"
        let peer = try requireRunnerValue("PEER_IP", "the finding device's address")
        launchPeer(["settings.osc.discovery.advertise": true, "settings.osc.peerAllowlist.enabled": true,
                    "settings.osc.approvedPeers": [String]()])
        openOSCScreen("oscPeersLink", title: "Approved Devices")
        ready("PEER", "osc011-announce")
        let start = Date()
        let received = wait(150) { self.blockedHosts().contains { $0.contains(peer) } }
        report(task, "announce", ["receivedFromD1": received ? 1 : 0, "seconds": Date().timeIntervalSince(start)])
        XCTAssertTrue(received, "D1 found this device and sent to it: \(blockedHosts())")
    }

    /// D1: find D2 within 10 s with its address, Use as send destination, Send OSC on, step the show; Find off
    /// empties the list.
    func testOSC011Find() throws {
        let task = "OSC-011-T19"
        let peer = try requireRunnerValue("PEER_IP", "the announcing device's address")
        launchPeer(["settings.osc.discovery.browse": true, "settings.osc.send.kinds": ["scene", "status"]], showSeed: true)
        openOSCScreen("oscDiscoveryLink", title: "Nearby Devices")
        let start = Date()
        let peers = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'oscDiscoveredPeer_'"))
        let found = wait(10) { peers.allElementsBoundByIndex.contains { $0.label.contains(peer) } }
        let seconds = Date().timeIntervalSince(start)
        report(task, "find", ["found": found ? 1 : 0, "seconds": seconds])
        XCTAssertTrue(found, "D2 is listed with its address within 10 s: \(peers.allElementsBoundByIndex.map(\.label))")
        guard let index = peers.allElementsBoundByIndex.firstIndex(where: { $0.label.contains(peer) }) else { return }
        let use = app.buttons["oscDiscoveryUseAsDestination_\(index)"].firstMatch
        XCTAssertTrue(scrollTo(use), "Use as send destination")
        use.tap()
        goBack()
        openOSCScreen("oscSendLink", title: "Send OSC")
        XCTAssertEqual(app.textFields["oscSendHost"].firstMatch.value as? String, peer, "the found address is the destination")
        setSwitch("oscSendToggle", on: true)
        goBack()
        closeSettingsPanel()
        sendSteps(seconds: 30)
        openSettingsPanel()
        openOSCScreen("oscDiscoveryLink", title: "Nearby Devices")
        setSwitch("oscDiscoveryBrowseToggle", on: false)
        let emptied = wait(5) { peers.count == 0 }
        report(task, "find off", ["emptied": emptied ? 1 : 0])
        XCTAssertTrue(emptied, "Find off empties the list")
        ready("PEER", "osc011-done")
    }

    // MARK: OSC-012-T22

    /// D1 leads: approved D2, Send OSC to D2, a cue step every 4 s for two minutes (`PEER-STEP` lines for peer.py).
    func testOSC012Lead() throws {
        let peer = try requireRunnerValue("PEER_IP", "the following device's address")
        launchPeer(["settings.osc.cueSync.role": "lead", "settings.osc.peerAllowlist.enabled": true,
                    "settings.osc.approvedPeers": [peer], "settings.osc.send.enabled": true,
                    "settings.osc.send.host": peer, "settings.osc.send.port": 9000,
                    "settings.osc.send.kinds": ["scene", "status"]], showSeed: true, section: false)
        ready("PEER", "osc012-lead")
        sendSteps(seconds: 120, every: 4, log: true)
    }

    /// D2 follows: every cue change is printed (`PEER-SEEN`) for peer.py, which pairs it with D1's `PEER-STEP` and
    /// checks each lands within 0.5 s (device clocks are NTP-synced; the pairing reports the offset it assumed).
    /// The 10 s Wi-Fi outage needs D2 on the USB cable: not required (owner ruling 2026-11-18).
    func testOSC012Follow() throws {
        let task = "OSC-012-T22"
        let peer = try requireRunnerValue("PEER_IP", "the leading device's address")
        launchPeer(["settings.osc.cueSync.role": "follow", "settings.osc.peerAllowlist.enabled": true,
                    "settings.osc.approvedPeers": [peer]], showSeed: true, section: false)
        ready("PEER", "osc012-follow")
        var last = appliedCue(), changes = 0
        let end = Date().addingTimeInterval(150)
        while Date() < end && changes < 12 {
            let cue = appliedCue()
            if cue != last {
                changes += 1
                last = cue
                print("PEER-SEEN cue=\(cue ?? -1) t=\(Date().timeIntervalSince1970)")
            }
            pause(0.05)
        }
        report(task, "follow", ["changes": Double(changes)])
        XCTAssertGreaterThanOrEqual(changes, 4, "D2 follows D1's cue steps")
        ready("PEER", "osc012-done")
    }
}
