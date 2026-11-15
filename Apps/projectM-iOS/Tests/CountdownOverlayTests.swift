// CountdownOverlayTests.swift — MED-012-T09, T12: the countdown's settings, timer, layer and cue trigger in the app
// (MED-012-R1 to R10; S2 to S5). Each test uses its own UserDefaults suite; "relaunch" is a new coordinator on the same
// defaults. Time is a `ManualMonotonicClock` moved by hand; no wall clock is read and nothing waits for the tick task.
import Compositor
import Foundation
import Metal
import SceneFormat
import TextLayer
import XCTest
@testable import projectM_iOS

@MainActor
final class CountdownOverlayTests: XCTestCase {
    private func makeDefaults() throws -> (UserDefaults, String) {
        let suite = "CountdownOverlayTests.\(UUID().uuidString)"
        return (try XCTUnwrap(UserDefaults(suiteName: suite)), suite)
    }

    func testSettingsAreOffByDefaultAndSurviveARelaunchWithoutTheRun() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let clock = ManualMonotonicClock(seconds: 10)
        let countdown = CountdownOverlayCoordinator(store: CountdownOverlayStore(defaults: defaults), clock: clock)
        XCTAssertEqual(countdown.settings, .default)
        XCTAssertEqual(countdown.summary, "Off")
        XCTAssertNil(defaults.object(forKey: CountdownOverlayStore.key), "nothing written before a change")
        countdown.settings.isShown = true
        countdown.settings.minutes = 1
        countdown.settings.seconds = 30
        countdown.settings.startsFromCues = true
        countdown.settings.style.verticalPosition = .bottom
        XCTAssertEqual(countdown.summary, "01:30")
        countdown.start()
        XCTAssertEqual(Array(defaults.persistentDomain(forName: suite)?.keys ?? [:].keys), [CountdownOverlayStore.key], "one settings key")
        let relaunched = CountdownOverlayCoordinator(store: CountdownOverlayStore(defaults: defaults), clock: clock)
        XCTAssertEqual(relaunched.settings, countdown.settings, "identical after a relaunch")
        XCTAssertEqual(relaunched.state, .idle, "the running state is not stored")
        XCTAssertEqual(relaunched.currentText, "01:30")
        XCTAssertTrue(AppSettings.allKeys.contains(CountdownOverlayStore.key), "removed by the UI-test reset")

        defaults.set(Data("garbage".utf8), forKey: CountdownOverlayStore.key)
        XCTAssertEqual(CountdownOverlayStore(defaults: defaults).load(), .default)
        XCTAssertNil(defaults.object(forKey: CountdownOverlayStore.key), "a damaged value is removed")
        let newer = Data("{\"version\":9}".utf8)
        defaults.set(newer, forKey: CountdownOverlayStore.key)
        XCTAssertEqual(CountdownOverlayStore(defaults: defaults).load(), .default)
        XCTAssertEqual(defaults.data(forKey: CountdownOverlayStore.key), newer, "left untouched")
    }

    /// S2, S3, R4, R6, R7: the layer above the clock gets one string per shown second; zero once, announced once,
    /// nothing pushed after it; Reset re-arms; a duration change resets.
    func testRunPushesOncePerSecondFinishesOnceAndResetReArms() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device") }
        let clock = ManualMonotonicClock(seconds: 50)
        let countdown = CountdownOverlayCoordinator(store: CountdownOverlayStore(defaults: defaults), clock: clock)
        var spoken: [String] = []
        countdown.announce = { (text: String) in spoken.append(text) }
        let clockOverlay = ClockOverlayCoordinator(store: nil)
        var stack = LayerStack()
        try stack.add(LayerDescriptor(kind: .text))
        let compositor = try Compositor(device: device)
        let base = TextLayerSource(device: device)
        try compositor.apply(stack) { (_: LayerStackEntry) throws(LayerSourceError) -> any LayerSource in base }
        XCTAssertNotNil(clockOverlay.attach(to: compositor))
        let layer = try XCTUnwrap(countdown.attach(to: compositor))
        XCTAssertEqual(layer.layerName, "countdown")
        XCTAssertNil(countdown.attach(to: compositor), "one countdown per stack")
        let kinds = compositor.appliedStack?.entries.map { (e: LayerStackEntry) -> LayerKind in e.descriptor.kind } ?? []
        XCTAssertEqual(Array(kinds.suffix(2)), [.clock, .countdown], "the countdown sits above the clock")
        XCTAssertTrue(layer.spec.isEmpty, "hidden: nothing to draw")

        countdown.settings.durationSeconds = 3
        countdown.settings.isShown = true
        XCTAssertEqual(layer.spec.message, "00:03")
        XCTAssertFalse(countdown.isTicking, "stopped: no tick task")
        countdown.start()
        XCTAssertTrue(countdown.isTicking)
        var pushes = 0
        for _ in 0..<40 {   // quarter seconds, 10 s: crosses zero at 3 s and keeps going
            clock.advance(by: 0.25)
            if countdown.tick() { pushes += 1 }
        }
        XCTAssertEqual(pushes, 3, "02, 01, 00: one string per shown second, none after zero")
        XCTAssertEqual(layer.spec.message, "00:00")
        XCTAssertEqual(countdown.finishedCount, 1)
        XCTAssertEqual(spoken, [CountdownOverlayCoordinator.finishedAnnouncement], "announced once")
        clock.advance(by: 36_000)
        XCTAssertFalse(countdown.tick(), "ten hours later: nothing new")
        countdown.appBecameActive()
        XCTAssertEqual(countdown.finishedCount, 1)

        countdown.reset()
        XCTAssertEqual(layer.spec.message, "00:03", "Reset shows the full duration")
        countdown.start()
        clock.advance(by: 5000)   // one jump past zero (back from the background)
        countdown.appBecameActive()
        XCTAssertEqual(countdown.finishedCount, 2, "a second run finishes once more")
        XCTAssertEqual(layer.spec.message, "00:00")

        countdown.start()
        clock.advance(by: 1)
        countdown.tick()
        countdown.pause()
        XCTAssertFalse(countdown.isTicking, "paused: no tick task")
        countdown.settings.durationSeconds = 120
        XCTAssertEqual(countdown.state, .idle, "a duration change resets the run")
        XCTAssertEqual(layer.spec.message, "02:00")
        countdown.settings.isShown = false
        XCTAssertTrue(layer.spec.isEmpty, "hidden again")
    }

    /// S4, R8: a scene added while Start From New Cues is on records the duration; applying it starts the countdown at
    /// that duration; a scene without it leaves the countdown alone.
    func testACueSceneRecordsAndStartsTheCountdown() throws {
        let registry = try SceneArchiveService.appRegistry()
        var look = ShowLook(visual: .text, bars: 64, orientation: .horizontal, spacing: 0.5, glowEnabled: false, glowIntensity: 0.7,
                            glowRadius: 0.03, glowThreshold: 0.4, text: TextOverlaySpec(message: "Go"), photoID: nil, videoID: nil)
        look.countdownSeconds = 90
        let document = ShowSceneSnapshot.document(look, id: UUID().uuidString, name: "Timed")
        let decoded = try SceneDocument.decode(document.encoded())
        XCTAssertEqual(decoded.document.countdownSeconds, 90, "survives the scene round trip")
        let loaded = try decoded.document.liveState(registry: registry)
        let apply = ShowSceneSnapshot.apply(of: decoded.document, warnings: loaded.warnings, registry: registry)
        XCTAssertEqual(apply.countdownSeconds, 90)

        let clock = ManualMonotonicClock(seconds: 0)
        let countdown = CountdownOverlayCoordinator(store: nil, clock: clock)
        countdown.settings.isShown = true
        if let seconds = apply.countdownSeconds { countdown.startFromCue(seconds: seconds) }   // what applyShowScene does
        XCTAssertEqual(countdown.state, .running)
        XCTAssertEqual(countdown.currentText, "01:30")
        XCTAssertEqual(countdown.settings.durationSeconds, 300, "a cue never changes the saved duration")

        look.countdownSeconds = nil
        let plain = ShowSceneSnapshot.document(look, id: UUID().uuidString, name: "Plain")
        let plainApply = ShowSceneSnapshot.apply(of: plain, warnings: [], registry: registry)
        XCTAssertNil(plainApply.countdownSeconds, "no field: the countdown is left alone")
        XCTAssertNil(plain.extra[SceneCountdown.key])

        // R8: launch restore and reopen read `SceneRestoredValues`, which carries no countdown, so they never start one.
        let restored = SceneAutosaveCapture.restoredValues(decoded.document, live: loaded.state, registry: registry)
        let labels = Mirror(reflecting: restored).children.compactMap { (child: Mirror.Child) -> String? in child.label?.lowercased() }
        XCTAssertFalse(labels.contains { (label: String) -> Bool in label.contains("countdown") })
    }
}
