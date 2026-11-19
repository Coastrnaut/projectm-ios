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
        ([alert.label] + alert.staticTexts.allElementsBoundByIndex.map(\.label)
            + alert.buttons.allElementsBoundByIndex.map(\.label)).joined(separator: " | ")
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
        if preferences.state == .runningForeground, preferences.navigationBars[Self.appDisplayName].exists { return }
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
                // Skip the search field itself, whose text is `text`.
                let match = query.matching(predicate).allElementsBoundByIndex
                    .first { $0.elementType != .searchField && $0.isHittable && $0.frame.minY > search.frame.maxY }
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

    var controlCenterIsOpen: Bool { controlCenterMarker.exists }

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
    @discardableResult
    func filesPick(path: [String] = [], name: String) -> Bool {
        if path.isEmpty, findFile(name, initialWait: 3, swipes: 6) {   // the picker opened where the file is
            tapFile(name)
            return true
        }
        let browse = app.buttons["Browse"].firstMatch   // the iPhone tab bar; iPadOS 26 nests a second Browse button
        if wait(3, { browse.exists }) { browse.tap(); pause(0.5) }
        let places = path.isEmpty ? [UIDevice.current.userInterfaceIdiom == .pad ? "On My iPad" : "On My iPhone",
                                     Self.appDisplayName] : path
        for place in places {
            let item = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", place)).firstMatch
            guard wait(5, { item.exists }) else {
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
        tapFile(name)
        return true
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
    func findFile(_ name: String, initialWait: Double, swipes: Int) -> Bool {
        if wait(initialWait, { self.isFullyShown(self.fileItem(name)) }) { return true }
        let grid = app.collectionViews["File View"].firstMatch
        guard grid.exists else { return fileItem(name).exists }
        for _ in 0..<swipes {
            let item = fileItem(name)
            if isFullyShown(item) { return true }
            moveTowards(item, in: grid)
            pause(0.6)
        }
        let item = fileItem(name)
        if item.exists && !isFullyShown(item) { moveTowards(item, in: grid); pause(0.6) }
        return fileItem(name).exists
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
    /// and tapped once more.
    func tapFile(_ name: String) {
        let open = app.buttons["Open"].firstMatch
        for attempt in 0..<2 {
            fileItem(name).tap()
            guard open.waitForExistence(timeout: 2) else { return }   // a single-selection picker took the file
            if wait(2, { open.isEnabled }) {
                open.tap()
                return
            }
            if attempt == 0 {
                print("DEVICE-ACCEPT-NOTE \(name): the tap selected nothing (Open disabled); tapping again")
                _ = findFile(name, initialWait: 0, swipes: 3)
            }
        }
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
        for place in places {
            let item = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", place)).firstMatch
            if wait(5, { item.exists }) { item.tap(); pause(0.8) }
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
    @discardableResult
    func photosPick(count: Int = 1) -> Bool {
        let grid = app.images.matching(identifier: "PXGGridLayout-Info")
        let skipped: Set<String> = ["PickerOnboardingHeaderViewIcon", "AdditionalDimmingOverlay"]
        var items: [XCUIElement] = []
        _ = wait(10) {
            items = Array(grid.allElementsBoundByIndex.prefix(40)).filter { $0.exists && $0.isHittable }
            if items.isEmpty {   // another release's grid: plain thumbnails inside the picker's scroll view
                items = Array(self.app.scrollViews.images.allElementsBoundByIndex.prefix(40)).filter {
                    $0.exists && $0.isHittable && !skipped.contains($0.identifier) && $0.frame.width > 40 && $0.frame.width < 300
                }
            }
            return !items.isEmpty
        }
        guard !items.isEmpty else {
            XCTFail("the Photos picker shows no items")
            return false
        }
        for item in Self.newestFirst(items).prefix(count) { item.tap() }
        for name in ["Add", "Done"] {
            let button = app.buttons[name].firstMatch
            if button.exists && button.isEnabled {
                button.tap()
                break
            }
        }
        return true
    }

    /// `items` newest first by the date in their labels ("Photo, November 18, 6:51 PM", "Video, Today, 9:05 AM"),
    /// or in their own order when a label has no date this can read.
    static func newestFirst(_ items: [XCUIElement]) -> [XCUIElement] {
        let dates = items.map { photoDate($0.label) }
        guard !dates.contains(where: { $0 == nil }) else { return items }
        let order = items.indices.sorted { a, b in dates[a]! != dates[b]! ? dates[a]! > dates[b]! : a < b }
        return order.map { items[$0] }
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
