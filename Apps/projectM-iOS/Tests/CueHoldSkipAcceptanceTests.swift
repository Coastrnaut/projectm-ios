// CueHoldSkipAcceptanceTests.swift — SHOW-005-T09, T12 (contract specs/232-show-005-cue-hold-skip/contracts/
// show-cue-hold-skip.md H1-H4, K3-K4): the roadmap acceptance "Hold prevents automatic advances; manual next remains
// available" through the app's real step path (a `ShowCoordinator` over a temporary store, SHOW-002's driver on a
// `ShowManualClock`, SHOW-003's quantizer with a synthetic 120 BPM grid). `tick()` is called by the test; no task runs
// and nothing waits on the wall clock.
import Foundation
import ParameterGraph
import PerformanceControl
import SceneFormat
import ShowControl
import ShowStorage
import TextLayer
import VisualGenerators
import XCTest
@testable import projectM_iOS

@MainActor
final class CueHoldSkipAcceptanceTests: XCTestCase {
    static let anchor: UInt64 = 10_000_000_000
    static let beat: UInt64 = 500_000_000

    private var show: ShowCoordinator!
    private var driver: ShowAutoAdvanceCoordinator!
    private var clock: ShowManualClock!
    private var defaults: UserDefaults!
    private var announced: [String] = []

    /// Five cues with 30 s dwells over a temporary store; the driver never starts its own task.
    override func setUp() async throws {
        let suite = "SHOW005-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        show = ShowCoordinator(store: ShowStore(directory: url), registry: try SceneArchiveService.appRegistry())
        show.applyScene = { (_: SceneDocument, _: [SceneIssue]) -> [String] in [] }
        show.announce = { [unowned self] (text: String) in self.announced.append(text) }
        for n in 1...5 {
            let look = ShowLook(visual: .circularSpectrum, bars: 64, orientation: .horizontal, spacing: 0.5, glowEnabled: false,
                                glowIntensity: 0.7, glowRadius: 0.03, glowThreshold: 0.4, text: TextOverlaySpec(message: ""),
                                photoID: nil, videoID: nil)
            XCTAssertTrue(show.addScene(ShowSceneSnapshot.document(look, id: UUID().uuidString, name: "Cue \(n)"), label: "Cue \(n)"))
        }
        for cue in show.list.cues { XCTAssertTrue(show.setDwell(cue.id, to: try ShowCueDwell(seconds: 30))) }
        clock = ShowManualClock()
        driver = ShowAutoAdvanceCoordinator(show: show, clock: clock, runsLoop: false)
    }

    private var number: Int? { show.list.activeIndex.map { (i: Int) -> Int in i + 1 } }

    /// Ticks once a second until `end` (whole seconds); returns the times at which the show moved.
    private func run(until end: Int) -> [Int] {
        var moved: [Int] = []
        var index: Int? = show.list.activeIndex
        while clock.now() < .seconds(end) {
            clock.advance(by: .seconds(1))
            driver.tick()
            if show.list.activeIndex != index {
                index = show.list.activeIndex
                moved.append(Int(clock.now().components.seconds))
            }
        }
        return moved
    }

    // MARK: - US1: Hold (H1-H3)

    func testHoldPreventsAutomaticAdvancesWhileManualNextRemainsAvailable() throws {
        show.next()
        XCTAssertEqual(run(until: 18), [])
        driver.setOperatorHold(true)
        XCTAssertEqual(driver.countdown, .init(seconds: 12, held: true))
        XCTAssertEqual(driver.countdownText, "Next in 0:12, held")
        XCTAssertEqual(run(until: 30), [], "no automatic advance at the deadline")
        XCTAssertEqual(run(until: 30 + 600), [], "none 10 minutes past it either")
        XCTAssertEqual(number, 1)

        XCTAssertTrue(show.setSkipped(show.list.cues[1].id, true))
        XCTAssertEqual(show.next().outcome, .moved, "manual Next stays available")
        XCTAssertEqual(number, 3, "exactly one (non-skipped) cue: cue 2 is skipped")
        XCTAssertEqual(driver.countdown, .init(seconds: 30, held: true), "the new cue starts held with its full dwell")
        XCTAssertEqual(run(until: 700), [], "still held")
    }

    func testReleasingHoldResumesWithTheKeptRemainingTime() {
        show.next()
        _ = run(until: 18)
        driver.setOperatorHold(true)
        _ = run(until: 100)
        driver.setOperatorHold(false)
        XCTAssertEqual(driver.countdown, .init(seconds: 12, held: false))
        XCTAssertEqual(run(until: 111), [], "not before the kept 12 s")
        XCTAssertEqual(run(until: 112), [112], "exactly when the kept 12 s have elapsed")
        XCTAssertEqual(number, 2)
        XCTAssertEqual(driver.countdown?.seconds, 30, "the next cue counts down normally")
    }

    func testHoldCombinesWithTheOtherHoldSources() {
        var paused = false
        driver.isHeld = { () -> Bool in paused }
        show.next()
        _ = run(until: 10)
        driver.setOperatorHold(true)
        paused = true
        _ = run(until: 50)
        driver.setOperatorHold(false)
        XCTAssertEqual(run(until: 80), [], "pause still holds after Hold is released")
        paused = false   // read by the next tick, at t = 81
        XCTAssertEqual(run(until: 100), [], "not before the kept 20 s")
        XCTAssertEqual(run(until: 101), [101], "20 s kept from t = 10, released at t = 81")
    }

    // MARK: - US1: a timed step waiting for the beat (H4)

    func testHoldWithdrawsATimedStepWaitingForTheBeat() throws {
        let settings = AppSettings(defaults: defaults, systemReduceMotion: false)
        var source = TempoSource()
        source.updateEstimate(TempoEstimate(bpm: 120, confidence: 1, beatNanoseconds: Self.anchor))
        let tempo: TempoSnapshot = source.snapshot
        var now: UInt64 = Self.anchor + 3 * Self.beat + 220_000_000
        let quantizer: ShowCueQuantizer = settings.showCueQuantizer
        quantizer.schedulesWakeUps = false
        quantizer.clock = { () -> UInt64 in now }
        quantizer.tempo = { () -> TempoSnapshot in tempo }
        show.cueQuantizer = quantizer
        show.next()   // Off: immediate
        quantizer.mode = .beat

        _ = run(until: 30)
        XCTAssertNotNil(quantizer.queuedText, "the due timed advance waits for the beat")
        XCTAssertEqual(number, 1)
        driver.setOperatorHold(true)
        XCTAssertNil(quantizer.queuedText, "Hold withdrew the waiting timed step")
        XCTAssertEqual(driver.countdown, .init(seconds: 0, held: true))
        now = Self.anchor + 6 * Self.beat
        quantizer.tick(at: now)
        XCTAssertEqual(number, 1, "nothing lands at the beat while held")
        XCTAssertEqual(run(until: 300), [])

        driver.setOperatorHold(false)
        driver.tick()
        XCTAssertNotNil(quantizer.queuedText, "Hold off requests the advance again at once")
        now = Self.anchor + 7 * Self.beat
        quantizer.tick(at: now)
        XCTAssertEqual(number, 2, "one cue, at the next beat")
    }

    // MARK: - US2: Skip in the app (K3, K4)

    func testTimedAdvancePassesOverSkippedCuesAndASkipEditCancelsAnOrphanedCountdown() {
        XCTAssertTrue(show.setSkipped(show.list.cues[1].id, true))
        XCTAssertTrue(show.setSkipped(show.list.cues[2].id, true))
        show.next()
        XCTAssertEqual(run(until: 30), [30])
        XCTAssertEqual(number, 4, "the timed advance passed over cues 2 and 3")
        XCTAssertEqual(driver.countdown?.seconds, 30)
        XCTAssertTrue(show.setSkipped(show.list.cues[4].id, true))
        XCTAssertNil(driver.countdown, "no cue left to advance to: the countdown is cancelled")
        XCTAssertFalse(show.list.canGoNext)
        XCTAssertTrue(show.setSkipped(show.list.cues[4].id, false))
        XCTAssertNil(driver.countdown, "unskipping never starts automation")
        XCTAssertEqual(number, 4, "Skip edits never move the show")
    }

    func testLockRefusesSkipEditsButNotHoldAndDuplicateKeepsTheFlag() throws {
        let lock = SceneLock(defaults: defaults)
        show.sceneLock = lock
        lock.lock()
        let second: UUID = show.list.cues[1].id
        XCTAssertFalse(show.setSkipped(second, true), "a Skip edit is an edit")
        XCTAssertFalse(show.list.cues[1].skipped)
        XCTAssertEqual(show.editorMessage, SceneLock.refusalMessage)
        driver.setOperatorHold(true)
        XCTAssertTrue(driver.isOperatorHeld, "Hold is performance state, allowed while locked")
        lock.unlock()
        XCTAssertTrue(show.setSkipped(second, true))
        let copy = try XCTUnwrap(show.duplicateScene(of: second))
        XCTAssertTrue(copy.skipped, "Duplicate Scene copies the flag")
    }

    func testAllSkippedDoesNotMoveAndPostsANotice() {
        show.next()
        for cue in show.list.cues { XCTAssertTrue(show.setSkipped(cue.id, true)) }
        XCTAssertEqual(show.statusText, "Cue 1 of 5 · Cue 1 · all skipped")
        XCTAssertEqual(show.next().outcome, .allSkipped)
        XCTAssertEqual(number, 1)
        XCTAssertEqual(show.notice, ShowCoordinator.allSkippedMessage)
        XCTAssertEqual(announced.last, ShowCoordinator.allSkippedMessage)
        XCTAssertEqual(show.go(to: show.list.cues[3].id).outcome, .moved, "Go to Cue still reaches a skipped cue")
    }
}
