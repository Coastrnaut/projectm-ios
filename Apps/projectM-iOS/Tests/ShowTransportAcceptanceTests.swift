// ShowTransportAcceptanceTests.swift — SHOW-007-T09, T12: the roadmap acceptance "Seek updates scheduled parameter values
// without duplicate events" (SHOW-007-S1 to S3; contract specs/243-show-007-timeline-transport/contracts/
// show-timeline-transport.md T2 to T6) through the app's real step path: a `ShowCoordinator` over a temporary store,
// SHOW-002's driver on a `ShowManualClock`, SHOW-003's cue quantizer and MOD-017's parameter quantizer in Cue mode (as
// AppCoordinator wires `applyScene`), and a recorder of every event: scene applies, transitions driven, announcements,
// MOD-017 applies and quantized steps. `tick()` is called by the test; no task runs and nothing waits on the wall clock.
import Compositor
import Foundation
import LibraryBackup
import ParameterGraph
import PerformanceControl
import SceneFormat
import ShowControl
import ShowStorage
import TextLayer
import VisualGenerators
import VisualParameters
import XCTest
@testable import projectM_iOS

@MainActor
private final class EventRecorder: CueTransitionDriving {
    var applies: [String] = []
    var transitions: [SceneTransitionSpec] = []
    var announcements: [String] = []
    var parameterApplies: [ParameterID] = []

    var total: Int { applies.count + transitions.count + announcements.count + parameterApplies.count }

    func driveTransition(_ spec: SceneTransitionSpec, toScene sceneID: String) { transitions.append(spec) }
}

@MainActor
final class ShowTransportAcceptanceTests: XCTestCase {
    static let anchor: UInt64 = 10_000_000_000
    static let beat: UInt64 = 500_000_000

    private var show: ShowCoordinator!
    private var driver: ShowAutoAdvanceCoordinator!
    private var transport: ShowTransportCoordinator!
    private var clock: ShowManualClock!
    private var defaults: UserDefaults!
    private var settings: AppSettings!
    private var recorder: EventRecorder!
    private var reduceFlashing = false

    /// Five cues with 30 s dwells (a 2:30 timeline), each scene a 2 s crossfade by default; MOD-017 in Cue mode.
    override func setUp() async throws {
        let suite = "SHOW007-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        settings = AppSettings(defaults: defaults, systemReduceMotion: false)
        recorder = EventRecorder()
        let recorder: EventRecorder = self.recorder
        let parameters: ParameterQuantizer = settings.parameterQuantizer
        parameters.hasCues = { () -> Bool in true }
        parameters.schedulesWakeUps = false
        parameters.apply = { (id: ParameterID, _: ParameterValue) -> Void in recorder.parameterApplies.append(id) }
        parameters.announce = { (text: String) -> Void in recorder.announcements.append(text) }
        show = ShowCoordinator(store: ShowStore(directory: url), registry: try SceneArchiveService.appRegistry())
        show.applyScene = { (document: SceneDocument, _: [SceneIssue]) -> [String] in   // as AppCoordinator+Show wires it
            recorder.applies.append(document.id)
            parameters.cueApplied()   // MOD-017-R8
            return []
        }
        show.announce = { (text: String) in recorder.announcements.append(text) }
        show.transitionDriver = recorder
        show.transitionSafety = { [unowned self] () -> (reduceMotion: Bool, reduceFlashing: Bool) in
            (reduceMotion: false, reduceFlashing: self.reduceFlashing)
        }
        let fade = try ShowCueTransition(type: .crossfade, durationSeconds: 2)
        for n in 1...5 {
            let look = ShowLook(visual: .circularSpectrum, bars: 64, orientation: .horizontal, spacing: 0.5, glowEnabled: false,
                                glowIntensity: 0.7, glowRadius: 0.03, glowThreshold: 0.4, text: TextOverlaySpec(message: ""),
                                photoID: nil, videoID: nil)
            XCTAssertTrue(show.addScene(ShowSceneSnapshot.document(look, id: UUID().uuidString, name: "Cue \(n)"), label: "Cue \(n)"))
        }
        for cue in show.list.cues {
            XCTAssertTrue(show.setDwell(cue.id, to: try ShowCueDwell(seconds: 30)))
            XCTAssertTrue(show.setTransition(cue.id, to: fade))
        }
        let cues: ShowCueQuantizer = settings.showCueQuantizer
        cues.schedulesWakeUps = false
        cues.announce = { (text: String) -> Void in recorder.announcements.append(text) }
        show.cueQuantizer = cues
        clock = ShowManualClock()
        driver = ShowAutoAdvanceCoordinator(show: show, clock: clock, runsLoop: false)
        transport = ShowTransportCoordinator(show: show, driver: driver, defaults: defaults)
    }

    private func scene(_ n: Int) -> String { show.list.cues[n - 1].sceneID }
    private var number: Int? { show.list.activeIndex.map { (i: Int) -> Int in i + 1 } }

    /// Ticks once a second until `end` (whole seconds).
    private func run(until end: Int) {
        while clock.now() < .seconds(end) {
            clock.advance(by: .seconds(1))
            driver.tick()
        }
    }

    // MARK: - US1: seek (T2, T3)

    func testSeekAcrossCuesAppliesOnlyTheDestinationOnceAndRepeatsAreSilent() throws {
        show.next()   // cue 1 at t = 0
        XCTAssertEqual(recorder.applies, [scene(1)])
        settings.parameterQuantizer.mode = .cue
        let glow: ParameterID = VisualParameterIDs.bloomEnabled
        settings.parameterQuantizer.request(glow, value: .boolean(true), current: .boolean(false)) { (_: ParameterValue) in
            XCTFail("Cue mode queues the change")
        }
        recorder.announcements.removeAll()
        let before: (transitions: Int, steps: Int) = (recorder.transitions.count, settings.showCueQuantizer.appliedAtBoundary)

        XCTAssertEqual(transport.seek(to: .seconds(105)), .apply(cueID: show.list.cues[3].id, remaining: .seconds(15)))
        XCTAssertEqual(number, 4)
        XCTAssertEqual(recorder.applies, [scene(1), scene(4)], "exactly one apply: the destination; cues 2 and 3 never")
        XCTAssertEqual(recorder.transitions.count, before.transitions + 1, "one transition drive")
        XCTAssertEqual(recorder.transitions.last, .cut, "it lands on the target state (a cut, not the cue's 2 s fade)")
        XCTAssertEqual(recorder.parameterApplies, [glow], "MOD-017's Cue-mode change applies once, on top of the destination")
        XCTAssertEqual(recorder.announcements.filter { (t: String) -> Bool in !t.hasSuffix(", applied") }, [],
                       "a seek announces nothing (MOD-017's own apply line only)")
        XCTAssertEqual(settings.showCueQuantizer.appliedAtBoundary, before.steps, "no quantized step")
        XCTAssertEqual(driver.countdown, .init(seconds: 15, held: false), "the countdown is positioned at the seek")
        XCTAssertEqual(transport.currentTime(), .seconds(105))

        let events: Int = recorder.total
        XCTAssertEqual(transport.seek(to: .seconds(105)), .none, "the same seek again")
        XCTAssertEqual(recorder.total, events, "repeated seeks fire nothing new")
        clock.advance(by: .seconds(3))
        XCTAssertEqual(transport.seek(to: .seconds(105)), .reposition(cueID: show.list.cues[3].id, remaining: .seconds(15)))
        XCTAssertEqual(recorder.total, events, "a seek inside the active cue only moves the countdown")
        XCTAssertEqual(driver.countdown?.seconds, 15)

        run(until: 18)
        XCTAssertEqual(number, 5, "the timed advance continues from the seek's position (15 s later)")
        XCTAssertEqual(recorder.applies.count, 3)
    }

    func testScrubCommitsOneSeekAndPassedOverCuesStaySilent() {
        show.next()
        let events: Int = recorder.total
        transport.beginScrub()
        for s in [12.0, 40, 66, 95, 130, 70] { transport.scrub(toSeconds: s) }
        XCTAssertEqual(recorder.total, events, "dragging applies nothing")
        XCTAssertEqual(number, 1)
        XCTAssertEqual(transport.positionText(), "Cue 3 · Cue 3 at 0:10", "the preview names the destination")
        transport.endScrub()
        XCTAssertEqual(number, 3)
        XCTAssertEqual(recorder.applies, [scene(1), scene(3)], "one commit, one apply")
        XCTAssertEqual(transport.appliedSeeks, 1)
        XCTAssertEqual(transport.positionText(), "1:10 / 2:30")
    }

    func testSeekWithdrawsAWaitingQuantizedStepAndSkippedCuesAreNotOnTheTimeline() throws {
        var source = TempoSource()
        source.updateEstimate(TempoEstimate(bpm: 120, confidence: 1, beatNanoseconds: Self.anchor))
        let tempo: TempoSnapshot = source.snapshot
        let quantizer: ShowCueQuantizer = settings.showCueQuantizer
        quantizer.clock = { () -> UInt64 in Self.anchor + 220_000_000 }
        quantizer.tempo = { () -> TempoSnapshot in tempo }
        show.next()
        quantizer.mode = .beat
        XCTAssertEqual(show.next().outcome, .queued, "Next waits for the beat")
        XCTAssertTrue(show.setSkipped(show.list.cues[2].id, true))
        XCTAssertEqual(transport.timeline.duration, .seconds(120), "cue 3 skipped: four timed cues")

        XCTAssertEqual(transport.seek(to: .seconds(65)), .apply(cueID: show.list.cues[3].id, remaining: .seconds(25)),
                       "65 s is inside cue 4 (cue 3 has no span)")
        XCTAssertNil(quantizer.queuedText, "the seek withdrew the waiting step")
        quantizer.tick(at: Self.anchor + 4 * Self.beat)
        XCTAssertEqual(number, 4, "nothing fires at the beat after the seek")
        XCTAssertEqual(recorder.applies, [scene(1), scene(4)])
    }

    func testReduceFlashingWidensTheSeekCutAndTheLockAllowsSeeking() {
        let lock = SceneLock(defaults: defaults)
        show.sceneLock = lock
        lock.lock()
        reduceFlashing = true
        show.next()
        transport.seek(to: .seconds(45))
        XCTAssertEqual(number, 2, "a seek is a performance action, allowed while locked")
        let spec: SceneTransitionSpec? = recorder.transitions.last
        XCTAssertEqual(spec?.style, .crossfade)
        XCTAssertEqual(spec?.durationSeconds, CueTransitionResolver.reduceFlashingMinimumSeconds,
                       "Reduce flashing widens the cut to its minimum fade, not the cue's 2 s")
    }

    // MARK: - US2: play, pause, loop (T5, T6)

    func testPausePlayKeepsTheRemainingDwellAndPlayAtStandbyStartsOnce() {
        XCTAssertFalse(transport.isPlaying, "Standby offers Play")
        transport.play()
        XCTAssertEqual(recorder.applies, [scene(1)], "Play at Standby applies the first cue once")
        run(until: 42)
        XCTAssertEqual(number, 2)
        XCTAssertEqual(driver.countdown?.seconds, 18)
        transport.pause()
        XCTAssertFalse(transport.isPlaying)
        run(until: 42 + 600)
        XCTAssertEqual(number, 2, "paused for 10 minutes")
        XCTAssertEqual(driver.countdown, .init(seconds: 18, held: true))
        XCTAssertEqual(transport.currentTime(), .seconds(42), "the position is frozen too")
        transport.play()
        XCTAssertEqual(driver.countdown, .init(seconds: 18, held: false), "Play keeps the remaining dwell")
        run(until: 642 + 17)
        XCTAssertEqual(number, 2)
        run(until: 642 + 18)
        XCTAssertEqual(number, 3)
    }

    func testLoopWrapsExactlyOncePerPassAndOffDoesNot() {
        show.next()
        run(until: 300)
        XCTAssertEqual(number, 5, "Loop off: the show stops on the last cue")
        XCTAssertEqual(driver.loopWraps, 0)
        XCTAssertNil(driver.countdown, "SHOW-002 unchanged: no countdown on the last cue")
        XCTAssertEqual(transport.currentTime(), .seconds(150), "the position ran to the end")

        XCTAssertEqual(transport.seek(to: .zero), .apply(cueID: show.list.cues[0].id, remaining: .seconds(30)))
        let start: Int = Int(clock.now().components.seconds)
        recorder.applies.removeAll()
        transport.setLoops(true)
        XCTAssertEqual(defaults.object(forKey: ShowTransportCoordinator.loopKey) as? Bool, true)
        run(until: start + 300)   // two passes of 150 s
        XCTAssertEqual(driver.loopWraps, 2, "exactly one wrap per pass")
        let perCue: [Int] = (1...5).map { (n: Int) -> Int in recorder.applies.filter { (id: String) -> Bool in id == scene(n) }.count }
        XCTAssertEqual(perCue, [2, 2, 2, 2, 2], "each cue applied once per pass: cue 1 twice by wraps, the rest by advances")
        XCTAssertEqual(number, 1, "the third pass has started")

        transport.setLoops(false)
        XCTAssertNil(defaults.object(forKey: ShowTransportCoordinator.loopKey), "Off removes the key")
        transport.seek(to: .seconds(140))
        run(until: start + 300 + 60)
        XCTAssertEqual(driver.loopWraps, 2, "no wrap with Loop off")
        XCTAssertEqual(number, 5)
    }

    func testLoopKeyIsStoredResetAndNeverBackedUp() {
        XCTAssertFalse(transport.loops, "off by default")
        transport.setLoops(true)
        XCTAssertTrue(ShowTransportCoordinator(show: show, driver: driver, defaults: defaults).loops, "remembered on the device")
        XCTAssertTrue(AppSettings.allKeys.contains(ShowTransportCoordinator.loopKey), "cleared by -uitestResetNotice and Settings erase")
        XCTAssertTrue(LibrarySettingsPolicy.excludedKeys.contains(ShowTransportCoordinator.loopKey), "never backed up")
        XCTAssertFalse(LibrarySettingsPolicy.isIncluded(ShowTransportCoordinator.loopKey))
        XCTAssertTrue(LibraryErasePolicy.erasableKeys.contains(ShowTransportCoordinator.loopKey))
    }
}
