// SystemUI.swift — QA-011 device automation, the shared driver for iOS's own UI (automation plan "Shared pieces",
// built by Batch 1; the other batches use it read-only). Everything here drives public XCUITest API on a physical
// device: springboard (alerts, Control Center, the app switcher), the Settings app (the app's own permission page,
// Accessibility, Battery), Clock (a timer as a real audio interruption), Siri, the Files and
// Photos pickers and the share sheet the app presents, and the Camera app. No Airplane Mode or Wi-Fi helper: steps
// that need the USB cable are not required (owner ruling 2026-11-18).
//
// Use: keep one instance per test and restore it in tearDown, so a test never leaves a device setting changed:
//
//     private lazy var system = SystemUI(app: app)
//     override func tearDown() async throws { system.restore(); try await super.tearDown() }
//
// Every setter records how to undo what it changed (only when it changed something) and `restore()` undoes it in
// reverse order. Pass `keep: true` to leave a change in place on purpose (the prompt flow's final grants).
//
// Rules (owner rules 7, 14; docs/autotester.md):
// * Prompts: a helper never answers a prompt by itself, except `answerAlert`, which a test calls on purpose. Only
//   PromptFlowDeviceTests answers permission prompts; every unattended batch excludes it.
// * Settings' layout differs between iOS 26 and 27 and between iPhone and iPad (split view): rows are found by their
//   visible label, scrolled into view, with a search-field fallback. Check a new helper on D1 first.
// * Coordinates (Control Center, the switcher) assume portrait; rotate back to portrait first.
// * The Mac: `MacDriver.request(...)` prints a `MAC-DO {json}` line that scripts/mac_device_driver.py follows in
//   the xcodebuild log. The log reaches the Mac late: wait on an app probe, never on the Mac.
// Simulator results are never evidence; this file is meant for D1-D3.
import UIKit
import XCTest

/// A permission row on the app's own page in Settings (Settings › Apps › projectM).
enum AppPermission: String, CaseIterable {
    case camera = "Camera"
    case microphone = "Microphone"
    case localNetwork = "Local Network"
    /// A row with a choice page, not a switch: on = "Add Photos Only", off = "None" (the app asks add-only access).
    case photos = "Photos"
}

/// A system setting that `SystemUI.toggleAccessibility` can change, with its path from the Settings root.
enum SystemSetting: CaseIterable {
    case reduceMotion, increaseContrast, grayscale, differentiateWithoutColor, smartInvert, lowPower

    /// Rows to tap from the Settings root, then the switch's label.
    var path: (rows: [String], switchLabel: String) {
        switch self {
        case .reduceMotion: return (["Accessibility", "Motion"], "Reduce Motion")
        case .increaseContrast: return (["Accessibility", "Display & Text Size"], "Increase Contrast")
        case .differentiateWithoutColor: return (["Accessibility", "Display & Text Size"], "Differentiate Without Color")
        case .smartInvert: return (["Accessibility", "Display & Text Size"], "Smart Invert")
        case .grayscale: return (["Accessibility", "Display & Text Size", "Color Filters"], "Color Filters")
        case .lowPower: return (["Battery"], "Low Power Mode")
        }
    }
}

@MainActor
final class SystemUI {
    static let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    static let preferences = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
    static let clock = XCUIApplication(bundleIdentifier: "com.apple.mobiletimer")
    static let camera = XCUIApplication(bundleIdentifier: "com.apple.camera")
    static let photosApp = XCUIApplication(bundleIdentifier: "com.apple.mobileslideshow")
    /// The app's name on the Home Screen and in Settings (CFBundleDisplayName in project.yml).
    static let appDisplayName = "projectM"

    var springboard: XCUIApplication { Self.springboard }
    var preferences: XCUIApplication { Self.preferences }
    let app: XCUIApplication

    private var undo: [(name: String, action: () -> Void)] = []

    init(app: XCUIApplication) {
        self.app = app
    }

    // MARK: Restore

    /// Undoes every recorded change, newest first, and brings the app back if it was running. Call from tearDown.
    func restore() {
        let steps = undo.reversed()
        undo.removeAll()
        for step in steps {
            print("SYSTEM-UI restore: \(step.name)")
            step.action()
        }
        if !steps.isEmpty {
            preferences.terminate()
            if app.state != .notRunning { app.activate() }
        }
    }

    private func remember(_ name: String, keep: Bool, _ action: @escaping () -> Void) {
        if !keep { undo.append((name, action)) }
    }

    /// Drops the recorded undo steps for one setting (names starting with `prefix`): a later `keep: true` change sets
    /// its final state, so an earlier undo of it is obsolete. CAM-013-T17 (D2 pass 4, 2026-11-19) revoked the camera,
    /// granted it again with `keep: true`, and tearDown still ran "Camera on": a second trip to Settings whose query
    /// on the backgrounded Settings app timed out (3 × 30 s, "Timed out while evaluating UI query").
    private func forget(_ prefix: String) {
        undo.removeAll { $0.name.hasPrefix(prefix) }
    }

    // MARK: Waiting

    func pause(_ seconds: Double) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    /// Polls every 0.2 s (checks at once first); false after `seconds`.
    func wait(_ seconds: Double, _ condition: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while true {
            if condition() { return true }
            if Date() >= end { return false }
            pause(0.2)
        }
    }

    // MARK: Alerts (springboard)

    /// Spellings iOS uses for the same answer (the curly apostrophe in "Don’t Allow" is iOS's own).
    static func synonyms(_ button: String) -> [String] {
        switch button {
        case "Allow": return ["Allow", "Allow Access", "OK", "Allow While Using App", "Allow Full Access"]
        case "Don't Allow", "Don’t Allow": return ["Don’t Allow", "Don't Allow"]
        default: return [button]
        }
    }

    /// The first system alert, if one is shown within `timeout` seconds.
    func systemAlert(timeout: Double = 0) -> XCUIElement? {
        let alert = springboard.alerts.firstMatch
        return wait(timeout, { alert.exists }) ? alert : nil
    }

    /// All the text of a system alert (title, message, buttons), for asserting which prompt it is.
    func alertText(_ alert: XCUIElement) -> String {
        // iPadOS 27.2 nests each button in a copy of itself and the alert's tree changes while it animates in or out:
        // an index read after the count can find nothing ("No matches found for Element at index 2", D2 prompt flow
        // 2026-11-19), so only elements that still exist are read.
        let present = { (query: XCUIElementQuery) in query.allElementsBoundByIndex.filter(\.exists).map(\.label) }
        return ([alert.label] + present(alert.staticTexts) + present(alert.buttons)).joined(separator: " | ")
    }

    /// Waits up to `timeout` s for a system alert and taps `button` (or one of its synonyms). Returns the alert's
    /// text, or nil when no alert came. Only the prompt flow calls this for permission prompts (owner rule 14).
    @discardableResult
    func answerAlert(_ button: String, timeout: Double = 10) -> String? {
        guard let alert = systemAlert(timeout: timeout) else { return nil }
        let text = alertText(alert)
        print("SYSTEM-UI alert: \(text) -> \(button)")
        for name in Self.synonyms(button) {
            guard let target = alertButton(alert, name) else { continue }
            target.tap()
            _ = wait(5) { !alert.exists }
            return text
        }
        XCTFail("the alert has no \(button) button: \(text)")
        return text
    }

    /// The alert's button `name` (identifier or label), one element: the first hittable match, else the first match.
    /// iPadOS 27.2 exposes each permission prompt button twice, nested (`kTCCServiceCamera-deny-button` inside
    /// itself; D2 2026-11-19), so tapping `alert.buttons[name]` failed with "Multiple matching elements found".
    func alertButton(_ alert: XCUIElement, _ name: String) -> XCUIElement? {
        let matches = alert.buttons.matching(identifier: name).allElementsBoundByIndex
        guard let first = matches.first else { return nil }
        return matches.first { $0.isHittable } ?? first
    }

    // MARK: Settings app

    /// Settings, freshly launched at its root list. Settings reopens on the page it showed last (D1, iOS 27.0.1,
    /// 2026-11-18: no Accessibility or Battery row after a relaunch), so pushed pages are popped first.
    func openSettingsRoot() {
        preferences.terminate()
        preferences.launch()
        XCTAssertTrue(preferences.wait(for: .runningForeground, timeout: 10), "Settings is in front")
        let back = NSPredicate(format: "identifier == 'BackButton' OR label == 'Back' OR label == 'Settings'")
        for _ in 0..<5 {
            let button = preferences.navigationBars.buttons.matching(back).firstMatch
            guard button.exists, button.isHittable else { break }
            button.tap()
            pause(0.6)
        }
    }

    /// The Settings lists on screen, the one to scroll first first. On an iPad (and iOS 27's iPhone layout) the root
    /// rows sit in `com.apple.settings.sidebar.collectionView` and a page's rows in the detail list beside it; scrolling
    /// `collectionViews.firstMatch` moved the sidebar while the row looked for was on the page (D2, 2026-11-18).
    private func settingsLists(in application: XCUIApplication, root: Bool) -> [XCUIElement] {
        let screen = application.windows.firstMatch.frame
        let shown = (application.collectionViews.allElementsBoundByIndex + application.tables.allElementsBoundByIndex)
            .filter { $0.exists && $0.frame.width > 0 && screen.intersects($0.frame) }
        let sidebar = shown.filter { $0.identifier.contains("sidebar") }
        let pages = shown.filter { !$0.identifier.contains("sidebar") }
        let ordered = root ? sidebar + pages : pages + sidebar
        return ordered.isEmpty ? [application.windows.firstMatch] : ordered
    }

    /// A row of the frontmost Settings page by its visible label (cells, buttons or texts, first match).
    func settingsRow(_ label: String) -> XCUIElement {
        let byLabel = NSPredicate(format: "label == %@", label)
        for query in [preferences.cells, preferences.buttons, preferences.staticTexts] {
            let match = query.matching(byLabel).firstMatch
            if match.exists { return match }
        }
        return preferences.cells.matching(byLabel).firstMatch
    }

    /// Scrolls the Settings lists until `element` is hittable (at most `swipes` slow swipes each way per list): the
    /// list that holds it when it exists, else the page list first (the sidebar first for a root row, `root`).
    @discardableResult
    func scrollTo(_ element: XCUIElement, in application: XCUIApplication, swipes: Int = 8, root: Bool = false) -> Bool {
        if element.exists && element.isHittable { return true }
        var lists = settingsLists(in: application, root: root)
        if element.exists {
            let x = element.frame.midX
            lists = lists.filter { $0.frame.minX <= x && x <= $0.frame.maxX } + lists.filter { !($0.frame.minX <= x && x <= $0.frame.maxX) }
        }
        for list in lists.prefix(2) {
            for _ in 0..<swipes where !(element.exists && element.isHittable) { list.swipeUp(velocity: .slow) }
            for _ in 0..<swipes where !(element.exists && element.isHittable) { list.swipeDown(velocity: .slow) }
            if element.exists && element.isHittable { return true }
        }
        return element.exists && element.isHittable
    }

    /// Taps the Settings row `label`, scrolling to it first; false when it cannot be found. `root`: a row of the
    /// Settings root (the sidebar on an iPad).
    @discardableResult
    func tapSettingsRow(_ label: String, root: Bool = false) -> Bool {
        _ = wait(3) { self.settingsRow(label).exists }
        var row = settingsRow(label)
        if !scrollTo(row, in: preferences, root: root) {
            row = settingsRow(label)   // re-resolve after scrolling (cells are reused)
            guard row.exists, row.isHittable else { return false }
        }
        row.tap()
        pause(0.6)
        return true
    }

    /// Walks `rows` from the Settings root.
    func openSettings(path rows: [String]) {
        openSettingsRoot()
        for (i, row) in rows.enumerated() {
            XCTAssertTrue(tapSettingsRow(row, root: i == 0), "Settings row \(row)")
        }
    }

    /// The app's own page: Settings › Apps › projectM (iOS 18 and later), found by scrolling or the Apps search field.
    /// If Settings is already in front on that page (after the app's "Open Settings" button), it is used as is.
    func openAppSettingsPage() {
        // Only while Settings, not the app, is in front: a query on a Settings app sent to the background never
        // answers (D2 pass 4, 2026-11-19: 3 × 30 s "Timed out while evaluating UI query" in CAM-013's tearDown).
        if preferences.state == .runningForeground, app.state != .runningForeground,
           preferences.navigationBars[Self.appDisplayName].exists { return }
        openSettingsRoot()
        // Settings' own search first: it lists the app's page on every layout. On iPadOS 27.2 (D2, 2026-11-18) no
        // "Apps" row was found in the sidebar after 16 swipes, and the pre-iOS 18 fallback found no app row either.
        if searchSettings(for: Self.appDisplayName),
           wait(5, { self.preferences.navigationBars[Self.appDisplayName].exists }) { return }
        openSettingsRoot()
        if tapSettingsRow("Apps", root: true) {
            let search = preferences.searchFields.firstMatch
            if search.waitForExistence(timeout: 2) {
                search.tap()
                search.typeText(Self.appDisplayName)
                pause(1)
            }
            XCTAssertTrue(tapSettingsRow(Self.appDisplayName), "the app in Settings › Apps")
        } else {
            XCTAssertTrue(tapSettingsRow(Self.appDisplayName, root: true), "the app in Settings (pre-iOS 18 layout)")
        }
        let shown = wait(5) { self.preferences.navigationBars[Self.appDisplayName].exists }
        if !shown { print("SYSTEM-UI app page not reached; Settings shows:\n\(preferences.debugDescription.prefix(6000))") }
        XCTAssertTrue(shown, "the app's Settings page is shown")
    }

    /// Types `text` into the Settings root's search field and taps the first result named exactly `text` (a cell,
    /// button or text; the app's row also carries a subtitle on some releases, so a prefix match is the fallback).
    /// False when there is no search field or no such result.
    @discardableResult
    func searchSettings(for text: String) -> Bool {
        let search = preferences.searchFields.firstMatch
        guard search.waitForExistence(timeout: 3) else { return false }
        search.tap()
        search.typeText(text)
        pause(1.5)
        let exact = NSPredicate(format: "label == %@", text), prefix = NSPredicate(format: "label BEGINSWITH %@", text)
        for predicate in [exact, prefix] {
            for query in [preferences.cells, preferences.buttons, preferences.staticTexts] {
                // Skip the search field itself, whose text is `text`, wherever it sits: at the top on iPadOS, at the
                // bottom of the screen on iOS 27 for iPhone (D1, 2026-11-22: every result sat above it, so the old
                // "below the field" filter found none and FILE-013 stayed in Settings).
                let field = search.frame
                let match = query.matching(predicate).allElementsBoundByIndex
                    .first { $0.elementType != .searchField && $0.isHittable && !$0.frame.intersects(field) }
                if let match {
                    match.tap()
                    pause(0.8)
                    return true
                }
            }
        }
        print("SYSTEM-UI search \(text): no result")
        return false
    }

    /// A Settings switch's state: "1"/"0" (or "On"/"Off", "true"/"false" on some releases, or a number).
    func isOn(_ element: XCUIElement) -> Bool { switchState(element) ?? false }

    /// The switch's state, or nil when its value is unreadable.
    func switchState(_ element: XCUIElement) -> Bool? {
        switch element.value {
        case let number as NSNumber: return number.boolValue
        case let text as String:
            switch text.lowercased() {
            case "1", "on", "true": return true
            case "0", "off", "false": return false
            default: return nil
            }
        default: return nil
        }
    }

    /// The switch labelled `label` on the frontmost Settings page (the switch itself, or its row's switch).
    func settingsSwitch(_ label: String) -> XCUIElement {
        let byLabel = NSPredicate(format: "label == %@", label)
        let direct = preferences.switches.matching(byLabel).firstMatch
        if direct.exists { return direct }
        return settingsRow(label).switches.firstMatch
    }

    /// Sets a Settings switch; returns its previous state, or nil when there is no such switch. Taps the switch's
    /// knob side (a centre tap can hit the label: docs/autotester.md, OSC-007) and falls back to a plain tap.
    @discardableResult
    func setSwitch(_ label: String, on: Bool) -> Bool? {
        let toggle = settingsSwitch(label)
        guard wait(3, { toggle.exists }) else { return nil }
        scrollTo(toggle, in: preferences)
        let readable = switchState(toggle) != nil
        let before = isOn(toggle)
        print("SYSTEM-UI switch \(label): value=\(String(describing: toggle.value)) frame=\(toggle.frame) want=\(on)")
        if before != on {
            // The knob, 26 pt in from the element's trailing edge: the element can be the whole row (iPadOS 27.2, D2),
            // where 90 % of its width is not on the knob and a centre tap lands on the label.
            let frame = toggle.frame
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5))
                .withOffset(CGVector(dx: max(frame.width - 26, frame.width / 2), dy: 0)).tap()
            // A second tap only when the state is readable and unchanged: a blind one turns the switch back off.
            if readable, !wait(3, { self.isOn(toggle) == on }) { toggle.tap() }
            XCTAssertTrue(wait(5) { self.isOn(toggle) == on },
                          "\(label) is \(on ? "on" : "off") (value \(String(describing: toggle.value)))")
        }
        return before
    }

    // MARK: The app's permissions

    /// Turns one of the app's permissions on or off on its Settings page. Revoking a permission while the app runs
    /// makes iOS end the app (a SIGKILL, not a crash): relaunch it afterwards. Returns false when the page has no
    /// such row (iOS lists a permission only after the app has asked for it once).
    @discardableResult
    func setAppPermission(_ permission: AppPermission, on: Bool, keep: Bool = false) -> Bool {
        openAppSettingsPage()
        if permission == .photos {
            let row = settingsRow(AppPermission.photos.rawValue)
            guard wait(3, { row.exists }) else { return false }
            let before = (row.value as? String) ?? ""
            guard scrollTo(row, in: preferences) else { return false }
            row.tap()
            let choice = on ? "Add Photos Only" : "None"
            XCTAssertTrue(tapSettingsRow(choice), "Photos › \(choice)")
            if keep { forget("Photos ") }
            if before != choice, !before.isEmpty {
                let previous = before
                remember("Photos \(previous)", keep: keep) { [weak self] in
                    guard let self else { return }
                    self.openAppSettingsPage()
                    if self.tapSettingsRow(AppPermission.photos.rawValue) { self.tapSettingsRow(previous) }
                }
            }
            return true
        }
        guard let before = setSwitch(permission.rawValue, on: on) else { return false }
        if keep { forget("\(permission.rawValue) ") }
        if before != on {
            remember("\(permission.rawValue) \(before ? "on" : "off")", keep: keep) { [weak self] in
                guard let self else { return }
                self.openAppSettingsPage()
                self.setSwitch(permission.rawValue, on: before)
            }
        }
        return true
    }

    // MARK: Accessibility, Battery

    /// Changes a system setting in Settings while the app keeps running, then brings the app back to the front.
    /// Grayscale turns on Color Filters and picks Grayscale (the filter's first choice).
    func toggleAccessibility(_ setting: SystemSetting, on: Bool, keep: Bool = false) {
        let (rows, label) = setting.path
        openSettings(path: rows)
        guard let before = setSwitch(label, on: on) else {
            XCTFail("no \(label) switch in Settings › \(rows.joined(separator: " › "))")
            return
        }
        if setting == .grayscale, on { tapSettingsRow("Grayscale") }
        if before != on {
            remember("\(label) \(before ? "on" : "off")", keep: keep) { [weak self] in
                self?.openSettings(path: rows)
                self?.setSwitch(label, on: before)
            }
        }
        backToApp()
    }

    /// Brings the app back to the front if it is running; a test that has not launched it yet launches it itself
    /// (`activate()` would launch it without the test's arguments).
    func backToApp() {
        guard app.state != .notRunning else { return }
        app.activate()
        _ = app.wait(for: .runningForeground, timeout: 10)
    }

    // MARK: Control Center

    /// Control Center's own buttons, used to tell it is open.
    private var controlCenterMarker: XCUIElement {
        springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "label IN %@", ["Wi-Fi", "Airplane Mode", "Bluetooth", "Screen Mirroring", "Focus"]))
            .firstMatch
    }

    /// Control Center's own buttons are shown. Not while Settings is in front: springboard's queries reach into the
    /// front app's windows (its full-screen "projectM" card matched in CAM-001), and Settings has rows of the same
    /// names. D2 pass 4 (2026-11-19, CAM-013 tearDown): with Settings in front and Control Center closed a marker
    /// matched, closeControlCenter swiped up, which went Home, and the restore that followed queried a backgrounded
    /// Settings app until it timed out. No test opens Control Center over Settings.
    var controlCenterIsOpen: Bool {
        if preferences.state == .runningForeground { return false }
        return controlCenterMarker.exists
    }

    /// Opens Control Center with a swipe down from the top-right corner (iPhone with Face ID, iPad), portrait.
    @discardableResult
    func openControlCenter() -> Bool {
        let start = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.002))
        let end = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.55))
        start.press(forDuration: 0.1, thenDragTo: end)
        return wait(4) { self.controlCenterIsOpen }
    }

    /// Closes Control Center (swipe up from the bottom), back to the app.
    func closeControlCenter() {
        guard controlCenterIsOpen else { return }
        let start = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.97))
        let end = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
        start.press(forDuration: 0.05, thenDragTo: end)
        if !wait(3, { !self.controlCenterIsOpen }) { app.activate() }
    }

    /// The privacy header Control Center shows while an app uses the camera or microphone ("projectM" with the
    /// sensor): the stand-in for iOS's camera indicator, which a screenshot may not show. Opens and closes Control
    /// Center; returns the header's text, or nil when nothing names the app.
    func controlCenterPrivacyUser() -> String? {
        guard openControlCenter() else { return nil }
        pause(0.8)
        let named = springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", Self.appDisplayName)).firstMatch
        let text: String? = named.exists ? named.label : nil
        closeControlCenter()
        return text
    }

    /// iOS's green camera dot (or orange microphone dot) in a fresh screenshot's top-right status area: true when
    /// enough saturated green (`green: true`) or orange pixels are there. A screenshot may not include the system's
    /// privacy indicator; check this on D1 against `controlCenterPrivacyUser()` before relying on it.
    func statusIndicatorDotVisible(green: Bool = true) -> Bool {
        guard let cg = XCUIScreen.main.screenshot().image.cgImage else { return false }
        let width = cg.width, height = max(1, cg.height / 18)
        var data = [UInt8](repeating: 0, count: width * height * 4)
        data.withUnsafeMutableBytes { (buffer: UnsafeMutableRawBufferPointer) -> Void in
            guard let ctx = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            // The top 1/18 of the screen, drawn at its own size (CoreGraphics' origin is bottom-left).
            ctx.draw(cg, in: CGRect(x: 0, y: height - cg.height, width: width, height: cg.height))
        }
        var hits = 0
        for y in 0..<height {
            for x in (width / 2)..<width {
                let i = (y * width + x) * 4
                let r = Int(data[i]), g = Int(data[i + 1]), b = Int(data[i + 2])
                if green ? (g > 170 && r < 110 && b < 130) : (r > 220 && g > 110 && g < 190 && b < 80) { hits += 1 }
            }
        }
        return hits >= 12
    }

    /// iPadOS Control Center's green privacy pill ("projectM  Controls ›" on system green, with a camera icon) in
    /// `screenshot`, taken while Control Center is open. On D2 (iPadOS 27.2) and D3 (26.5) the pill lives in a remote
    /// process whose accessibility tree XCUITest cannot read ("Ignoring failure to get hierarchy for remote element
    /// ... kAXErrorServerNotFound"), so no label names it (QA-011 pass 4, 2026-11-19). Measured on those screenshots:
    /// the pill is a system-green run of 182 pt (364 px: 22 % of D3's width, 18 % of D2's) in the top 5 % of the
    /// right half, 31 (D2) and 53 (D3) pixel rows matching this rule; once the camera is no longer in use the pill
    /// turns grey with only a small green icon (longest run 35 px, 0 rows). True when at least 8 pixel rows in the top
    /// 8 % of the right half hold a green run of 10-30 % of the screen's width (in pixels, so the screenshot's scale does not matter).
    func controlCenterGreenPillVisible(in screenshot: XCUIScreenshot) -> Bool {
        let image = screenshot.image
        guard let cg = image.cgImage else { return false }
        let width = cg.width, height = max(1, cg.height * 8 / 100)
        var data = [UInt8](repeating: 0, count: width * height * 4)
        data.withUnsafeMutableBytes { (buffer: UnsafeMutableRawBufferPointer) -> Void in
            guard let ctx = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            ctx.draw(cg, in: CGRect(x: 0, y: height - cg.height, width: width, height: cg.height))
        }
        let minRun = width / 10, maxRun = width * 3 / 10
        var rows = 0
        for y in 0..<height {
            var run = 0, longest = 0
            for x in (width / 2)..<width {
                let i = (y * width + x) * 4
                let r = Int(data[i]), g = Int(data[i + 1]), b = Int(data[i + 2])
                if g > 150 && g - r > 70 && g - b > 50 { run += 1; longest = max(longest, run) } else { run = 0 }
            }
            if longest >= minRun && longest <= maxRun { rows += 1 }
        }
        print("SYSTEM-UI Control Center green pill rows: \(rows) (width \(width) px)")
        return rows >= 8
    }

    // MARK: App switcher

    /// The app's bundle identifier (project.yml), which names its switcher card.
    static let appBundleID = "org.projectmios.ProjectMiOS"

    /// The app's card in the switcher: `card:<bundle id>:sceneID:…` (D1, iOS 27.0.1), else an element named like the
    /// app that is not a Home Screen or Dock icon. On an iPad the Dock stays up in the switcher and its "projectM" Icon
    /// came first, so the flick moved the icon and the app kept running (D2, D3, 2026-11-18).
    var appSwitcherCard: XCUIElement {
        let card = springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "card:\(Self.appBundleID)")).firstMatch
        if card.exists { return card }
        return springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "(label == %@ OR identifier == %@) AND elementType != %d", Self.appDisplayName,
                                  Self.appDisplayName, Int(XCUIElement.ElementType.icon.rawValue)))
            .firstMatch
    }

    /// Opens the app switcher: a slow swipe up from the bottom edge that holds in the middle (portrait).
    func openAppSwitcher() {
        let start = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.998))
        let end = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.58))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.9)
        pause(1)
    }

    /// Back into the app from the switcher: taps its card (or the screen centre, where the current card sits).
    func returnFromAppSwitcher() {
        let card = appSwitcherCard
        if card.exists, card.isHittable { card.tap() } else {
            springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap()
        }
        _ = app.wait(for: .runningForeground, timeout: 10)
    }

    /// In the open switcher, flicks the app's card up: the user's force quit. Waits until the app has ended, then
    /// goes to the Home Screen. Returns whether the app ended.
    /// 2026-11-19 (pass 3, D2 and D3): the card was found, but a press-then-drag to the top (750 pt/s, 0.8 s long) left
    /// the app running on both iPads: iPadOS takes a slow drag as moving the card and lets it settle back. The card
    /// is now flicked (a short, fast swipe up), up to three times, each followed by a check that the app ended.
    @discardableResult
    func forceQuitFromSwitcher() -> Bool {
        _ = wait(3) { self.appSwitcherCard.exists }
        var ended = false
        for attempt in 0..<3 where !ended {
            let card = appSwitcherCard
            print("SYSTEM-UI switcher card (flick \(attempt + 1)): "
                  + (card.exists ? "\(card.elementType.rawValue) \(card.identifier) \(card.frame)" : "none"))
            if card.exists, card.frame.height > 0 {
                if attempt == 0 {
                    card.swipeUp(velocity: XCUIGestureVelocity(rawValue: 3000))
                } else {
                    // A flick from the card's lower part: a tiny press, then a fast short drag well past its top.
                    let from = card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
                    let to = card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: -0.6))
                    from.press(forDuration: 0.01, thenDragTo: to, withVelocity: XCUIGestureVelocity(rawValue: 4000),
                               thenHoldForDuration: 0)
                }
            } else {
                let from = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
                let to = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
                from.press(forDuration: 0.01, thenDragTo: to, withVelocity: XCUIGestureVelocity(rawValue: 4000), thenHoldForDuration: 0)
            }
            ended = wait(4) { self.app.state == .notRunning }
        }
        XCUIDevice.shared.press(.home)
        return ended
    }

    // MARK: Clock timer (a real audio interruption)

    /// Starts a Clock timer of `seconds` (at least 1) and returns to the app. When it ends, its alarm interrupts
    /// the app's audio session like any alarm. Stopped again by `stopClockTimer()` (also on restore).
    func startClockTimer(seconds: Int) {
        // A timer left ringing by an earlier run that never reached its restore (the app was killed mid-test, D2
        // 2026-11-19: the alarm repeated until a person stopped it) is stopped first.
        let names = ["Stop", "Dismiss", "Stop Timer"]
        let ringing = springboard.buttons.matching(NSPredicate(format: "label IN %@ OR identifier IN %@", names, names)).firstMatch
        if ringing.exists { ringing.tap(); pause(0.5) }
        let clock = Self.clock
        clock.launch()
        XCTAssertTrue(clock.wait(for: .runningForeground, timeout: 10), "Clock is in front")
        // The Timers tab: a tab bar button on iOS 26; on iPadOS 27.2 (D2, 2026-11-18) the tab bar had no "Timers" or
        // "Timer" button, Clock stayed on another tab and no wheels were found, so any button of that name is tried.
        let tab = NSPredicate(format: "label IN %@ OR identifier IN %@", ["Timers", "Timer"], ["Timers", "Timer"])
        let tabButton = clock.tabBars.buttons.matching(tab).firstMatch.exists ? clock.tabBars.buttons.matching(tab).firstMatch
            : clock.buttons.matching(tab).firstMatch
        if wait(3, { tabButton.exists }) { tabButton.tap() }
        let wheels = clock.pickerWheels
        if wait(3, { wheels.count >= 3 }) {
            // hours, minutes, seconds
            adjustWheel(wheels.element(boundBy: 0), to: 0)
            adjustWheel(wheels.element(boundBy: 1), to: 0)
            adjustWheel(wheels.element(boundBy: 2), to: max(1, seconds))
        } else {
            print("SYSTEM-UI Clock has no timer wheels; Clock shows:\n\(clock.debugDescription.prefix(8000))")
            XCTFail("the Clock timer's wheels were not found")
        }
        let start = clock.buttons["Start"]
        XCTAssertTrue(wait(3) { start.exists }, "the timer's Start button")
        start.tap()
        remember("Clock timer", keep: false) { [weak self] in self?.stopClockTimer() }
        app.activate()
        _ = app.wait(for: .runningForeground, timeout: 10)
    }

    /// Sets a timer wheel to `number`. The wheels' values carry their unit ("0 hours", "1 hour" on iPadOS 26.5, D3
    /// 2026-11-18: a bare "0" was refused as not one of the values), so the value is built from the wheel's current
    /// one: the same unit, singular for 1 where the unit is a full word.
    func adjustWheel(_ wheel: XCUIElement, to number: Int) {
        let current = (wheel.value as? String) ?? ""
        let parts = current.split(separator: " ", maxSplits: 1).map(String.init)
        guard parts.count == 2, Int(parts[0]) != nil else {
            wheel.adjust(toPickerWheelValue: "\(number)")   // bare numbers (older releases)
            return
        }
        var unit = parts[1]
        let words = ["hour", "minute", "second"]
        if let word = words.first(where: { unit == $0 || unit == $0 + "s" }) { unit = number == 1 ? word : word + "s" }
        print("SYSTEM-UI wheel \(current) -> \(number) \(unit)")
        wheel.adjust(toPickerWheelValue: "\(number) \(unit)")
    }

    /// Stops a ringing timer from its alert or banner, or cancels a running one in Clock.
    ///
    /// On iPadOS 26.5 (D3, QA-011 pass 3, 2026-11-19) the ringing timer is a "Timer" banner at the top centre with a
    /// repeat and an X button; it stayed up (and the alarm kept its interruption: no `ended` in seven runs) until the
    /// test's teardown, covering the session panel's `session:routeLost`. Its X is matched by the usual stop/dismiss
    /// labels; when none matches, the banner's buttons are printed for the next run.
    func stopClockTimer() {
        let names = ["Stop", "Dismiss", "Close", "Clear", "Stop Timer"]
        let stop = springboard.buttons.matching(NSPredicate(format: "label IN %@ OR identifier IN %@", names, names)).firstMatch
        if wait(2, { stop.exists }) { stop.tap(); return }
        let banner = springboard.descendants(matching: .any).matching(NSPredicate(format: "label == 'Timer'")).firstMatch
        if banner.exists {
            print("SYSTEM-UI timer banner without a known stop button; SpringBoard buttons: "
                  + springboard.buttons.allElementsBoundByIndex.prefix(20).map { "\($0.identifier)|\($0.label)" }.joined(separator: ", "))
        }
        let clock = Self.clock
        guard clock.state != .notRunning else { return }
        clock.activate()
        for name in ["Stop", "Cancel"] where clock.buttons[name].exists {
            clock.buttons[name].tap()
            break
        }
        if app.state != .notRunning { app.activate() }
    }

    // MARK: Siri (a real interruption)

    /// Asks Siri `text` (typed recognition, no microphone), waits `seconds` and returns to the app. Siri must be on.
    /// Once a step in this run found Siri unreachable (`SiriAvailability.knownUnavailable`), it only sets
    /// `unavailableSeen` and returns, so the caller skips at once instead of waiting out XCUITest's 60 s timeout.
    func siriInterruption(_ text: String = "What time is it", seconds: Double = 4) {
        if SiriAvailability.knownUnavailable { SiriAvailability.unavailableSeen = true; return }
        XCUIDevice.shared.siriService.activate(voiceRecognitionText: text)
        if SiriAvailability.unavailableSeen {   // Siri did not come up: nothing to wait for
            app.activate()
            return
        }
        pause(seconds)
        app.activate()
        _ = app.wait(for: .runningForeground, timeout: 10)
    }

    // MARK: Pickers and sheets the app presents (out of process, listed in the app's tree)

    /// In the app's document picker (Files): the file `name` where the picker opened (it remembers the last folder,
    /// and the audio importer opens in Documents with DEBUG `-uitestPickerInDocuments`), else Browse, a location
    /// ("On My iPhone"/"On My iPad" when `path` is empty, then `projectM`), the folders in `path`, then the file; taps
    /// Open when the picker asks. When the file is not found the picker is cancelled, so the test's next steps act on
    /// the app again instead of failing behind a picker that is still up.
    ///
    /// QA-011 pass 3 (D3, iPadOS 26.5, 2026-11-19): the picker does list On My iPad › projectM and shows the seeded
    /// files, but a file's cell is labelled "<stem>, <extension>, <date>, <size>" (identifier "<stem>, <extension>"),
    /// so the old "label BEGINSWITH <name with extension>" never matched; and the grid shows 4 files per row, so most
    /// fixtures sit below the first screen. `fileItem` matches that label and `findFile` scrolls the grid
    /// ("File View").
    ///
    /// QA-011 pass 6 (D2, iPadOS 27.2, 2026-11-19, after a fresh reinstall): the picker opened one level up, in
    /// On My iPad, whose grid shows the projectM folder ("44 items") in its first row. The search for the file swiped
    /// that grid up 6-8 times, which scrolled the folder's row off the top; the sidebar's On My iPad was already
    /// selected, so tapping it left the grid scrolled, and "projectM" was no longer in the tree ("Files: no projectM"
    /// in PRE-012, PRE-014, MED-001, MED-002, MED-006, MED-008, MED-010, MED-014). In pass 5b the picker had
    /// remembered projectM itself. Now, when the grid where the picker opened shows the app's folder, the pick goes
    /// into it before looking for the file, and each place on the path is found by scrolling the grid back to the top
    /// and then down (`revealPlace`), so any starting location and scroll position works.
    @discardableResult
    func filesPick(path: [String] = [], name: String) -> Bool {
        if path.isEmpty {
            enterAppFolderIfShown()
            if findFile(name, initialWait: 3, swipes: 6) {   // the picker opened (or now is) where the file is
                if tapFile(name) { return true }
                XCTFail("Files: the picker did not take \(name)")
                cancelFilesPicker()
                return false
            }
        }
        let browse = app.buttons["Browse"].firstMatch   // the iPhone tab bar; iPadOS 26 nests a second Browse button
        if wait(3, { browse.exists }) { browse.tap(); pause(0.5) }
        let places = path.isEmpty ? [UIDevice.current.userInterfaceIdiom == .pad ? "On My iPad" : "On My iPhone",
                                     Self.appDisplayName] : path
        for place in places {
            guard let item = revealPlace(place, wait: 5) else {
                XCTFail("Files: no \(place)")
                cancelFilesPicker()
                return false
            }
            item.tap()
            pause(0.8)
        }
        guard findFile(name, initialWait: 5, swipes: 10) else {
            XCTFail("Files: no \(name) in \(places.joined(separator: " › "))")
            cancelFilesPicker()
            return false
        }
        if tapFile(name) { return true }
        XCTFail("Files: the picker did not take \(name)")
        cancelFilesPicker()
        return false
    }

    /// A cell of the picker's file grid for the folder `place`: labelled "projectM" or "projectM, 44 items", or
    /// holding a "projectM" text. Only grid cells, so the navigation title of the folder itself never counts.
    func gridPlace(_ place: String) -> XCUIElement? {
        let grid = app.collectionViews["File View"].firstMatch
        guard grid.exists else { return nil }
        let own = grid.cells.matching(NSPredicate(format: "label == %@ OR label BEGINSWITH %@", place, place + ","))
            .firstMatch
        if own.exists { return own }
        let holding = grid.cells.containing(NSPredicate(format: "label == %@", place)).firstMatch
        return holding.exists ? holding : nil
    }

    /// The location or folder `place`: its grid cell, else any element so labelled (the sidebar's locations).
    func placeItem(_ place: String) -> XCUIElement {
        gridPlace(place) ?? app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", place)).firstMatch
    }

    /// When the picker opened one level above the app's Documents (On My iPhone/iPad: its grid shows the app's
    /// folder), taps that folder. Waits up to 3 s for the grid's first cells; returns whether it went in.
    @discardableResult
    func enterAppFolderIfShown() -> Bool {
        let grid = app.collectionViews["File View"].firstMatch
        _ = wait(3, { grid.exists && grid.cells.count > 0 })
        guard gridPlace(Self.appDisplayName) != nil, let folder = revealPlace(Self.appDisplayName, wait: 0) else {
            return false
        }
        print("DEVICE-ACCEPT-NOTE the Files picker opened above \(Self.appDisplayName); going into it")
        folder.tap()
        pause(0.8)
        return true
    }

    /// Finds `place` from any scroll position: waits up to `seconds` for it on screen, then scrolls the file grid
    /// back to the top (at most 4 swipes down) and down again (at most 8 swipes up) until it is wholly shown and
    /// still. Returns that item, else an item so named that exists but could not be brought wholly into view (the
    /// tap is tried), else nil.
    func revealPlace(_ place: String, wait seconds: Double) -> XCUIElement? {
        if wait(seconds, { self.isFullyShown(self.placeItem(place)) }) { return placeItem(place) }
        let grid = app.collectionViews["File View"].firstMatch
        if grid.exists {
            for down in [false, true] {   // first back to the top, then down through the folder
                for _ in 0..<(down ? 8 : 4) {
                    if isFullyShown(placeItem(place)) {
                        settle(placeItem(place))
                        return placeItem(place)
                    }
                    if down { grid.swipeUp() } else { grid.swipeDown() }
                    pause(0.6)
                }
            }
            if isFullyShown(placeItem(place)) {
                settle(placeItem(place))
                return placeItem(place)
            }
        }
        let item = placeItem(place)
        return item.exists ? item : nil
    }

    /// How the Files picker names `name`: its own label (releases that show extensions), or the grid cell's
    /// "<stem>, <extension>" identifier and "<stem>, <extension>, <date>, <size>" label (iPadOS 26.5, 2026-11-19).
    static func fileItemPredicate(_ name: String) -> NSPredicate {
        let stem = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension
        var options = [NSPredicate(format: "label == %@", name), NSPredicate(format: "label BEGINSWITH %@", name + ",")]
        if !ext.isEmpty {
            let shown = "\(stem), \(ext)"
            options += [NSPredicate(format: "identifier == %@", shown), NSPredicate(format: "label BEGINSWITH %@", shown + ",")]
        }
        return NSCompoundPredicate(orPredicateWithSubpredicates: options)
    }

    /// The picker's item for `name`: its cell when the picker shows cells, else any element so named.
    func fileItem(_ name: String) -> XCUIElement {
        let cell = app.cells.matching(Self.fileItemPredicate(name)).firstMatch
        return cell.exists ? cell : app.descendants(matching: .any).matching(Self.fileItemPredicate(name)).firstMatch
    }

    /// Waits up to `initialWait` for `name` in the folder the picker shows, then scrolls the file grid down (at most
    /// `swipes` times) until its item is on screen.
    ///
    /// QA-011 rerun 3 (D3, iPadOS 26.5, 2026-11-19): after two swipes seed-damaged.m4a's cell sat on the screen's bottom
    /// edge, cut in half. XCUITest calls an element hittable when its centre point is on screen, so the cell counted as
    /// found; the tap landed on the edge and selected nothing (Open stayed disabled), the picker stayed up over the
    /// app, no import alert came, and the next step's Import Audio tap failed as "not hittable". An item now counts only
    /// when it is wholly inside the window, clear of the toolbar and the home indicator (`isFullyShown`); a partly shown
    /// item is brought in with a short, slow drag (`nudge`), an item off screen with a full swipe.
    ///
    /// QA-011 pass 4 (D2, iPadOS 27.2, 2026-11-19): the first pick after a full-speed swipe tapped the cell about 2 s
    /// after the swipe, while the grid was still decelerating. A touch on a moving scroll view only stops it: nothing
    /// was picked, no Open button came, the picker stayed up (screenshots), and the test read "No photo"/"No video"
    /// (MED-001-T23, MED-001-T24 HEIC, MED-002 H.264, MED-014 panorama); later picks in the same test, with no swipe,
    /// worked. After any scroll the item's frame must now hold still before it counts as found (`settle`).
    func findFile(_ name: String, initialWait: Double, swipes: Int) -> Bool {
        if wait(initialWait, { self.isFullyShown(self.fileItem(name)) }) { return true }
        let grid = app.collectionViews["File View"].firstMatch
        guard grid.exists else { return fileItem(name).exists }
        for _ in 0..<swipes {
            let item = fileItem(name)
            if isFullyShown(item) { return settle(item) }
            moveTowards(item, in: grid)
            pause(0.6)
        }
        let item = fileItem(name)
        if item.exists && !isFullyShown(item) { moveTowards(item, in: grid); pause(0.6) }
        return fileItem(name).exists && settle(fileItem(name))
    }

    /// Waits (at most `timeout` s) until `item`'s frame is the same in two reads 0.4 s apart: the scroll view under it
    /// has stopped, so a tap is a tap and not a scroll stop. True when it settled, or when it kept moving but is still
    /// on screen (the tap is tried anyway; `tapFile` checks that the picker took it).
    @discardableResult
    func settle(_ item: XCUIElement, timeout: Double = 4) -> Bool {
        var last = item.exists ? item.frame : .null
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            pause(0.4)
            guard item.exists else { return false }
            let now = item.frame
            if now == last { return true }
            last = now
        }
        return item.exists
    }

    /// Whether `item` is hittable and wholly inside the window, at least 60 pt below its top (the picker's toolbar)
    /// and 40 pt above its bottom (the home indicator).
    func isFullyShown(_ item: XCUIElement) -> Bool {
        guard item.exists, item.isHittable else { return false }
        let window = app.windows.firstMatch.frame, frame = item.frame
        guard !window.isEmpty else { return true }
        return frame.minY >= window.minY + 60 && frame.maxY <= window.maxY - 40
    }

    /// Scrolls `grid` so `item` comes into view: a full swipe up while it is not built or wholly off screen, otherwise
    /// a slow drag of a third of the grid that moves it towards the middle.
    private func moveTowards(_ item: XCUIElement, in grid: XCUIElement) {
        let window = app.windows.firstMatch.frame
        guard item.exists, window.isEmpty || item.frame.intersects(window) else {
            if item.exists, item.frame.maxY < window.minY { grid.swipeDown() } else { grid.swipeUp() }
            return
        }
        let up = item.frame.midY > grid.frame.midY   // below the middle: drag the content up
        let start = grid.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.7 : 0.35))
        let end = grid.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.35 : 0.7))
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
    }

    /// Taps the file's item, then Open when the picker selects several (the audio importer) or asks to confirm. When
    /// Open is shown but stays disabled, the tap selected nothing (rerun 3, D3): the item is brought fully into view
    /// and tapped once more. Returns whether the picker took the file.
    ///
    /// QA-011 pass 4 (D2, iPadOS 27.2, 2026-11-19): in a single-selection picker (photos, videos, presets) the first tap
    /// after a grid swipe only stopped the scroll's momentum: no Open button came, the picker stayed up over the app,
    /// and the test went on as if the file had been taken (FILE-009 stored no photo or video; PRE-012 and PRE-014 saw
    /// no Import Preset alert). The tap now waits for the item to stop moving, and a single-selection pick counts only
    /// once the item is gone (the picker closed); otherwise it taps again.
    ///
    /// QA-011 full run 12 (D2, iPadOS 27.2, 2026-11-20): PRE-014 tapped preset-512k.milk's cell three times and the
    /// picker never took it. XCUITest taps an element at its accessibility activation point. For every other grid cell
    /// in that run and in full run 8 that point was the thumbnail's centre (59, 46 pt into a 117.5 × 190 icon cell),
    /// but this cell reported (11.8, 19): its top-left margin, outside the thumbnail and the name, so each tap selected
    /// nothing (session log: "Computed hit point {503.3, 985.0}" for a cell at {491.5, 966}). The tap no longer trusts
    /// the activation point: it aims at where a person taps (`tapItem`), the thumbnail first, then the name, then the
    /// cell's middle on later attempts.
    @discardableResult
    func tapFile(_ name: String) -> Bool {
        let open = app.buttons["Open"].firstMatch
        for attempt in 0..<3 {
            settle(fileItem(name))
            tapItem(fileItem(name), name: name, attempt: attempt)
            if open.waitForExistence(timeout: 2) {
                if wait(2, { open.isEnabled }) {
                    open.tap()
                    return true
                }
                print("DEVICE-ACCEPT-NOTE \(name): the tap selected nothing (Open disabled); tapping again")
                _ = findFile(name, initialWait: 0, swipes: 3)
                continue
            }
            if wait(3, { !self.pickerShows(name) }) { return true }   // a single-selection picker took the file
            print("DEVICE-ACCEPT-NOTE \(name): the picker is still up after tap \(attempt + 1); tapping again")
            _ = findFile(name, initialWait: 0, swipes: 2)
        }
        return !pickerShows(name)
    }

    /// Taps the picker item for `name` where a person would, not at its accessibility activation point (full run 12,
    /// `tapFile`). In the icon grid (a cell taller than wide) attempt 0 aims at the thumbnail's centre (half the width,
    /// 24% down: the usual activation point, 46 of 190 pt), attempt 1 at the file's name below it, attempt 2 at the
    /// cell's middle. A list row or any other element gets its own tap first, then its name, then its middle.
    func tapItem(_ item: XCUIElement, name: String, attempt: Int) {
        guard item.exists else { item.tap(); return }   // fails with XCUITest's own message
        let frame = item.frame
        let iconCell = item.elementType == .cell && frame.height > frame.width
        let stem = (name as NSString).deletingPathExtension
        let title = item.staticTexts.matching(NSPredicate(format: "label == %@ OR label BEGINSWITH %@", name, stem))
            .firstMatch
        if attempt > 0 {
            let image = item.images.firstMatch
            print("DEVICE-ACCEPT-NOTE \(name): tap \(attempt + 1) of the cell \(frame); its image "
                  + "\(image.exists ? "\(image.frame)" : "missing"), its name \(title.exists ? "\(title.frame)" : "missing")")
        }
        switch attempt {
        case 0 where iconCell:
            item.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.24)).tap()
        case 0:
            item.tap()
        case 1 where title.exists && !title.frame.isEmpty && frame.contains(CGPoint(x: title.frame.midX, y: title.frame.midY)):
            title.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        default:
            item.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
    }

    /// Whether the Files picker is still up: its grid, or a cell for `name` (only cells: after a pick the app itself may
    /// show the file's name in a label).
    func pickerShows(_ name: String) -> Bool {
        app.collectionViews["File View"].exists || app.cells.matching(Self.fileItemPredicate(name)).firstMatch.exists
    }

    /// Cancels a Files picker that is still up (after a failed pick or save), so the app is in front again.
    func cancelFilesPicker() {
        for label in ["Cancel", "Close"] {
            let button = app.buttons[label].firstMatch
            if button.exists && button.isHittable {
                button.tap()
                pause(1)
                return
            }
        }
    }

    /// In the app's document picker for export: the location (On My iPhone/iPad › projectM by default), then Save
    /// (or Move/Done, by release). `inCurrentLocation: true` taps Save where the picker opened, before any browsing
    /// (an exporter opened in the app's Documents with a DEBUG default-directory hook).
    @discardableResult
    func filesSave(path: [String] = [], inCurrentLocation: Bool = false) -> Bool {
        if inCurrentLocation {
            for name in ["Save", "Move", "Done"] where app.buttons[name].firstMatch.waitForExistence(timeout: 3) {
                app.buttons[name].firstMatch.tap()
                return true
            }
        }
        let browse = app.buttons["Browse"].firstMatch   // iPadOS 26 nests a second Browse button (REC-003, D3)
        if wait(5, { browse.exists }) { browse.tap(); pause(0.5) }
        let places = path.isEmpty ? [UIDevice.current.userInterfaceIdiom == .pad ? "On My iPad" : "On My iPhone",
                                     Self.appDisplayName] : path
        // QA-011 pass 9 (D2, iPadOS 27.2, 2026-11-19), a test bug: the mover opened in projectM, the test chose On My
        // iPad (the root), and the tap on the first element labelled exactly "projectM" did not open the folder, so
        // Save wrote the recording to the root of On My iPad (the Files app showed it there, beside earlier runs'
        // recordings) and "Files lists the recording" failed in projectM. A folder below the location is now its
        // cell in the grid ("projectM, 44 items"), tapped at its centre, and the step waits until the cell is gone
        // (the folder is open); the exact-label element stays the fallback (sidebar locations, other releases).
        for (index, place) in places.enumerated() {
            let folder = app.cells.matching(NSPredicate(format: "label BEGINSWITH %@", place + ",")).firstMatch
            let item = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", place)).firstMatch
            if index > 0, wait(5, { folder.exists }) {
                if folder.isHittable { folder.tap() } else { folder.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).tap() }
                if !wait(4, { !folder.exists }) {
                    print("DEVICE-ACCEPT-NOTE Files: the \(place) folder is still listed after the tap; tapping again")
                    if folder.exists { folder.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).tap() }
                    _ = wait(4) { !folder.exists }
                }
                pause(0.8)
            } else if wait(5, { item.exists }) {
                item.tap()
                pause(0.8)
            }
        }
        for name in ["Save", "Move", "Done", "Open"] {
            let button = app.buttons[name].firstMatch
            if button.exists && button.isEnabled {
                button.tap()
                return true
            }
        }
        XCTFail("Files: no Save button")
        cancelFilesPicker()
        return false
    }

    /// In the app's Photos picker (PHPicker): taps the newest `count` items, then Add (or Done) when the picker allows
    /// several.
    ///
    /// The grid's items are images with identifier "PXGGridLayout-Info" and labels such as "Photo, November 18,
    /// 6:51 PM" (iPadOS 26.5, 2026-11-19). The picker's other images (the "Private Access to Photos" header's icon, a
    /// dimming overlay off screen) come first in the tree, so the old "first image in a scroll view" tapped the header
    /// icon, picked nothing, and every Photos step after it failed (MED-001-T22, MED-002, MED-006, MED-008, MED-014).
    /// Newest is by the label's date when every item's label has one (the grid's order differs by release), else the
    /// grid's order.
    ///
    /// QA-011 rerun 4 and pass 4 (2026-11-19):
    /// * D3 (iPadOS 26.5): the grid's items existed (the log checked about 25 "PXGGridLayout-Info" images) and the
    ///   screenshot shows the seeded fixtures in the picker, but XCUITest called none of them hittable (the grid is
    ///   another process's view), so the filter left nothing: "the Photos picker shows no items". An item now counts
    ///   when its frame lies inside the window (hittable ones first), and it is tapped at its centre by coordinate.
    /// * D2 (iPadOS 27.2): a one-item picker closes on the tap, and the "Done" then found was the app's own Settings
    ///   Done, which closed the panel: the next summary read "" (MED-014-T23). Add/Done is tapped only for several
    ///   items, never the Settings navigation bar's Done.
    @discardableResult
    func photosPick(count: Int = 1) -> Bool {
        let grid = app.images.matching(identifier: "PXGGridLayout-Info")
        let skipped: Set<String> = ["PickerOnboardingHeaderViewIcon", "AdditionalDimmingOverlay"]
        let window = app.windows.firstMatch.frame
        func onScreen(_ e: XCUIElement) -> Bool {
            guard e.exists else { return false }
            let f = e.frame
            return !f.isEmpty && (window.isEmpty || window.contains(f))
        }
        func candidates(_ all: [XCUIElement]) -> [XCUIElement] {
            let shown = all.filter(onScreen)
            let hittable = shown.filter { $0.isHittable }
            return hittable.isEmpty ? shown : hittable
        }
        var items: [XCUIElement] = []
        _ = wait(10) {
            items = candidates(Array(grid.allElementsBoundByIndex.prefix(40)))
            if items.isEmpty {   // another release's grid: plain thumbnails inside the picker's scroll view
                items = candidates(Array(self.app.scrollViews.images.allElementsBoundByIndex.prefix(40)).filter {
                    !skipped.contains($0.identifier) && $0.frame.width > 40 && $0.frame.width < 300
                })
            }
            return !items.isEmpty
        }
        guard !items.isEmpty else {
            let seen = grid.allElementsBoundByIndex.prefix(4).map { "\($0.frame) hittable=\($0.isHittable)" }
            XCTFail("the Photos picker shows no items (grid items seen: \(grid.count); first frames \(seen); window \(window))")
            return false
        }
        let picks = Array(Self.newestFirst(items).prefix(count))
        print("DEVICE-ACCEPT-NOTE Photos picker: picking \(picks.map(\.label)) of \(items.count) shown")
        for item in picks {
            item.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            pause(0.4)
        }
        if count > 1 {
            let settingsDone = app.navigationBars["Settings"].buttons["Done"].firstMatch
            let appDone = settingsDone.exists ? settingsDone.frame : .null
            for name in ["Add", "Done"] {
                let button = app.buttons.matching(identifier: name).allElementsBoundByIndex.first {
                    $0.exists && $0.isEnabled && $0.frame != appDone
                }
                if let button {
                    button.tap()
                    break
                }
            }
        }
        let closed = wait(10) { !grid.firstMatch.exists }
        if !closed { XCTFail("the Photos picker is still up after picking \(count)") }
        return closed
    }

    /// `items` newest first by the date in their labels ("Photo, November 18, 6:51 PM", "Video, Today, 9:05 AM"),
    /// or in their own order when a label has no date this can read. Labels carry minutes only, so items added in
    /// the same minute tie (the library seed adds several at once): ties follow the grid's own direction, read from
    /// the labels that differ (newest-first grids keep their order, oldest-first grids are reversed).
    static func newestFirst(_ items: [XCUIElement]) -> [XCUIElement] {
        newestFirstOrder(items.map { photoDate($0.label) }).map { items[$0] }
    }

    /// The indices of `dates` newest first (see `newestFirst`); the given order when any date is nil.
    static func newestFirstOrder(_ dates: [Date?]) -> [Int] {
        guard !dates.contains(where: { $0 == nil }) else { return Array(dates.indices) }
        let d = dates.map { $0! }
        var rising = 0, falling = 0
        for i in d.indices.dropFirst() where d[i] != d[i - 1] {
            if d[i] > d[i - 1] { rising += 1 } else { falling += 1 }
        }
        let oldestFirstGrid = rising > falling
        return d.indices.sorted { a, b in d[a] != d[b] ? d[a] > d[b] : (oldestFirstGrid ? a > b : a < b) }
    }

    /// The date in a Photos picker label: "<kind>, <Month day>[, <year>], <time>" or "<kind>, Today|Yesterday, <time>".
    static func photoDate(_ label: String, now: Date = Date()) -> Date? {
        let parts = label.components(separatedBy: ", ")
        guard parts.count >= 3 else { return nil }
        let time = parts[parts.count - 1], day = parts[1...(parts.count - 2)].joined(separator: ", ")
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.defaultDate = now   // a label without a year is this year
        if day == "Today" || day == "Yesterday" {
            formatter.dateFormat = "h:mm a"
            guard let clock = formatter.date(from: time) else { return nil }
            let calendar = Calendar.current
            let c = calendar.dateComponents([.hour, .minute], from: clock)
            let base = calendar.startOfDay(for: now).addingTimeInterval(day == "Today" ? 0 : -86_400)
            return calendar.date(byAdding: DateComponents(hour: c.hour, minute: c.minute), to: base)
        }
        for format in ["MMMM d, yyyy h:mm a", "MMMM d h:mm a"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: day + " " + time) { return date }
        }
        return nil
    }

    /// In the share sheet the app presents: taps the activity labelled `activity` ("Save to Files", "Copy" …).
    @discardableResult
    func shareSheet(_ activity: String) -> Bool {
        let target = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", activity)).firstMatch
        if !wait(5, { target.exists }) {
            // The second row scrolls sideways; More lists every action.
            let more = app.buttons["More"].firstMatch
            if more.exists { more.tap() }
        }
        guard wait(5, { target.exists }) else {
            XCTFail("share sheet: no \(activity)")
            return false
        }
        target.tap()
        return true
    }

    // MARK: Camera app (real HEIC photos and HEVC clips into Photos)

    /// Takes one photo with the Camera app (back camera, Photo mode) and returns to the app.
    func cameraApp(photo: Bool = true) {
        let camera = Self.camera
        camera.launch()
        XCTAssertTrue(camera.wait(for: .runningForeground, timeout: 10), "Camera is in front")
        selectCameraMode(["PHOTO", "Photo"])
        let shutter = camera.buttons["PhotoCapture"]
        XCTAssertTrue(wait(5) { shutter.exists }, "the Camera shutter")
        shutter.tap()
        pause(2)
        app.activate()
    }

    /// Records a clip of `seconds` with the Camera app (Video mode) and returns to the app.
    func cameraApp(record seconds: Double) {
        let camera = Self.camera
        camera.launch()
        XCTAssertTrue(camera.wait(for: .runningForeground, timeout: 10), "Camera is in front")
        selectCameraMode(["VIDEO", "Video"])
        let shutter = camera.buttons["VideoCapture"].exists ? camera.buttons["VideoCapture"] : camera.buttons["PhotoCapture"]
        XCTAssertTrue(wait(5) { shutter.exists }, "the Camera record button")
        shutter.tap()
        pause(seconds)
        shutter.tap()
        pause(2)
        app.activate()
    }

    private func selectCameraMode(_ labels: [String]) {
        let camera = Self.camera
        for label in labels {
            let mode = camera.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
            if mode.exists { mode.tap(); pause(1); return }
        }
    }
}

// MARK: The Mac beside the device

/// Requests to scripts/mac_device_driver.py, which follows the xcodebuild log. Each request is one line,
/// `MAC-DO {"id": "<n>", "action": "<module.verb>", ...}`; the driver logs `MAC-DONE <id>` in its own log. The test
/// never waits for the Mac's answer itself (the log reaches the Mac seconds late): it waits on an app probe.
@MainActor
enum MacDriver {
    private static var counter = 0

    /// TEST_RUNNER_MAC_DRIVER=1: the run was started with the driver following the log.
    static var isFollowing: Bool { ProcessInfo.processInfo.environment["MAC_DRIVER"] == "1" }

    @discardableResult
    static func request(_ action: String, _ arguments: [String: Any] = [:]) -> String {
        counter += 1
        let id = "\(counter)"
        var body = arguments
        body["id"] = id
        body["action"] = action
        let data = (try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])) ?? Data()
        print("MAC-DO \(String(decoding: data, as: UTF8.self))")
        return id
    }
}

// MARK: Accessibility audits

/// The app's DEBUG test probes: near-transparent texts (opacity 0.01, `-uitestDiagnostics`, `-uitestVisualProbes` and
/// the other UI-test hooks) that carry state for the tests and are not in a shipping build. An audit flags them
/// (contrast, element description); on an iPad Settings is a side panel, so the visualizer's probes stay on screen
/// beside it and every audit there listed them (ACC-003-T17, SHD-003-T20 on D2 and D3, 2026-11-18).
enum DebugProbes {
    static let identifiers: Set<String> = [
        "cameraDeviceState", "cameraFramesShown", "cameraOrientationGrid", "cameraRecovery", "diskBallast",
        "externalCalibration", "externalCornerPin", "externalDiagnostics", "externalGridWarp", "externalOutputMode",
        "externalPlacement", "externalResolution", "externalResources", "gestureShortcutLast", "gestureShortcutPreset",
        "oneHandedZone", "outputBlackout", "performanceSafeArea", "photoFramesShown", "photoLibrarySeed",
        "photoStoredMetadata", "recordingFacts", "renderHealth", "renderPlaceholderShown", "sceneAutosave",
        "sessionRecovery", "showAppliedScene", "sourceStarts", "splitOutputFrame", "textRendering", "videoFrameRate",
        "visualRunning",
    ]

    /// True for a probe's identifier: the list above, or any `…Probe` / `uitest…` identifier.
    static func contains(_ identifier: String) -> Bool {
        identifiers.contains(identifier) || identifier.hasSuffix("Probe") || identifier.hasPrefix("uitest")
            || identifier.contains(".uitest")
    }
}

extension XCTestCase {
    /// Runs an accessibility audit of what `app` shows; returns one line per issue (and attaches the screen when
    /// there are issues). The caller asserts, so a test can report issues per screen. Issues on the DEBUG probes
    /// (`DebugProbes`) are left out unless `includeProbes`.
    @MainActor
    func auditIssues(_ app: XCUIApplication, _ screen: String,
                     types: XCUIAccessibilityAuditType = .all, includeProbes: Bool = false) -> [String] {
        var issues: [String] = []
        do {
            try app.performAccessibilityAudit(for: types) { (issue: XCUIAccessibilityAuditIssue) -> Bool in
                let snapshot: XCUIElementSnapshot? = try? issue.element?.snapshot()
                if !includeProbes, DebugProbes.contains(snapshot?.identifier ?? "") { return true }
                issues.append("[\(screen)] type=\(issue.auditType.rawValue) id=\"\(snapshot?.identifier ?? "")\" "
                              + "label=\"\(snapshot?.label ?? "")\": \(issue.compactDescription)")
                return true
            }
        } catch {
            issues.append("[\(screen)] audit failed: \(error)")
        }
        if !issues.isEmpty {
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot.name = "audit-\(screen)"
            shot.lifetime = .keepAlways
            add(shot)
        }
        return issues
    }
}
