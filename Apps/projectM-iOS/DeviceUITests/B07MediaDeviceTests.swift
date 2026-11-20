// B07MediaDeviceTests.swift — QA-011 Batch 5 (media layers): the MED-001/002/003/004/006/007/008/009/010/014 device
// tasks, with the real Photos and Files pickers driven through Batch 1's SystemUI.swift on D1 (and D3 where listed).
//
// Fixtures: `python3 scripts/install_test_fixtures.py --device <D> --media` copies Build/fixtures/media
// (scripts/make_media_fixtures.py) into the app's Documents, which the Debug device-test host shows in Files as
// On My iPhone/iPad › projectM. Photos picks need pictures in the library: `-uitestSeedPhotoLibrary <names>` adds those
// Documents files with add-only access, answered once per device in PromptFlowDeviceTests (testZ grants it); a seed
// that would prompt fails the test instead of waiting. The Camera app's own clips and photos (`SystemUI.cameraApp`)
// need no prompt of this app.
//
// Measurements are probes, not looks: `photoVisual`/`videoVisual` VoiceOver values ("Photo W × H", "Video W × H",
// "Animated photo W × H, N frames"), `photoStoredMetadata` and `videoFrameRate` (Debug/UITestMediaDeviceProbes.swift),
// `videoLoopRegion`, `videoLoopStats`, `videoSpeed`, `slideshowProbe`, `logoProbe`, `textRendering`, `memoryProbe`, and
// screenshot statistics away from the centred spectrum (DeviceAcceptanceCase.stillRegion). Every value is printed as a
// `DEVICE-ACCEPT {json}` line. No test waits for a person; tests that need one part a person does say so in their
// comment (iCloud Drive eviction, real keyboards, VoiceOver speech, ProRAW).
import UIKit
import XCTest

/// Shared steps of the Batch 5 tests (media here, files and presets in B07FilesDeviceTests.swift).
@MainActor
class B07Case: ControlSurfaceCase {
    /// One SystemUI per test, so `restore()` undoes what this test changed.
    lazy var ui = SystemUI(app: app)

    override func tearDown() async throws {
        ui.restore()
        try await super.tearDown()
    }

    /// A launch that keeps what the app stored (no reset, no seeds), as after a real relaunch. With no
    /// `-uitestDefaults` and no `-uitestResetNotice` the app keeps the typed settings of `launch` too (the visual among
    /// them; AppCoordinator.applyUITestDefaults, 2026-11-19).
    static let plainArguments = ["-uitestDiagnostics", "-autostart", "inAppPlayback", "-uitestUnlocked", "NO"]

    func relaunch(_ extra: [String] = [], replacing: [String]? = nil) {
        app.terminate()
        app.launchArguments = (replacing ?? Self.plainArguments) + extra
        app.launch()
        XCTAssertTrue(wait(20) { self.app.staticTexts["sourceStarts"].exists }, "the app relaunched")
        pause(2)
    }

    // MARK: Values

    /// The visual's VoiceOver value, or "" while it is not on screen (reading `value` of a missing element records a
    /// failure at once instead of letting the caller's `wait` retry: MED-001, MED-008, MED-014 on D3, 2026-11-19).
    var photoValue: String { visualValue("photoVisual") }
    var videoValue: String { visualValue("videoVisual") }

    func visualValue(_ id: String) -> String {
        let visual = element(id)
        return visual.exists ? (visual.value as? String ?? "") : ""
    }

    /// Any element whose label contains `text`.
    func labelled(_ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// "a=1 b=x" → ["a": "1", "b": "x"].
    static func fields(_ text: String) -> [String: String] {
        var out: [String: String] = [:]
        for part in text.split(separator: " ") {
            let kv = part.split(separator: "=", maxSplits: 1)
            if kv.count == 2 { out[String(kv[0])] = String(kv[1]) }
        }
        return out
    }

    func footprintMB() -> Int? { Int(text("memoryProbe").replacingOccurrences(of: "footprintMB=", with: "")) }

    /// A frame counter probe as a number (-1 when missing). The digits only: SwiftUI shows "1,234" past 999.
    func probeCount(_ id: String) -> Int { Int(text(id).filter(\.isNumber)) ?? -1 }

    // MARK: Settings

    /// Taps a Settings control (a button, a PhotosPicker, a link) by identifier, scrolling to it: slow swipes first
    /// (precise near the top), then full-speed swipes for controls near the end of a long Settings list. On the iPad
    /// panel 12 slow swipes in each direction never reached Storage below the projectM visual's sections (PRE-001-T14,
    /// FILE-009-T12 on D3, 2026-11-19).
    @discardableResult
    func tapControl(_ id: String) -> Bool {
        let button = app.buttons[id].firstMatch
        let target = button.exists ? button : app.descendants(matching: .any)[id].firstMatch
        if !scrollTo(target, swipes: 12) && !fastScrollTo(target, up: false) && !fastScrollTo(target, up: true) {
            XCTFail("\(id) is reachable in Settings")
            return false
        }
        target.tap()
        return true
    }

    /// Full-speed swipes of the frontmost list until `element` is hittable (a slow swipe settles one found just off
    /// screen).
    private func fastScrollTo(_ element: XCUIElement, up: Bool, swipes: Int = 15) -> Bool {
        let list = app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch : app.tables.firstMatch
        for _ in 0..<swipes {
            if element.exists && element.isHittable { return true }
            if element.exists { return scrollTo(element, up: up, swipes: 3) }
            list.scrollStep(up: !up, velocity: .fast)
            pause(0.4)
        }
        return element.exists && element.isHittable
    }

    /// Chooses `option` in the menu picker `id` (menu items are buttons by their label).
    func chooseMenu(_ id: String, _ option: String) {
        guard tapControl(id) else { return }
        var item = app.buttons[option].firstMatch
        if !wait(3, { item.exists }) {
            item = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", option)).firstMatch
        }
        XCTAssertTrue(wait(3) { item.exists }, "\(id) offers \(option)")
        if item.exists { item.tap() }
        pause(0.6)
    }

    /// Settings › the visual row `raw` (VisualChoice raw value), then Done.
    func chooseVisual(_ raw: String) {
        openSettingsPanel()
        let row = app.buttons["visual.\(raw)"].firstMatch
        if !scrollTo(row, up: true, swipes: 12) { _ = scrollTo(row, swipes: 12) }
        XCTAssertTrue(row.exists, "the \(raw) row")
        if row.exists { row.tap() }
        closeSettingsPanel()
    }

    /// Settings › `button` (a "Choose from Files…") › the document picker › Documents/`name`.
    func pickFromFiles(_ button: String, _ name: String) {
        openSettingsPanel()
        guard tapControl(button) else { return }
        XCTAssertTrue(ui.filesPick(name: name), "Files: picked \(name)")
        pause(1)
    }

    /// Settings › `button` (a "Choose from Photos…") › the Photos picker › the newest `count` items.
    func pickFromPhotos(_ button: String, count: Int = 1) {
        openSettingsPanel()
        guard tapControl(button) else { return }
        XCTAssertTrue(ui.photosPick(count: count), "Photos: picked \(count)")
        pause(1)
    }

    /// A Settings summary row (`LabeledContent`): its value, or its label without the row title ("Photo, 320 × 240").
    func summary(_ id: String) -> String {
        var value = text(id)
        for title in ["Photo, ", "Video, ", "Logo, "] where value.hasPrefix(title) { value = String(value.dropFirst(title.count)) }
        return value
    }

    /// The summary row `id` once it no longer reads "Importing…" or "Loading…".
    @discardableResult
    func settledSummary(_ id: String, timeout: Double = 60) -> String {
        _ = wait(timeout) {
            let value = self.summary(id)
            return !value.isEmpty && !value.contains("Importing") && !value.contains("Loading")
        }
        return summary(id)
    }

    /// No springboard alert (a permission prompt) is on screen.
    func assertNoPrompt(_ task: String, _ step: String) {
        if let alert = ui.systemAlert(timeout: 1) {
            XCTFail("\(task) \(step): a system prompt appeared: \(ui.alertText(alert))")
        }
    }

    // MARK: Photo library seed (Batch 1)

    static func seedLibrary(_ names: [String]) -> [String] { ["-uitestSeedPhotoLibrary", names.joined(separator: ",")] }

    /// Waits for `-uitestSeedPhotoLibrary`; fails (never waits for a person) when add-only access was not granted.
    /// False when the seed did not add every fixture: the caller stops there, since its Photos steps would only pick
    /// whatever else the library holds (pass 4, D2: the prompt was up and every later step failed behind it).
    @discardableResult
    func waitLibrarySeed(_ task: String) -> Bool {
        let done = wait(90) { self.text("photoLibrarySeed").contains("done=1") || self.ui.systemAlert() != nil }
        let value = text("photoLibrarySeed")
        if ui.systemAlert() != nil {
            XCTFail("\(task): the Photos add-only prompt appeared; run the prompt-flow batch first "
                    + "(python3 scripts/mac_device_driver.py prompt-flow --device <D>); stopping here")
            return false
        }
        let seeded = done && value.contains("status=granted") && value.contains("missing=0") && value.contains("failed=0")
        XCTAssertTrue(seeded, "\(task): the library seed (\(value)); install the media fixtures (install_test_fixtures.py --media) and "
                      + "grant Photos add-only (prompt-flow batch)")
        return seeded
    }

    /// Waits up to `timeout` s for an element labelled with `text` (a notice). A notice row added below the Photo
    /// section's buttons lies under the fold of the Settings list, and the list builds no off-screen rows, so it is
    /// not in the tree until shown: MED-001-T24 on D3 (2026-11-19) never found "larger than 40 MB" although the app
    /// refused the file (the hierarchy ends at Choose from Files…). The list is dragged up a third at a time (slowly,
    /// at most three times) while the notice is missing; it clears itself after 6 s (PhotoCoordinator).
    func waitForNotice(_ text: String, timeout: Double = 20) -> Bool {
        let notice = labelled(text)
        var drags = 0
        return wait(timeout) {
            if notice.exists { return true }
            let list = self.app.collectionViews.firstMatch
            if drags < 3, self.app.navigationBars["Settings"].exists, list.exists {
                drags += 1
                let a = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
                let b = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.42))
                a.press(forDuration: 0.05, thenDragTo: b, withVelocity: .slow, thenHoldForDuration: 0.2)
            }
            return notice.exists
        }
    }

    /// Drags an ACC-005 slider row (an adjustable element, not an XCUIElement slider: `app.sliders[id]` never
    /// matches it) from `current` to `target` (0…1): the line runs 27 pt above the row's bottom, 34 pt in from each
    /// side (as UITestSliders' `dragSlider`).
    func dragRowSlider(_ e: XCUIElement, from current: CGFloat, to target: CGFloat) {
        let rect = e.frame
        let width = max(rect.width, 1)
        let y: CGFloat = rect.height > 50 ? rect.height - 27 : rect.height / 2
        let left: CGFloat = rect.height > 50 ? 34 : 14
        let track = max(width - 2 * left, 1)
        func x(_ p: CGFloat) -> CGFloat { left + min(max(p, 0), 1) * track }
        let origin = e.coordinate(withNormalizedOffset: .zero)
        let endX: CGFloat = target <= 0 ? -10 : (target >= 1 ? width + 10 : x(target))
        origin.withOffset(CGVector(dx: x(current), dy: y))
            .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: endX, dy: y)), withVelocity: .slow,
                   thenHoldForDuration: 0.1)
    }

    // MARK: Pixels

    /// Screenshot pixels at `step` (full width and height in samples).
    func pixels(_ task: String, _ label: String, step: Int) -> (pixels: [UInt8], width: Int, height: Int) {
        let saved = sampleStep
        sampleStep = step
        let p = screen(task, label).1
        let size = lastSize
        sampleStep = saved
        return (p, size.0, size.1)
    }

    static func luma(_ p: [UInt8], _ i: Int) -> Double {
        (0.2126 * Double(p[i]) + 0.7152 * Double(p[i + 1]) + 0.0722 * Double(p[i + 2])) / 255
    }

    /// "1:05" or "1:02:05" → seconds.
    static func clock(_ text: String) -> Double? {
        let parts = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "-", with: "").split(separator: ":")
            .compactMap { Double($0) }
        guard parts.count >= 2 else { return nil }
        return parts.reduce(0) { $0 * 60 + $1 }
    }

    /// The In-App Playback position from the transport (`transportElapsed`), with the controls shown.
    func musicPosition() -> Double? {
        showControlsBar()
        let elapsed = app.descendants(matching: .any)["transportElapsed"].firstMatch
        guard wait(3, { elapsed.exists }) else { return nil }
        return Self.clock(elapsed.label) ?? Self.clock(elapsed.value as? String ?? "")
    }

    // MARK: Screenshots without the controls

    /// Hides the controls before a screenshot statistic. Closing Settings leaves the controls up for 5 s, and on an
    /// iPad portrait screen they cover the lower half, `stillRegion` and both bottom corners (and show the status bar
    /// in the top corners): QA-011 pass 4 (D2, D3 2026-11-19) MED-007's first Ken Burns and Reduce Motion pictures and
    /// every MED-010 corner were taken with them up (nonBlack 0.81 against 0.997 without; the "dark fringe" was the
    /// controls' text on their black panel).
    func hideControlsForShot() {
        let controls = app.otherElements["controls"]
        let area = app.otherElements["visualizerTapArea"].firstMatch
        if controls.exists, area.exists { area.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap() }
        if !wait(2, { !controls.exists }) { _ = wait(7) { !controls.exists } }   // else their own 5 s timeout
        XCTAssertFalse(controls.exists, "the controls are hidden for the screenshot")
        pause(0.6)   // their fade-out
    }

    // MARK: ACC-005 slider rows

    /// An ACC-005 slider row by identifier, any element type (its frame is the whole row).
    func sliderRow(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    /// Scrolls until the row lies on screen below the navigation bar: frames only, since an ACC-005 row reports
    /// `isHittable` false even when it is fully on screen (B07DeviceCase.reveal, 2026-11-18).
    @discardableResult
    func revealRow(_ e: XCUIElement, swipes: Int = 12) -> Bool {
        let window = app.windows.firstMatch
        func visible() -> Bool {
            guard e.exists else { return false }
            let f = e.frame, bar = app.navigationBars.firstMatch
            let top: CGFloat = bar.exists ? bar.frame.maxY : window.frame.minY
            return f.height > 0 && f.minY >= top && f.maxY <= window.frame.maxY
        }
        let list = app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch : app.tables.firstMatch
        var up = false
        for i in 0..<swipes {
            if visible() { return true }
            if e.exists { up = e.frame.minY < window.frame.midY } else if i == swipes / 2 { up = true }
            list.scrollStep(up: !up)
        }
        return visible()
    }

    /// Drags an ACC-005 slider row's thumb from `current` to `target` (0…1), as UITestSliders' `dragSlider`: the line
    /// runs 27 pt above the row's bottom, 34 pt in from each side; 0 and 1 overshoot onto the end stops.
    func dragRow(_ e: XCUIElement, from current: CGFloat, to target: CGFloat) {
        let rect: CGRect = e.frame
        let width: CGFloat = max(rect.width, 1)
        let y: CGFloat = rect.height > 50 ? rect.height - 27 : rect.height / 2
        let left: CGFloat = rect.height > 50 ? 34 : 14
        let track: CGFloat = max(width - 2 * left, 1)
        func x(_ p: CGFloat) -> CGFloat { left + min(max(p, 0), 1) * track }
        let origin = e.coordinate(withNormalizedOffset: .zero)
        let endX: CGFloat = target <= 0 ? -10 : (target >= 1 ? width + 10 : x(target))
        origin.withOffset(CGVector(dx: x(current), dy: y))
            .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: endX, dy: y)), withVelocity: .slow,
                   thenHoldForDuration: 0.1)
    }
}

@MainActor
final class B07MediaDeviceTests: B07Case {
    // MARK: MED-001 photo layer

    /// MED-001-T22 (D1, D3): Choose from Photos… with no permission prompt; the photo renders; relaunch keeps it.
    /// "Limited access" does not apply: the out-of-process PHPicker asks no library access (MED-001 research D1), so
    /// there is no access level to vary; recorded as `limitedAccessApplies=0`.
    func testMED001PhotosPickerNoPrompt() {
        let task = "MED-001-T22"
        launch(visual: "photo", extra: Self.seedLibrary(["photo-small.jpg"]))
        guard waitLibrarySeed(task) else { return }
        pickFromPhotos("choosePhotoFromPhotos")
        assertNoPrompt(task, "Choose from Photos")
        let summary = settledSummary("photoSummary")
        closeSettingsPanel()
        XCTAssertTrue(wait(20) { self.photoValue.hasPrefix("Photo ") }, "\(task): the picked photo is shown: \(photoValue) (\(summary))")
        let frames = probeCount("photoFramesShown")
        pause(1)
        XCTAssertGreaterThan(probeCount("photoFramesShown"), frames, "\(task): frames keep showing the photo")
        let (stats, _) = screen(task, "picked photo")
        XCTAssertGreaterThan(stats.nonBlack, 0.3, "\(task): the photo fills the screen")
        let shown = photoValue
        relaunch()
        XCTAssertTrue(wait(20) { self.photoValue == shown }, "\(task): relaunch keeps it: \(photoValue) (was \(shown))")
        assertNoPrompt(task, "relaunch")
        report(task, "photos pick", ["kept": photoValue == shown ? 1 : 0, "limitedAccessApplies": 0])
    }

    /// MED-001-T23 (D1, D3): Choose from Files… from On My iPhone/iPad, relaunch, Remove Photo. The iCloud Drive file
    /// not yet downloaded stays a person's (iCloud sign-in and eviction are not controllable here).
    func testMED001FilesPickRelaunchRemove() {
        let task = "MED-001-T23"
        launch(visual: "photo")
        pickFromFiles("choosePhotoFromFiles", "photo-small.jpg")
        let stored = settledSummary("photoSummary")
        XCTAssertTrue(stored.contains("320 × 240"), "\(task): the stored size: \(stored)")
        closeSettingsPanel()
        XCTAssertTrue(wait(20) { self.photoValue == "Photo 320 × 240" }, "\(task): shown: \(photoValue)")
        relaunch()
        XCTAssertTrue(wait(20) { self.photoValue == "Photo 320 × 240" }, "\(task): after relaunch: \(photoValue)")
        openSettingsPanel()
        tapControl("removePhoto")
        XCTAssertTrue(wait(5) { !self.app.buttons["removePhoto"].exists }, "\(task): removed")
        closeSettingsPanel()
        XCTAssertTrue(wait(10) { self.photoValue == "No photo" }, "\(task): falls back: \(photoValue)")
        relaunch()
        XCTAssertTrue(wait(10) { self.photoValue == "No photo" }, "\(task): stays removed: \(photoValue)")
    }

    /// MED-001-T24 (D1, D3): a HEIC with GPS (the stored copy has none), a 60 MP panorama (stored at 4096 px), a
    /// 45 MB JPEG (the 40 MB notice; the app keeps running and keeps the photo it had).
    func testMED001HEICLocationPanoramaLarge() {
        let task = "MED-001-T24"
        launch(visual: "photo")
        pickFromFiles("choosePhotoFromFiles", "photo-gps.heic")
        let heic = settledSummary("photoSummary")
        XCTAssertTrue(heic.contains("1024 × 768"), "\(task): the HEIC imports: \(heic)")
        let metadata = text("photoStoredMetadata")
        XCTAssertTrue(metadata.contains("gps=none"), "\(task): the stored copy has no location: \(metadata)")
        print("MED-001-T24 stored HEIC copy: \(metadata)")

        let started = Date()
        pickFromFiles("choosePhotoFromFiles", "panorama-60mp.png")
        let panorama = settledSummary("photoSummary", timeout: 90)
        let seconds = Date().timeIntervalSince(started)
        XCTAssertTrue(panorama.contains("4096 × "), "\(task): the 60 MP panorama is stored at 4096 px: \(panorama)")

        pickFromFiles("choosePhotoFromFiles", "photo-45mb.jpg")
        let noticeShown = waitForNotice("larger than 40 MB")
        XCTAssertTrue(noticeShown, "\(task): the 40 MB notice")
        XCTAssertEqual(app.state, .runningForeground, "\(task): the app keeps running")
        XCTAssertEqual(settledSummary("photoSummary"), panorama, "\(task): the refused file leaves the photo")
        closeSettingsPanel()
        XCTAssertTrue(wait(20) { self.photoValue.hasPrefix("Photo 4096 × ") }, "\(task): the panorama renders: \(photoValue)")
        report(task, "HEIC, panorama, 45 MB", ["gpsStripped": metadata.contains("gps=none") ? 1 : 0,
                                              "panoramaSeconds": seconds, "noticeShown": noticeShown ? 1 : 0])
    }

    /// MED-014-T23 (D1, D3): a real camera HEIC and a camera HEVC clip (Dolby Vision on iPhone 15 when HDR video is
    /// on, the default), the 60 MP HEIC panorama and the Mac's HLG HEVC: each imports and renders, no refusal. ProRAW
    /// DNG stays the owner's (D1 is not a Pro model; a Pro-made DNG file would be needed).
    func testMED014RealCameraMediaPanoramaAndHDR() {
        let task = "MED-014-T23"
        launch(visual: "photo")
        ui.cameraApp(photo: true)
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10), "\(task): back in the app")
        pickFromPhotos("choosePhotoFromPhotos")
        let camera = settledSummary("photoSummary")
        XCTAssertFalse(labelled("isn't an image").exists || labelled("couldn't").exists, "\(task): the camera HEIC is not refused")
        XCTAssertTrue(camera.contains(" × "), "\(task): the camera HEIC imports: \(camera)")
        print("MED-014-T23 camera photo copy: \(text("photoStoredMetadata"))")

        pickFromFiles("choosePhotoFromFiles", "panorama-60mp.heic")
        let panorama = settledSummary("photoSummary", timeout: 90)
        XCTAssertTrue(panorama.contains("4096 × "), "\(task): the HEIC panorama imports: \(panorama)")
        closeSettingsPanel()
        XCTAssertTrue(wait(20) { self.photoValue.hasPrefix("Photo 4096") }, "\(task): it renders: \(photoValue)")

        chooseVisual("video")
        pickFromFiles("chooseVideoFromFiles", "video-hdr-hlg.mov")
        let hlg = settledSummary("videoSummary", timeout: 90)
        closeSettingsPanel()
        XCTAssertTrue(wait(30) { self.videoValue == "Video 1920 × 1080" }, "\(task): the HLG clip plays: \(videoValue) (\(hlg))")
        assertDrawingAndMoving(task, "HLG HEVC")

        ui.cameraApp(record: 3)
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10), "\(task): back in the app")
        pickFromPhotos("chooseVideoFromPhotos")
        let clip = settledSummary("videoSummary", timeout: 90)
        XCTAssertFalse(text("videoNotice").contains("couldn"), "\(task): the camera clip is not refused: \(text("videoNotice"))")
        closeSettingsPanel()
        XCTAssertTrue(wait(30) { self.videoValue.hasPrefix("Video ") }, "\(task): the camera clip plays: \(videoValue) (\(clip), HLG was \(hlg))")
        // QA-011 pass 5 (D3): "-1 is not greater than -1": the probe read "1,234" (SwiftUI formats the count with a
        // grouping separator once it passes 999) and Int() rejected it. `probeCount` keeps the digits only.
        let frames = probeCount("videoFramesShown")
        pause(1)
        XCTAssertGreaterThan(probeCount("videoFramesShown"), frames, "\(task): its pictures keep coming (\(frames) before)")
        report(task, "real and HDR media", ["cameraPhoto": camera.contains(" × ") ? 1 : 0,
                                           "cameraClip": videoValue.hasPrefix("Video ") ? 1 : 0])
    }

    // MARK: MED-002 video layer

    /// MED-002-T26 (D1, D3): a camera HEVC clip through Photos and the Mac's H.264 file through Files, no permission
    /// prompt, Remove Video, relaunch.
    func testMED002PhotosAndFilesVideoPicks() {
        let task = "MED-002-T26"
        launch(visual: "video")
        ui.cameraApp(record: 3)
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10), "\(task): back in the app")
        pickFromPhotos("chooseVideoFromPhotos")
        assertNoPrompt(task, "Choose from Photos")
        let camera = settledSummary("videoSummary", timeout: 90)
        closeSettingsPanel()
        XCTAssertTrue(wait(30) { self.videoValue.hasPrefix("Video ") }, "\(task): the camera clip plays: \(videoValue) (\(camera))")

        openSettingsPanel()
        tapControl("removeVideo")
        XCTAssertTrue(wait(5) { !self.app.buttons["removeVideo"].exists }, "\(task): Remove Video")
        closeSettingsPanel()
        XCTAssertTrue(wait(10) { self.videoValue == "No video" }, "\(task): no video: \(videoValue)")

        pickFromFiles("chooseVideoFromFiles", "video-h264-1080p.mp4")
        assertNoPrompt(task, "Choose from Files")
        _ = settledSummary("videoSummary", timeout: 90)
        closeSettingsPanel()
        XCTAssertTrue(wait(30) { self.videoValue == "Video 1920 × 1080" }, "\(task): the H.264 file plays: \(videoValue)")
        relaunch()
        XCTAssertTrue(wait(30) { self.videoValue == "Video 1920 × 1080" }, "\(task): relaunch keeps it: \(videoValue)")
        assertDrawingAndMoving(task, "H.264 after relaunch")
    }

    // MARK: MED-003 loop region, MED-004 speed (the Mac's 10 s H.264 1080p clip)

    /// The Mac's 10 s H.264 1080p clip, imported at launch through the picked-file path (`-uitestSeedVideo h264-1080p`:
    /// Documents/video-h264-1080p.mp4, else a counter of that shape). Picking it in Files is MED-002-T26's check; here a
    /// failed pick hid the loop sliders and the Speed menu (they show only with a stored video), so MED-003 and
    /// MED-004 measured nothing of their own (QA-011 pass 3 and 4, D2 and D3, 2026-11-19).
    private func pickTenSecondClip(_ task: String) {
        launch(visual: "video", extra: ["-uitestSeedVideo", "h264-1080p", "-uitestSettingsSection", "video"])
        XCTAssertTrue(wait(60) { self.videoValue == "Video 1920 × 1080" }, "\(task): the 1080p clip plays: \(videoValue)")
    }

    /// "<in ms>-<out ms>" → seconds.
    private func loopRegion() -> (Double, Double)? {
        let parts = text("videoLoopRegion").split(separator: "-").compactMap { Double($0) }
        return parts.count == 2 ? (parts[0] / 1000, parts[1] / 1000) : nil
    }

    private func loopStats() -> (wraps: Int, gap: Int, early: Int) {
        let f = Self.fields(text("videoLoopStats"))
        return (Int(f["wraps"] ?? "") ?? -1, Int(f["gap"] ?? "") ?? -1, Int(f["early"] ?? "") ?? -1)
    }

    /// Shown pictures (30 fps timeline) that fall outside `region` among `samples` readings 0.3 s apart.
    private func indicesOutside(_ region: (Double, Double), samples: Int = 10) -> (outside: Int, read: Int) {
        var outside = 0, read = 0
        for _ in 0..<samples {
            if let i = Int(text("videoMediaFrameIndex")) {
                read += 1
                let t = Double(i) / 30
                if t < region.0 - 0.07 || t > region.1 + 0.07 { outside += 1 }
            }
            pause(0.3)
        }
        return (outside, read)
    }

    /// MED-003-T20 (D1): a picked clip, a region set with the Loop in/out sliders, five joints with no stall (the
    /// layer's wrap lateness under one picture), background and relaunch inside the region, Reset.
    func testMED003LoopRegion() {
        let task = "MED-003-T20"
        pickTenSecondClip(task)
        openSettingsPanel()
        // ACC-005 rows (any element type; the frame is the whole row), dragged by touch as VideoLoopUITests does.
        let loopIn = sliderRow("videoLoopIn"), loopOut = sliderRow("videoLoopOut")
        XCTAssertTrue(revealRow(loopOut) && loopIn.exists, "\(task): the loop sliders")
        if revealRow(loopIn) { dragRow(loopIn, from: 0, to: 0.2) }
        if revealRow(loopOut) { dragRow(loopOut, from: 1, to: 0.5) }
        closeSettingsPanel()
        XCTAssertTrue(wait(5) { self.loopRegion() != nil }, "\(task): a region applies: \(text("videoLoopRegion"))")
        guard let region = loopRegion() else { return }
        let length = region.1 - region.0
        XCTAssertGreaterThan(length, 0.24, "\(task): region \(region)")
        let started = loopStats().wraps
        let joined = wait(length * 6 + 10) { self.loopStats().wraps >= started + 5 }
        let stats = loopStats()
        XCTAssertTrue(joined, "\(task): five joints (wraps \(started) → \(stats.wraps))")
        XCTAssertEqual(stats.gap, 0, "\(task): no joint was late by a picture or more: \(text("videoLoopStats"))")
        let inside = indicesOutside(region)
        XCTAssertEqual(inside.outside, 0, "\(task): every shown picture lies in the region (\(inside.read) read)")

        XCUIDevice.shared.press(.home)
        pause(3)
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10), "\(task): back from the background")
        let afterBackground = indicesOutside(region, samples: 6)
        XCTAssertEqual(afterBackground.outside, 0, "\(task): inside after the background (\(afterBackground.read) read)")

        relaunch()
        XCTAssertTrue(wait(30) { self.videoValue == "Video 1920 × 1080" }, "\(task): plays after relaunch")
        XCTAssertTrue(wait(10) { self.loopRegion().map { abs($0.0 - region.0) < 0.01 && abs($0.1 - region.1) < 0.01 } ?? false },
                      "\(task): relaunch keeps the region: \(text("videoLoopRegion"))")
        let afterRelaunch = indicesOutside(region, samples: 6)
        XCTAssertEqual(afterRelaunch.outside, 0, "\(task): inside after relaunch (\(afterRelaunch.read) read)")

        openSettingsPanel()
        tapControl("videoLoopReset")
        closeSettingsPanel()
        XCTAssertTrue(wait(5) { self.text("videoLoopRegion") == "whole" }, "\(task): Reset: \(text("videoLoopRegion"))")
        report(task, "loop region", ["inSeconds": region.0, "outSeconds": region.1, "wraps": Double(stats.wraps - started),
                                     "gapFrames": Double(stats.gap), "earlyEnds": Double(stats.early)])
    }

    private func speedRatio() -> Double? {
        Double(Self.fields(text("videoSpeed"))["ratio"] ?? "")
    }

    private func setSpeed(_ spoken: String, _ shown: String, percent: Int) {
        openSettingsPanel()
        guard tapControl("videoSpeedPicker") else { return }
        var item = app.buttons[spoken].firstMatch
        if !wait(3, { item.exists }) { item = app.buttons[shown].firstMatch }
        XCTAssertTrue(wait(3) { item.exists }, "Speed offers \(spoken)")
        if item.exists { item.tap() }
        closeSettingsPanel()
        XCTAssertTrue(wait(5) { self.text("videoSpeed").hasPrefix("\(percent) ") }, "speed \(percent): \(text("videoSpeed"))")
    }

    /// Video pictures per second and late pictures over `seconds` (the `videoFrameRate` probe, once a second).
    private func videoRate(seconds: Int) -> (median: Double, late: Int) {
        var rates: [Double] = [], late = 0
        for _ in 0..<seconds {
            pause(1)
            let f = Self.fields(text("videoFrameRate"))
            if let fps = Double(f["fps"] ?? "") { rates.append(fps) }
            late += Int(f["late"] ?? "") ?? 0
        }
        return (Self.median(rates), late)
    }

    /// MED-004-T22 (D1): the picked clip at 2× keeps media time at 2 s per second (late pictures allowed, no
    /// slowdown), at 0.25× steady (a quarter of the clip's 30 pictures per second, none late), and the In-App
    /// Playback music advances 1 s per second at every speed.
    func testMED004SpeedRates() {
        let task = "MED-004-T22"
        pickTenSecondClip(task)
        for (spoken, shown, percent) in [("Double speed", "2×", 200), ("Quarter speed", "0.25×", 25), ("Normal speed", "1×", 100)] {
            setSpeed(spoken, shown, percent: percent)
            pause(3)   // the measured ratio restarts at the change
            let musicStart = musicPosition(), startTime = Date()
            let rate = videoRate(seconds: 6)
            let ratio = speedRatio() ?? -1
            let musicEnd = musicPosition()
            let wall = Date().timeIntervalSince(startTime)
            let expected = Double(percent) / 100
            report(task, "\(percent) %", ["ratio": ratio, "videoFPS": rate.median, "late": Double(rate.late),
                                          "musicAdvance": (musicEnd ?? -1) - (musicStart ?? -1)])
            XCTAssertEqual(ratio, expected, accuracy: expected * 0.05, "\(task) \(percent) %: media time per second")
            if percent == 25 {
                XCTAssertEqual(rate.median, 7.5, accuracy: 1.5, "\(task) 0.25×: a steady quarter of 30 pictures per second")
                XCTAssertEqual(rate.late, 0, "\(task) 0.25×: no late pictures")
            }
            if let a = musicStart, let b = musicEnd, b > a {   // a track change wraps the position
                XCTAssertEqual(b - a, wall, accuracy: 1.6, "\(task) \(percent) %: the music keeps its own rate (1 s per s)")
            }
        }
        XCTAssertTrue(overlayFPS() == nil || (overlayFPS() ?? 0) > 0, "the overlay reads")
        XCTAssertEqual(app.state, .runningForeground, "no crash")
    }

    // MARK: MED-006 slideshow

    private func slide() -> (index: Int, changes: Int)? {
        let parts = text("slideshowProbe").split(separator: " ")
        guard parts.count == 2, let i = Int(parts[0]), let c = Int(parts[1].replacingOccurrences(of: "changes=", with: "")) else { return nil }
        return (i, c)
    }

    /// Follows the slideshow for `seconds`; returns the indices shown in turn, whether each step was the next one, and
    /// the seconds between two seen changes (the probe is polled about every 0.15 s).
    private func followSlides(seconds: Double, count: Int) -> (sequence: [Int], inOrder: Bool, intervals: [Double]) {
        var sequence: [Int] = [], inOrder = true, changedAt: [Date] = []
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if let s = slide(), sequence.last != s.index {
                if let last = sequence.last, s.index != (last + 1) % count { inOrder = false }
                if !sequence.isEmpty { changedAt.append(Date()) }   // the first reading is not a change
                sequence.append(s.index)
            }
            pause(0.1)
        }
        let intervals = zip(changedAt.dropFirst(), changedAt).map { $0.timeIntervalSince($1) }
        return (sequence, inOrder, intervals)
    }

    /// Seconds per picture through the slider's VoiceOver decrement (the DEBUG probe buttons,
    /// `-uitestAccessibilityActions`): one step per tap, read back from the slider's spoken value.
    private func setSlideSeconds(_ task: String, to target: Int) -> Bool {
        let slider = element("slideshowSecondsSlider")
        let down = app.buttons["slideshowSecondsSlider.uitestDecrement"].firstMatch
        // The probe button, not the slider row: an ACC-005 row can report not hittable while on screen (autotester).
        XCTAssertTrue(scrollTo(down), "\(task): Seconds per picture's decrement probe")
        func seconds() -> Int? { Int(((slider.value as? String) ?? "").prefix { $0.isNumber }) }
        for _ in 0..<60 {
            guard let now = seconds(), now > target, down.exists else { break }
            down.tap()
            _ = wait(2) { (seconds() ?? now) < now }
        }
        let shown = seconds()
        XCTAssertEqual(shown, target, "\(task): Seconds per picture reads \(slider.value as? String ?? "nothing")")
        return shown == target
    }

    /// MED-006-T22 (D1): five pictures chosen at once in the real Photos picker and two from Files cycle in their
    /// saved order in Time mode (2 s) and Beats mode (every beat at a tapped 120 BPM: `-uitestTapInterval 500` spaces
    /// the four taps exactly); relaunch keeps the order and the mode.
    ///
    /// QA-011 pass 5 (D3, iPadOS 26.5, 2026-11-19), a test bug and a threshold, no app defect:
    /// * Time saw [1, 2, 3, 4] in 16 s, a change about every 5 s: the slider drag (from 3/58 of the row) missed the
    ///   thumb on the iPad's Settings row, so Seconds stayed at the default 5. The seconds are now set through the
    ///   slider's own VoiceOver decrement (`-uitestAccessibilityActions` probe buttons) and read back as 2.
    /// * Beats saw [6, 0, 1, 2, 3] in 6 s: four changes about 1.0-1.5 s apart, which is MED-006-R7's safety floor
    ///   (1 s at the Standard profile: two changes are never closer, so "every beat" at 120 BPM changes on every second
    ///   or third beat). Six slides in 6 s cannot happen on a correct app. The step now follows 9 s and checks the
    ///   rule itself: at least 5 changes, none closer than the floor, and a median gap under the 2 s Time fallback
    ///   (so the beat drives it). Spec 127 Clarifications.
    func testMED006SlideshowFromPhotosAndFiles() {
        let task = "MED-006-T22"
        let slides = (1...5).map { "slide-\($0).png" }
        launch(visual: "photo", settings: ["settings.performanceOverlay": false],
               extra: Self.seedLibrary(slides) + ["-uitestTapInterval", "500", "-uitestAccessibilityActions"])
        guard waitLibrarySeed(task) else { return }
        openSettingsPanel()
        guard tapControl("slideshowAddFromPhotos") else { return }
        XCTAssertTrue(ui.photosPick(count: 5), "\(task): five at once")
        XCTAssertTrue(wait(60) { self.text("slideshowSummary") == "5 pictures" }, "\(task): \(text("slideshowSummary"))")
        for name in ["photo-small.jpg", "photo-transparent.png"] {
            guard tapControl("slideshowAddFromFiles") else { return }
            XCTAssertTrue(ui.filesPick(name: name), "\(task): Files \(name)")
            pause(1)
        }
        XCTAssertTrue(wait(30) { self.text("slideshowSummary") == "7 pictures" }, "\(task): \(text("slideshowSummary"))")
        setSwitch("slideshowToggle", on: true)
        // An ACC-005 adjustable row, not a slider: `app.sliders` never found it, and a drag missed the thumb (pass 4,
        // D2 and pass 5, D3: Time stayed at the default 5 s). From 5 s to 2 s by three VoiceOver decrements.
        _ = setSlideSeconds(task, to: 2)
        pause(0.5)
        closeSettingsPanel()
        let time = followSlides(seconds: 16, count: 7)
        let timeGap = Self.median(time.intervals)
        XCTAssertGreaterThanOrEqual(time.sequence.count, 5, "\(task) Time: slides change: \(time.sequence)")
        XCTAssertTrue(time.inOrder, "\(task) Time: in the saved order: \(time.sequence)")
        XCTAssertEqual(timeGap, 2, accuracy: 0.4, "\(task) Time: a picture every 2 s: gaps \(time.intervals)")

        openSettingsPanel()
        chooseMenu("slideshowModePicker", "On the beat")
        chooseMenu("slideshowBeatsPicker", "Every beat")
        closeSettingsPanel()
        showControlsBar()
        let tap = app.buttons["tapTempo"].firstMatch
        XCTAssertTrue(wait(5) { tap.exists }, "\(task): Tap tempo")
        for _ in 0..<4 { if tap.exists { tap.tap() } }
        // MED-006-R7: every beat at 120 BPM (0.5 s) is held to the 1 s Standard floor, so a change comes on the first
        // beat at or after 1 s: gaps of 1.0 or 1.5 s (0.15 s polling). Time's 2 s fallback would give 2 s gaps.
        let beats = followSlides(seconds: 9, count: 7)
        let beatGap = Self.median(beats.intervals)
        report(task, "beats", ["changes": Double(beats.sequence.count - 1), "medianGap": beatGap,
                               "minGap": beats.intervals.min() ?? -1])
        XCTAssertGreaterThanOrEqual(beats.sequence.count, 6, "\(task) Beats: at least 5 changes in 9 s: \(beats.sequence)")
        XCTAssertTrue(beats.inOrder, "\(task) Beats: in order: \(beats.sequence)")
        XCTAssertGreaterThanOrEqual(beats.intervals.min() ?? 1, 0.8, "\(task) Beats: never closer than the 1 s floor: \(beats.intervals)")
        XCTAssertLessThanOrEqual(beatGap, 1.7, "\(task) Beats: the beat drives it (not the 2 s fallback): \(beats.intervals)")

        relaunch()
        openSettingsPanel()
        _ = scrollTo(app.switches["slideshowToggle"].firstMatch, swipes: 12)   // the list builds no off-screen rows
        XCTAssertTrue(wait(10) { self.text("slideshowSummary") == "7 pictures" },
                      "\(task): relaunch keeps the pictures: \(text("slideshowSummary"))")
        let mode = app.buttons["slideshowModePicker"].firstMatch
        _ = scrollTo(mode)
        XCTAssertTrue("\(mode.label) \(mode.value as? String ?? "")".contains("On the beat"), "\(task): relaunch keeps Beats: \(mode.label)")
        closeSettingsPanel()
        let after = followSlides(seconds: 12, count: 7)   // no tempo after a relaunch: the seconds fallback
        XCTAssertTrue(after.inOrder, "\(task): relaunch keeps the order: \(after.sequence)")
        report(task, "slideshow", ["timeSteps": Double(time.sequence.count), "beatSteps": Double(beats.sequence.count),
                                   "afterRelaunchSteps": Double(after.sequence.count)])
    }

    // MARK: MED-007 Ken Burns

    private func kenBurnsOn() {
        openSettingsPanel()
        setSwitch("kenBurnsToggle", on: true)
    }

    /// MED-007-T16 (D1): Zoom in over 10 s moves steadily (the change from the first picture grows every 2 s) and holds
    /// after 10 s; Reduce Motion (`-uitestReduceMotion YES`) holds the start framing; in a slideshow the movement
    /// restarts at each slide.
    ///
    /// QA-011 pass 4 (D2, D3 2026-11-19), test bugs, no app defect found: (1) the first picture of the zoom and of
    /// Reduce Motion was taken with the controls up (closing Settings shows them for 5 s; on an iPad they cover
    /// `stillRegion`), so the zoom looked non-monotonic on D3 and Reduce Motion "moved" 0.264 on D2;
    /// `hideControlsForShot` now hides them first. (2) The slideshow step expected a 2 s Duration to end inside a 5 s
    /// slide, but MED-007-R8 runs every slide's movement over the slide's dwell (KenBurnsCoordinator
    /// .slideDwellNanoseconds), so "still late in the slide" never held on a correct app. The step now checks R8 itself:
    /// every slide moves during its dwell, and slides 0 and 2 (the same picture) start at the same framing, which holds
    /// only when the movement restarts at each change. (3) No music (`music: false`): on D3 the held pictures differed
    /// by a uniform 1.2 % brightness step (no edge moved) while the spectrum played; the photo's framing is what is
    /// measured. The slides are seeded (`-uitestSeedPhoto kenBurnsSlides`: two patterned pictures, Time 5 s) instead
    /// of picked in Files (MED-006 covers the pick).
    func testMED007KenBurns() {
        let task = "MED-007-T16"
        let quiet: [String: Any] = ["settings.performanceOverlay": false]
        launch(visual: "photo", settings: quiet, extra: ["-uitestSeedPhoto", "pattern", "-uitestSettingsSection", "kenBurns"],
               music: false)
        kenBurnsOn()
        XCTAssertEqual(text("kenBurnsSummary"), "Zoom in, 10 s", "\(task): the default movement")
        closeSettingsPanel()
        hideControlsForShot()
        let first = screen(task, "zoom 0 s").1
        var fromStart: [Double] = []
        for k in 1...4 {
            pause(2)
            fromStart.append(stillChange(first, screen(task, "zoom \(2 * k) s").1))
        }
        pause(4)   // past 10 s
        let held1 = screen(task, "held a").1
        pause(2)
        let held2 = screen(task, "held b").1
        let hold = stillChange(held1, held2)
        report(task, "zoom in", ["d2": fromStart[0], "d4": fromStart[1], "d6": fromStart[2], "d8": fromStart[3], "hold": hold])
        XCTAssertGreaterThan(fromStart[0], 0.002, "\(task): the photo moves")
        for (a, b) in zip(fromStart, fromStart.dropFirst()) {
            XCTAssertGreaterThanOrEqual(b, a * 0.9, "\(task): the zoom keeps going one way: \(fromStart)")
        }
        XCTAssertLessThan(hold, 0.002, "\(task): it holds after 10 s")

        relaunch(["-uitestReduceMotion", "YES", "-uitestSettingsSection", "kenBurns"])
        openSettingsPanel()
        XCTAssertTrue(wait(5) { self.app.descendants(matching: .any)["kenBurnsReduceMotionNote"].firstMatch.exists },
                      "\(task): the Reduce Motion note")
        closeSettingsPanel()
        hideControlsForShot()
        let r1 = screen(task, "reduce motion a").1
        pause(2)
        let still = stillChange(r1, screen(task, "reduce motion b").1)
        report(task, "reduce motion", ["change": still])
        XCTAssertLessThan(still, 0.002, "\(task): Reduce Motion holds the start framing")

        launch(visual: "photo", settings: quiet,
               extra: ["-uitestSeedPhoto", "kenBurnsSlides", "-uitestSettingsSection", "kenBurns"], music: false)
        XCTAssertTrue(wait(20) { self.slide() != nil }, "\(task): the seeded slideshow runs: \(text("slideshowProbe"))")
        kenBurnsOn()   // Time mode, 5 s slides: each slide's movement lasts 5 s (MED-007-R8)
        closeSettingsPanel()
        hideControlsForShot()
        var starts: [[UInt8]] = [], within: [Double] = []
        for n in 0..<3 {
            let before = slide()?.changes ?? -1
            guard wait(8, { (self.slide()?.changes ?? -1) > before }) else { XCTFail("\(task): no slide change"); break }
            pause(0.4)
            let a = screen(task, "slide \(n) start").1
            pause(1.2)   // both pictures inside the 5 s slide (a screenshot takes about 1.3 s on D3)
            let moved = stillChange(a, screen(task, "slide \(n) later").1)
            report(task, "slide \(n)", ["moved": moved])
            starts.append(a)
            within.append(moved)
        }
        XCTAssertTrue(within.count == 3 && within.allSatisfy { $0 > 0.002 },
                      "\(task): every slide moves during its dwell: \(within)")
        if starts.count == 3 {
            let restart = stillChange(starts[0], starts[2])   // the same picture, both about 0.5 s into their slide
            report(task, "restart", ["sameStartChange": restart, "minMoved": within.min() ?? 0])
            XCTAssertLessThan(restart, (within.min() ?? 0) * 0.5,
                              "\(task): the movement restarts at each slide (slides 0 and 2 start at the same framing)")
        }
    }

    // MARK: MED-008 animated GIF

    /// The yellow bar's mean column in a band above the centred spectrum (animated-200.gif: a yellow bar sweeping a
    /// 160 × 120 frame, filled to the screen), or nil when it is off screen.
    ///
    /// QA-011 pass 5 (D3, 2026-11-19), a test bug: the GIF played (the bar sat at a different column in each of the 20
    /// screenshots), but the band was 70-74 % of the height, which on an iPad in portrait lies under the controls
    /// panel (it starts at 66 %), so the bar was found in one picture only ("bar seen at [19]"). The band is now
    /// 12-20 %: below the status bar and a notification banner, above the spectrum, clear of the controls on every
    /// device.
    private func barColumn(_ p: [UInt8]) -> Double? {
        let (w, h) = lastSize
        guard w > 0, h > 0 else { return nil }
        var sum = 0.0, n = 0
        for y in Int(Double(h) * 0.12)..<Int(Double(h) * 0.20) {
            for x in 0..<w {
                let i = (y * w + x) * 4
                guard i + 3 < p.count else { continue }
                if p[i] > 190, p[i + 1] > 150, p[i + 2] < 100 { sum += Double(x); n += 1 }
            }
        }
        return n > 3 ? sum / Double(n) / Double(w) : nil
    }

    /// MED-008-T12 (D1): the Mac's 200-frame GIF plays for a minute (the bar moves) within the device's animated-frame
    /// budget (AnimatedFrameBudget: 32/64/128 MB by memory), with no growth; Reduce Motion holds frame 0. Also picked
    /// once through Photos (`animatedThroughPhotos`): the Photos picker must keep the frames (preferred encoding).
    func testMED008LargeGIF() {
        let task = "MED-008-T12"
        launch(visual: "photo", settings: ["settings.performanceOverlay": false], extra: Self.seedLibrary(["animated-200.gif"]))
        guard waitLibrarySeed(task) else { return }
        pickFromPhotos("choosePhotoFromPhotos")
        _ = settledSummary("photoSummary")
        closeSettingsPanel()
        let viaPhotos = wait(15) { self.photoValue.hasPrefix("Animated photo") }
        XCTAssertTrue(viaPhotos, "\(task): the GIF picked in Photos stays animated: \(photoValue)")

        pickFromFiles("choosePhotoFromFiles", "animated-200.gif")
        _ = settledSummary("photoSummary")
        closeSettingsPanel()
        XCTAssertTrue(wait(15) { self.photoValue.hasPrefix("Animated photo 160 × 120, 200 frames") }, "\(task): \(photoValue)")
        pause(3)
        let baseline = footprintMB() ?? -1
        var footprints: [Int] = [], columns: Set<Int> = [], seen = 0
        for s in 0..<20 {   // 60 s
            pause(3)
            if let mb = footprintMB() { footprints.append(mb) }
            if let c = barColumn(screen(task, "gif \(s)").1) { columns.insert(Int(c * 20)); seen += 1 }
        }
        let gib = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        let budget = gib < 4 ? 32 : gib < 8 ? 64 : 128
        let peak = footprints.max() ?? -1
        let third = max(1, footprints.count / 3)
        let early = footprints.prefix(third).reduce(0, +) / third, late = footprints.suffix(third).reduce(0, +) / third
        report(task, "one minute", ["baselineMB": Double(baseline), "peakMB": Double(peak), "budgetMB": Double(budget),
                                    "earlyMB": Double(early), "lateMB": Double(late), "barPositions": Double(columns.count),
                                    "barSeen": Double(seen), "viaPhotosAnimated": viaPhotos ? 1 : 0])
        XCTAssertGreaterThanOrEqual(columns.count, 3, "\(task): the animation plays (bar seen at \(columns.sorted()))")
        XCTAssertLessThanOrEqual(peak - baseline, budget, "\(task): growth within the \(budget) MB animated-frame budget")
        XCTAssertLessThanOrEqual(late, early + 10, "\(task): no growth over the minute (\(early) → \(late) MB)")

        relaunch(["-uitestReduceMotion", "YES"])
        XCTAssertTrue(wait(15) { self.photoValue.hasPrefix("Animated photo") }, "\(task): after relaunch: \(photoValue)")
        pause(2)
        let a = screen(task, "reduce motion a").1
        let barA = barColumn(a)
        pause(1.3)
        let b = screen(task, "reduce motion b").1
        let barB = barColumn(b)
        report(task, "reduce motion", ["change": stillChange(a, b)])
        XCTAssertEqual(barA.map { Int($0 * 100) }, barB.map { Int($0 * 100) }, "\(task): Reduce Motion holds frame 0")
        XCTAssertLessThan(stillChange(a, b), 0.002, "\(task): the picture holds")
    }

    // MARK: MED-009 text

    /// MED-009-T23 (D1, D3): the editor at the largest Dynamic Type size (AX5), right-to-left text typed in Arabic and
    /// Hebrew (with the app in that language) and emoji with skin tones; relaunch shows the same text and the same
    /// rendering. XCUITest types the characters itself; typing on the real Arabic and Hebrew keyboards stays a person's.
    func testMED009LargestTypeRTLEmoji() {
        let task = "MED-009-T23"
        let ax5 = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        let cases: [(String, [String], String)] = [
            ("en", [], "Hello 👋🏽 👍🏿 🧑🏻‍🎤"),
            ("ar", ["-AppleLanguages", "(ar)", "-AppleLocale", "ar"], "مرحبا بالعالم 👋🏾"),
            ("he", ["-AppleLanguages", "(he)", "-AppleLocale", "he"], "שלום עולם 👍🏼"),
        ]
        for (language, arguments, message) in cases {
            launch(visual: "text", settings: ["settings.performanceOverlay": false],
                   extra: ax5 + arguments + ["-uitestSettingsSection", "text"])
            openSettingsPanel()
            let field = app.descendants(matching: .any)["textMessageField"].firstMatch
            XCTAssertTrue(scrollTo(field), "\(task) \(language): the Message field at AX5")
            field.tap()
            let old = (field.value as? String) ?? ""
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count + 4))
            field.typeText(message)
            let issues = auditIssues(app, "text editor \(language) AX5", types: [.textClipped, .dynamicType])
            issues.forEach { print("MED-009-T23 audit: \($0)") }
            closeSettingsPanel()
            XCTAssertTrue(wait(10) { self.visualValue("textVisual") == message },
                          "\(task) \(language): the visual shows the text: \(visualValue("textVisual"))")
            _ = wait(10) { !["none", "drawing"].contains(self.text("textRendering")) }
            let rendering = text("textRendering")
            relaunch(ax5 + arguments)
            XCTAssertTrue(wait(10) { self.visualValue("textVisual") == message },
                          "\(task) \(language): relaunch keeps the text: \(visualValue("textVisual"))")
            XCTAssertTrue(wait(10) { self.text("textRendering") == rendering },
                          "\(task) \(language): the same rendering (\(rendering) vs \(text("textRendering")))")
            report(task, language, ["auditIssues": Double(issues.count), "kept": text("textRendering") == rendering ? 1 : 0])
            app.terminate()
        }
    }

    // MARK: MED-010 logo

    /// Dark-fringe check in one corner: the logo's bright pixels, and how many of the pixels touching them are darker
    /// than the background (a premultiplied-alpha fault draws a dark rim). `corner`: (0|1, 0|1) = (right?, bottom?).
    /// `excluded`: rectangles in sample coordinates left out of both counts (the app's own buttons in the corner).
    private func fringe(_ shot: (pixels: [UInt8], width: Int, height: Int), corner: (Int, Int),
                        excluded: [CGRect] = []) -> (bright: Int, edge: Int, dark: Int, bg: Double) {
        let (p, w, h) = shot
        let s = Double(min(w, h))
        let span = Int(s * 0.28)   // margin 0.04 + size 0.15 of the short side, with room
        let x0 = corner.0 == 0 ? 0 : w - span, y0 = corner.1 == 0 ? 0 : h - span
        func at(_ x: Int, _ y: Int) -> Int { (y * w + x) * 4 }
        func skipped(_ x: Int, _ y: Int) -> Bool {
            excluded.contains { $0.contains(CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5)) }
        }
        // The background: the corner's pixel nearest the screen edge inside the margin.
        let bx = corner.0 == 0 ? Int(s * 0.01) : w - 1 - Int(s * 0.01), by = corner.1 == 0 ? Int(s * 0.01) : h - 1 - Int(s * 0.01)
        let bg = Self.luma(p, at(bx, by))
        var bright = Set<Int>()
        for y in y0..<(y0 + span) {
            for x in x0..<(x0 + span) where !skipped(x, y) && Self.luma(p, at(x, y)) > min(0.97, bg + 0.3) {
                bright.insert(y * w + x)
            }
        }
        var edge = 0, dark = 0
        for y in (y0 + 1)..<(y0 + span - 1) {
            for x in (x0 + 1)..<(x0 + span - 1) where !bright.contains(y * w + x) && !skipped(x, y) {
                let touches = bright.contains(y * w + x - 1) || bright.contains(y * w + x + 1)
                    || bright.contains((y - 1) * w + x) || bright.contains((y + 1) * w + x)
                guard touches else { continue }
                edge += 1
                if Self.luma(p, at(x, y)) < bg - 0.08 { dark += 1 }
            }
        }
        return (bright.count, edge, dark, bg)
    }

    /// The app's always-shown buttons (Emergency Blackout: a black disc with a white eye in the bottom-right corner)
    /// in sample coordinates, grown by 4 pt: on D2 and D3 its white symbol on black counted as the logo's "dark fringe"
    /// (QA-011 pass 4, 2026-11-19).
    private func cornerButtons(sampleWidth: Int) -> [CGRect] {
        let window = app.windows.firstMatch.frame
        guard window.width > 0 else { return [] }
        let perPoint: CGFloat = CGFloat(sampleWidth) / window.width
        return ["emergencyBlackout"].compactMap { (id: String) -> CGRect? in
            let e = app.descendants(matching: .any)[id].firstMatch
            guard e.exists, e.frame.width > 0 else { return nil }
            let f = e.frame.insetBy(dx: -4, dy: -4)
            return CGRect(x: (f.minX - window.minX) * perPoint, y: (f.minY - window.minY) * perPoint,
                          width: f.width * perPoint, height: f.height * perPoint)
        }
    }

    private func logoInCorners(_ task: String, _ source: String, _ names: [String] = ["Top left", "Top right", "Bottom left", "Bottom right"]) {
        let all: [String: (Int, Int)] = ["Top left": (0, 0), "Top right": (1, 0), "Bottom left": (0, 1), "Bottom right": (1, 1)]
        for name in names {
            guard let corner = all[name] else { continue }
            openSettingsPanel()
            chooseMenu("logoPositionPicker", name)
            closeSettingsPanel()
            hideControlsForShot()
            pause(0.9)
            let shot = pixels(task, "\(source) \(name)", step: 2)
            let f = fringe(shot, corner: corner, excluded: cornerButtons(sampleWidth: shot.width))
            report(task, "\(source) \(name)", ["brightPixels": Double(f.bright), "edgePixels": Double(f.edge),
                                               "darkEdgePixels": Double(f.dark), "backgroundLuma": f.bg])
            XCTAssertGreaterThan(f.bright, 50, "\(task) \(source) \(name): the logo is drawn in that corner")
            XCTAssertLessThanOrEqual(Double(f.dark), Double(max(f.edge, 1)) * 0.02, "\(task) \(source) \(name): no dark fringe")
        }
    }

    /// MED-010-T25 (D1): the white-disc PNG over the Photo visual (solid orange), clean-edged in each corner; then the
    /// same file picked in Files and in the real Photos picker is stored and drawn.
    ///
    /// QA-011 pass 4 (D2, D3 2026-11-19), test bugs, no app defect: every corner was photographed with the controls up
    /// (closing Settings shows them for 5 s; on an iPad they fill both bottom corners, so their white text on the black
    /// panel read as a "dark fringe" of 305 to 1400 pixels) and the Emergency Blackout button sat in the bottom-right
    /// corner; with the logo actually drawn (Files, top corners on D2) the fringe count was 0. And the corner sweep
    /// waited on two picks that failed for picker reasons (another lane's work), so it measured no logo at all on D3.
    /// The sweep now runs on the white disc imported at launch through the picked-logo path (`-uitestSeedLogo
    /// white-disc`: Documents/logo-white-disc.png), with the controls hidden and the button left out; the Files pick
    /// (opened in Documents, `-uitestPickerInDocuments`) and the Photos pick each check one corner.
    func testMED010LogoCorners() {
        let task = "MED-010-T25"
        let quiet: [String: Any] = ["settings.performanceOverlay": false]
        launch(visual: "photo", settings: quiet,
               extra: ["-uitestSeedPhoto", "solid", "-uitestSeedLogo", "white-disc", "-uitestPickerInDocuments"], music: false)
        XCTAssertTrue(wait(20) { self.text("logoProbe").hasSuffix("logo=yes") }, "\(task): the white disc is stored: \(text("logoProbe"))")
        logoInCorners(task, "Seeded")

        openSettingsPanel()
        tapControl("removeLogo")   // so the Files pick is what is shown
        closeSettingsPanel()
        _ = wait(5) { self.text("logoProbe").hasSuffix("logo=no") }
        pickFromFiles("chooseLogoFromFiles", "logo-white-disc.png")
        XCTAssertFalse(text("logoNotice").contains("couldn"), "\(task): no refusal: \(text("logoNotice"))")
        closeSettingsPanel()
        XCTAssertTrue(wait(20) { self.text("logoProbe").hasSuffix("logo=yes") }, "\(task): Files logo stored: \(text("logoProbe"))")
        logoInCorners(task, "Files", ["Bottom right"])

        launch(visual: "photo", settings: quiet,
               extra: ["-uitestSeedPhoto", "solid"] + Self.seedLibrary(["logo-white-disc.png"]), music: false)
        waitLibrarySeed(task)
        pickFromPhotos("chooseLogoFromPhotos")
        XCTAssertTrue(wait(20) { self.text("logoProbe").hasSuffix("logo=yes") }, "\(task): Photos logo stored: \(text("logoProbe"))")
        closeSettingsPanel()
        logoInCorners(task, "Photos", ["Top left"])
    }
}
