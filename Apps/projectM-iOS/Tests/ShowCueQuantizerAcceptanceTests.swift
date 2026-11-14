// ShowCueQuantizerAcceptanceTests.swift — SHOW-003-T07, T08, T10 (US1 to US3; R2 to R8; S1 to S4): the roadmap
// acceptance "Synthetic beats trigger once and missing tempo uses explicit fallback" through the app's real step path
// (a real `ShowCoordinator` over a temporary store, `AppSettings`' quantizers wired as the app wires them, SHOW-002's
// driver on a manual clock). Synthetic 120 BPM grid and injected times; wake-ups off; no wall clock.
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
final class ShowCueQuantizerAcceptanceTests: XCTestCase {
    static let anchor: UInt64 = 10_000_000_000
    static let beat: UInt64 = 500_000_000

    private var defaults: UserDefaults!
    private var settings: AppSettings!
    private var quantizer: ShowCueQuantizer!
    private var show: ShowCoordinator!
    private var applied: [String] = []
    private var ids: [String] = []
    private var announced: [String] = []
    private var now: UInt64 = 0
    private var tempo: TempoSnapshot = .none

    override func setUp() async throws {
        let suite = "SHOW003-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        settings = AppSettings(defaults: defaults, systemReduceMotion: false)
        settings.glowEnabled = false
        var source = TempoSource()
        source.updateEstimate(TempoEstimate(bpm: 120, confidence: 1, beatNanoseconds: Self.anchor))
        tempo = source.snapshot

        let folder: URL = FileManager.default.temporaryDirectory.appendingPathComponent("SHOW003-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let registry: ParameterRegistry = try SceneArchiveService.appRegistry()
        show = ShowCoordinator(store: ShowStore(directory: folder), registry: registry)
        show.announce = { (_: String) in }
        let settings: AppSettings = self.settings
        show.applyScene = { [unowned self] (document: SceneDocument, warnings: [SceneIssue]) -> [String] in   // as AppCoordinator+Show
            self.applied.append(document.id)
            let apply: ShowSceneApply = ShowSceneSnapshot.apply(of: document, warnings: warnings, registry: registry)
            if let glow = apply.parameters[VisualParameterIDs.bloomEnabled]?.boolValue { settings.glowEnabled = glow }
            settings.parameterQuantizer.cueApplied()
            return []
        }
        for index in 0..<4 {
            let look = ShowLook(visual: .circularSpectrum, bars: 64, orientation: .horizontal, spacing: 0.5, glowEnabled: false,
                                glowIntensity: 0.7, glowRadius: 0.03, glowThreshold: 0.4, text: TextOverlaySpec(message: ""),
                                photoID: nil, videoID: nil)
            let document: SceneDocument = ShowSceneSnapshot.document(look, id: UUID().uuidString, name: "Cue \(index)")
            ids.append(document.id)
            XCTAssertTrue(show.addScene(document, label: "Cue \(index)"))
        }

        // The app's wiring (AppCoordinator+ParameterQuantizer), with test closures for the tempo, clock and announcer.
        let parameters: ParameterQuantizer = settings.parameterQuantizer
        parameters.schedulesWakeUps = false
        parameters.connect(settings: settings, tempo: { [unowned self] () -> TempoSnapshot in self.tempo },
                           hasCues: { () -> Bool in true }, announce: { [unowned self] (text: String) -> Void in self.announced.append(text) })
        parameters.clock = { [unowned self] () -> UInt64 in self.now }
        quantizer = settings.showCueQuantizer
        quantizer.schedulesWakeUps = false
        quantizer.clock = { [unowned self] () -> UInt64 in self.now }
        quantizer.tempo = { [unowned self] () -> TempoSnapshot in self.tempo }
        quantizer.announce = { [unowned self] (text: String) -> Void in self.announced.append(text) }
        quantizer.willStep = { (deadline: UInt64) -> Void in parameters.tick(at: deadline) }
        show.cueQuantizer = quantizer
    }

    /// Ticks every 10 ms from `start` through `end`; returns how many times the active cue changed.
    private func ticks(from start: UInt64, through end: UInt64) -> Int {
        var moves = 0
        var index: Int? = show.list.activeIndex
        var t: UInt64 = start
        while t <= end {
            now = t
            quantizer.tick(at: t)
            if show.list.activeIndex != index { moves += 1; index = show.list.activeIndex }
            t += 10_000_000
        }
        return moves
    }

    // MARK: - US1 (S1): synthetic beats trigger once

    func testNextMidBeatMovesExactlyOnceAtTheNextBeat() {
        show.next()   // Standby → cue 1 (Off: immediate)
        quantizer.mode = .beat
        now = Self.anchor + 3 * Self.beat + 220_000_000
        XCTAssertEqual(show.next().outcome, .queued)
        XCTAssertEqual(show.list.activeIndex, 0, "nothing moves at the request")
        XCTAssertEqual(quantizer.queuedText, "Cue queued for the next beat")
        XCTAssertEqual(announced.last, "Cue queued for the next beat")

        let boundary: UInt64 = Self.anchor + 4 * Self.beat
        XCTAssertEqual(ticks(from: now, through: boundary - 1), 0, "none before the beat")
        now = boundary
        quantizer.tick(at: boundary)
        XCTAssertEqual(show.list.activeIndex, 1, "one cue, at the beat")
        XCTAssertEqual(applied, [ids[0], ids[1]], "the cue's scene applied once through the step path")
        XCTAssertNil(quantizer.queuedText)
        XCTAssertEqual(ticks(from: boundary, through: boundary + 3 * Self.beat), 0, "never again over 3 beats")
        XCTAssertEqual(quantizer.appliedAtBoundary, 1)
    }

    func testBarWaitsForTheBarAndLatestRequestWins() throws {
        show.go(to: show.list.cues[1].id)
        quantizer.mode = .bar
        now = Self.anchor + Self.beat + 50_000_000
        show.next()
        XCTAssertEqual(quantizer.queuedText, "Cue queued for the next bar")
        now += 100_000_000
        XCTAssertEqual(show.previous().outcome, .queued, "Previous replaces Next")
        let bar: UInt64 = Self.anchor + 4 * Self.beat
        XCTAssertEqual(ticks(from: now, through: bar - 1), 0, "the beats inside the bar change nothing")
        XCTAssertEqual(ticks(from: bar, through: bar + 8 * Self.beat), 1, "once, at the bar")
        XCTAssertEqual(show.list.activeIndex, 0, "the latest request (Previous) applied, not Next")
    }

    func testTheSameRequestAgainCancelsAndANonMovingStepIsNotQueued() {
        show.go(to: show.list.cues[3].id)   // the last cue
        quantizer.mode = .beat
        now = Self.anchor + 100
        XCTAssertEqual(show.next().outcome, .atEnd, "Next at the last cue: nothing to wait for")
        XCTAssertNil(quantizer.step.pending)

        XCTAssertEqual(show.previous().outcome, .queued)
        XCTAssertEqual(show.previous().outcome, .queued, "the second Previous cancels")
        XCTAssertEqual(announced.last, ShowCueQuantizer.cancelledAnnouncement)
        XCTAssertNil(quantizer.step.pending)
        XCTAssertEqual(ticks(from: now, through: Self.anchor + 4 * Self.beat), 0, "nothing at the beat")
        XCTAssertEqual(show.list.activeIndex, 3)
    }

    func testRemovedGoTargetDoesNothingAndModeChangeCancels() {
        show.next()
        quantizer.mode = .beat
        now = Self.anchor + 100
        let target: UUID = show.list.cues[2].id
        show.go(to: target)
        show.remove(target)
        XCTAssertEqual(ticks(from: now, through: Self.anchor + 2 * Self.beat), 0, "a removed target moves nothing")
        XCTAssertEqual(show.list.activeIndex, 0)

        show.next()
        quantizer.mode = .bar
        XCTAssertNil(quantizer.step.pending)
        XCTAssertEqual(announced.last, ShowCueQuantizer.cancelledAnnouncement)
    }

    func testSameBeatParameterChangeAppliesFirstAndCueModeChangeLandsOnTheQueuedCue() throws {
        show.next()
        quantizer.mode = .beat
        settings.parameterQuantizer.mode = .cue
        now = Self.anchor + 100
        let glow: ParameterInspectorTarget = try XCTUnwrap(ParameterInspectorTargets.quantizedTarget(for: VisualParameterIDs.bloomEnabled, settings: settings))
        glow.set(.boolean(true))   // MOD-017 Cue mode: waits for the next cue step
        show.next()
        XCTAssertFalse(settings.glowEnabled)
        now = Self.anchor + Self.beat
        quantizer.tick(at: now)
        XCTAssertEqual(show.list.activeIndex, 1)
        XCTAssertTrue(settings.glowEnabled, "MOD-017's cue-mode change lands right after the queued cue's scene")

        // MOD-017 Beat mode at the same beat: applied first (willStep), then the cue's scene (glow off) stands.
        settings.parameterQuantizer.mode = .beat
        glow.set(.boolean(false))
        settings.glowEnabled = true
        now = Self.anchor + Self.beat + 100
        glow.set(.boolean(false))
        show.next()
        quantizer.tick(at: Self.anchor + 2 * Self.beat)
        XCTAssertEqual(settings.parameterQuantizer.appliedAtBoundary, 2, "the parameter change applied (once) before the cue")
        XCTAssertFalse(settings.glowEnabled)
        XCTAssertEqual(show.list.activeIndex, 2)
    }

    // MARK: - US2 (S2): missing tempo uses the explicit fallback

    func testNoTempoMovesAtOnceWithTheFallbackAnnouncement() {
        quantizer.mode = .beat
        tempo = .none
        XCTAssertEqual(show.next().outcome, .moved)
        XCTAssertEqual(show.list.activeIndex, 0)
        XCTAssertEqual(announced.last, ShowCueQuantizer.noTempoAnnouncement)
        XCTAssertNil(quantizer.step.pending)
        XCTAssertEqual(applied.count, 1)
    }

    // MARK: - US3 (S4): a timed advance waits for the beat too

    func testTimedAdvanceMovesOnceAtTheNextBeat() throws {
        let clock = ShowManualClock()
        let driver = ShowAutoAdvanceCoordinator(show: show, clock: clock, runsLoop: false)
        XCTAssertTrue(show.setDwell(show.list.cues[0].id, to: try ShowCueDwell(seconds: 10)))
        show.next()
        quantizer.mode = .beat
        clock.advance(by: .seconds(10))
        now = Self.anchor + 300_000_000
        driver.tick()
        XCTAssertEqual(show.list.activeIndex, 0, "due, but waiting for the beat")
        driver.tick()
        XCTAssertEqual(quantizer.step.pending?.request, .next, "a second tick neither cancels nor adds a step")
        XCTAssertEqual(ticks(from: now, through: Self.anchor + 4 * Self.beat), 1, "one advance, at the beat")
        XCTAssertEqual(show.list.activeIndex, 1)
    }

    // MARK: - Settings key (R1)

    func testModeIsStoredAndListedForResetAndBackupPolicy() {
        quantizer.mode = .bar
        XCTAssertEqual(defaults.string(forKey: ShowCueQuantizer.key), "bar")
        XCTAssertEqual(ShowCueQuantizer(defaults: defaults).mode, .bar, "remembered on the device")
        quantizer.mode = .cue
        XCTAssertNil(defaults.object(forKey: ShowCueQuantizer.key), "Cue is not a cue step mode: stored as Off")
        XCTAssertTrue(AppSettings.allKeys.contains(ShowCueQuantizer.key), "cleared by -uitestResetNotice")
        XCTAssertTrue(LibrarySettingsPolicy.excludedKeys.contains(ShowCueQuantizer.key), "never backed up")
        XCTAssertTrue(LibraryErasePolicy.erasableKeys.contains(ShowCueQuantizer.key), "erased with Settings")
    }
}
