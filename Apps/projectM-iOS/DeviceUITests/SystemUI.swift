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
        for name in Self.synonyms(button) where alert.buttons[name].exists {
            alert.buttons[name].tap()
            _ = wait(5) { !alert.exists }
            return text
        }
        XCTFail("the alert has no \(button) button: \(text)")
        return text
    }

    // MARK: Settings app

    /// Settings, freshly launched at its root list.
    func openSettingsRoot() {
        preferences.terminate()
        preferences.launch()
        XCTAssertTrue(preferences.wait(for: .runningForeground, timeout: 10), "Settings is in front")
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

    /// Scrolls the frontmost Settings list until `element` is hittable (at most `swipes` slow swipes each way).
    @discardableResult
    func scrollTo(_ element: XCUIElement, in application: XCUIApplication, swipes: Int = 8) -> Bool {
        if element.exists && element.isHittable { return true }
        let list = application.collectionViews.firstMatch.exists ? application.collectionViews.firstMatch
            : application.tables.firstMatch.exists ? application.tables.firstMatch : application.windows.firstMatch
        for _ in 0..<swipes where !(element.exists && element.isHittable) { list.swipeUp(velocity: .slow) }
        for _ in 0..<swipes where !(element.exists && element.isHittable) { list.swipeDown(velocity: .slow) }
        return element.exists && element.isHittable
    }

    /// Taps the Settings row `label`, scrolling to it first; false when it cannot be found.
    @discardableResult
    func tapSettingsRow(_ label: String) -> Bool {
        _ = wait(3) { self.settingsRow(label).exists }
        var row = settingsRow(label)
        if !scrollTo(row, in: preferences) {
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
        for row in rows {
            XCTAssertTrue(tapSettingsRow(row), "Settings row \(row)")
        }
    }

    /// The app's own page: Settings › Apps › projectM (iOS 18 and later), found by scrolling or the Apps search field.
    /// If Settings is already in front on that page (after the app's "Open Settings" button), it is used as is.
    func openAppSettingsPage() {
        if preferences.state == .runningForeground, preferences.navigationBars[Self.appDisplayName].exists { return }
        openSettingsRoot()
        if tapSettingsRow("Apps") {
            let search = preferences.searchFields.firstMatch
            if search.waitForExistence(timeout: 2) {
                search.tap()
                search.typeText(Self.appDisplayName)
                pause(1)
            }
            XCTAssertTrue(tapSettingsRow(Self.appDisplayName), "the app in Settings › Apps")
        } else {
            XCTAssertTrue(tapSettingsRow(Self.appDisplayName), "the app in Settings (pre-iOS 18 layout)")
        }
        XCTAssertTrue(wait(5) { self.preferences.navigationBars[Self.appDisplayName].exists },
                      "the app's Settings page is shown")
    }

    /// A Settings switch's state: "1"/"0" (or "On"/"Off" on some releases).
    func isOn(_ element: XCUIElement) -> Bool {
        let value = (element.value as? String)?.lowercased() ?? ""
        return value == "1" || value == "on"
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
        let before = isOn(toggle)
        if before != on {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
            if !wait(3, { self.isOn(toggle) == on }) { toggle.tap() }
            XCTAssertTrue(wait(5) { self.isOn(toggle) == on }, "\(label) is \(on ? "on" : "off")")
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

    /// The app's card in the switcher, if springboard lists it by the app's name.
    var appSwitcherCard: XCUIElement {
        springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@ OR identifier == %@", Self.appDisplayName, Self.appDisplayName))
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
    @discardableResult
    func forceQuitFromSwitcher() -> Bool {
        let card = appSwitcherCard
        let from = card.exists && card.frame.height > 0 ? card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            : springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let to = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02))
        from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .fast, thenHoldForDuration: 0)
        let ended = wait(8) { self.app.state == .notRunning }
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
        for name in ["Timers", "Timer"] where clock.tabBars.buttons[name].exists {
            clock.tabBars.buttons[name].tap()
            break
        }
        let wheels = clock.pickerWheels
        if wait(3, { wheels.count >= 3 }) {
            // hours, minutes, seconds
            wheels.element(boundBy: 0).adjust(toPickerWheelValue: "0")
            wheels.element(boundBy: 1).adjust(toPickerWheelValue: "0")
            wheels.element(boundBy: 2).adjust(toPickerWheelValue: "\(max(1, seconds))")
        } else {
            XCTFail("the Clock timer's wheels were not found")
        }
        let start = clock.buttons["Start"]
        XCTAssertTrue(wait(3) { start.exists }, "the timer's Start button")
        start.tap()
        remember("Clock timer", keep: false) { [weak self] in self?.stopClockTimer() }
        app.activate()
        _ = app.wait(for: .runningForeground, timeout: 10)
    }

    /// Stops a ringing timer from its alert or banner, or cancels a running one in Clock.
    func stopClockTimer() {
        let stop = springboard.buttons["Stop"]
        if wait(2, { stop.exists }) { stop.tap(); return }
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
    func siriInterruption(_ text: String = "What time is it", seconds: Double = 4) {
        XCUIDevice.shared.siriService.activate(voiceRecognitionText: text)
        pause(seconds)
        app.activate()
        _ = app.wait(for: .runningForeground, timeout: 10)
    }

    // MARK: Pickers and sheets the app presents (out of process, listed in the app's tree)

    /// In the app's document picker (Files): Browse, a location ("On My iPhone"/"On My iPad" when `path` is empty,
    /// then `projectM`), the folders in `path`, then the file `name`; taps Open when the picker asks.
    @discardableResult
    func filesPick(path: [String] = [], name: String) -> Bool {
        let browse = app.buttons["Browse"]
        if wait(5, { browse.exists }) { browse.tap(); pause(0.5) }
        let places = path.isEmpty ? [UIDevice.current.userInterfaceIdiom == .pad ? "On My iPad" : "On My iPhone",
                                     Self.appDisplayName] : path
        for place in places {
            let item = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", place)).firstMatch
            guard wait(5, { item.exists }) else {
                XCTFail("Files: no \(place)")
                return false
            }
            item.tap()
            pause(0.6)
        }
        let file = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
        guard wait(5, { file.exists }) else {
            XCTFail("Files: no \(name) in \(places.joined(separator: " › "))")
            return false
        }
        file.tap()
        if app.buttons["Open"].waitForExistence(timeout: 2) { app.buttons["Open"].tap() }
        return true
    }

    /// In the app's document picker for export: the location (On My iPhone/iPad › projectM by default), then Save
    /// (or Move/Done, by release).
    @discardableResult
    func filesSave(path: [String] = []) -> Bool {
        let browse = app.buttons["Browse"]
        if wait(5, { browse.exists }) { browse.tap(); pause(0.5) }
        let places = path.isEmpty ? [UIDevice.current.userInterfaceIdiom == .pad ? "On My iPad" : "On My iPhone",
                                     Self.appDisplayName] : path
        for place in places {
            let item = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", place)).firstMatch
            if wait(5, { item.exists }) { item.tap(); pause(0.6) }
        }
        for name in ["Save", "Move", "Done", "Open"] where app.buttons[name].exists {
            app.buttons[name].tap()
            return true
        }
        XCTFail("Files: no Save button")
        return false
    }

    /// In the app's Photos picker (PHPicker): taps the newest `count` items, then Add when the picker allows several.
    @discardableResult
    func photosPick(count: Int = 1) -> Bool {
        let items = app.scrollViews.images
        guard wait(8, { items.count > 0 }) else {
            XCTFail("the Photos picker shows no items")
            return false
        }
        for i in 0..<min(count, items.count) { items.element(boundBy: i).tap() }
        for name in ["Add", "Done"] where app.buttons[name].exists {
            app.buttons[name].tap()
            break
        }
        return true
    }

    /// In the share sheet the app presents: taps the activity labelled `activity` ("Save to Files", "Copy" …).
    @discardableResult
    func shareSheet(_ activity: String) -> Bool {
        let target = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", activity)).firstMatch
        if !wait(5, { target.exists }) {
            // The second row scrolls sideways; More lists every action.
            let more = app.buttons["More"]
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

extension XCTestCase {
    /// Runs an accessibility audit of what `app` shows; returns one line per issue (and attaches the screen when
    /// there are issues). The caller asserts, so a test can report issues per screen.
    @MainActor
    func auditIssues(_ app: XCUIApplication, _ screen: String,
                     types: XCUIAccessibilityAuditType = .all) -> [String] {
        var issues: [String] = []
        do {
            try app.performAccessibilityAudit(for: types) { (issue: XCUIAccessibilityAuditIssue) -> Bool in
                let snapshot: XCUIElementSnapshot? = try? issue.element?.snapshot()
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
