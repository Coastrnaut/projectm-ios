// SceneRotationAcceptanceTests.swift — SHOW-013-T06, T10: auto scene rotation in the app with an injected clock (spec
// SHOW-013-S2, S3; contract C3, C4). A real `ShowCoordinator` over a temporary store with five stored scenes; every switch
// goes through the show's step path (`applyScene` records the applied scene). `tick()` is called by the test; no task
// runs and nothing waits on the wall clock.
import Foundation
import LibraryBackup
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
final class SceneRotationAcceptanceTests: XCTestCase {
    private static let second: UInt64 = 1_000_000_000

    private var now: UInt64 = 0
    private var applied: [String] = []
    private var defaults: UserDefaults!
    private var show: ShowCoordinator!
    private var ids: [String] = []

    private func makeShow() throws {
        let suite = "SHOW013-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        let folder: URL = FileManager.default.temporaryDirectory.appendingPathComponent("SHOW013-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        show = ShowCoordinator(store: ShowStore(directory: folder), registry: try SceneArchiveService.appRegistry())
        show.announce = { (_: String) in }
        show.applyScene = { [unowned self] (document: SceneDocument, _: [SceneIssue]) -> [String] in
            self.applied.append(document.id)
            return []
        }
        ids = []
        for n in 1...5 {
            let look = ShowLook(visual: n % 2 == 0 ? .linearSpectrum : .circularSpectrum, bars: 16 * n, orientation: .horizontal,
                                spacing: 0.5, glowEnabled: false, glowIntensity: 0.7, glowRadius: 0.03, glowThreshold: 0.4,
                                text: TextOverlaySpec(message: "Hi"), photoID: nil, videoID: nil)
            let document = ShowSceneSnapshot.document(look, id: UUID().uuidString, name: "Scene \(n)")
            ids.append(document.id)
            XCTAssertTrue(show.addScene(document, label: "Scene \(n)"))
        }
    }

    private func makeRotation(seed: UInt64 = 7) -> SceneRotationCoordinator {
        let rotation = SceneRotationCoordinator(show: show, defaults: defaults, runsLoop: false)
        rotation.clock = { [unowned self] () -> UInt64 in self.now }
        rotation.makeSeed = { () -> UInt64 in seed }
        return rotation
    }

    private func advance(_ rotation: SceneRotationCoordinator, seconds: Int) {
        for _ in 0..<seconds {
            now += Self.second
            rotation.tick()
        }
    }

    func testATimerRotationSwitchesRealScenesThroughTheStepPath() throws {
        try makeShow()
        let rotation = makeRotation()
        rotation.update { (s: inout SceneRotationSettings) -> Void in s.intervalSeconds = 30 }
        rotation.setOn(true)
        XCTAssertEqual(rotation.statusText, "Next scene in 0:30")
        advance(rotation, seconds: 29)
        XCTAssertEqual(applied, [], "nothing before the interval")
        XCTAssertEqual(rotation.statusText, "Next scene in 0:01")
        advance(rotation, seconds: 1)
        XCTAssertEqual(applied.count, 1, "one switch at 30 s")
        XCTAssertEqual(show.appliedSceneID, applied.first, "the show applied the picked scene")
        XCTAssertEqual(show.list.activeSceneID, applied.first)
        XCTAssertEqual(rotation.statusText, "Next scene in 0:30", "the switch restarted the interval")
        advance(rotation, seconds: 60)
        XCTAssertEqual(applied.count, 3, "one switch per 30 s")
        XCTAssertNotEqual(applied[1], applied[0])
        XCTAssertNotEqual(applied[2], applied[1])
        XCTAssertEqual(rotation.rotations, 3)
    }

    func testAManualChangeRestartsTheInterval() throws {
        try makeShow()
        let rotation = makeRotation()
        rotation.update { (s: inout SceneRotationSettings) -> Void in s.intervalSeconds = 30 }
        rotation.setOn(true)
        advance(rotation, seconds: 20)
        show.go(to: show.list.cues[3].id)   // a manual Go 10 s before the deadline
        XCTAssertEqual(applied, [ids[3]])
        advance(rotation, seconds: 29)
        XCTAssertEqual(applied.count, 1, "the old deadline (30 s) never fires")
        advance(rotation, seconds: 1)
        XCTAssertEqual(applied.count, 2, "30 s after the manual change")
        XCTAssertNotEqual(applied[1], ids[3], "never the scene shown")
    }

    func testDisabledScenesNeverShowOverFiftyRotations() throws {
        try makeShow()
        let rotation = makeRotation(seed: 99)
        rotation.update { (s: inout SceneRotationSettings) -> Void in
            s.intervalSeconds = 15
            s.setEnabled(false, sceneID: ids[1])
            s.setEnabled(false, sceneID: ids[4])
        }
        rotation.setOn(true)
        advance(rotation, seconds: 15 * 50)
        XCTAssertEqual(applied.count, 50)
        XCTAssertFalse(applied.contains(ids[1]) || applied.contains(ids[4]), "disabled scenes never applied")
        XCTAssertEqual(zip(applied, applied.dropFirst()).filter { (pair: (String, String)) -> Bool in pair.0 == pair.1 }.count, 0,
                       "no immediate repeat")
        XCTAssertEqual(Set(applied), [ids[0], ids[2], ids[3]])
    }

    func testOneOrZeroEnabledScenesStayIdleWithAMessage() throws {
        try makeShow()
        let rotation = makeRotation()
        rotation.update { (s: inout SceneRotationSettings) -> Void in
            for id in self.ids.dropFirst() { s.setEnabled(false, sceneID: id) }
        }
        rotation.setOn(true)
        advance(rotation, seconds: 120)
        XCTAssertEqual(applied, [], "one enabled scene: no switching")
        XCTAssertEqual(rotation.statusText, SceneRotationCoordinator.oneSceneText)
        rotation.setEnabled(false, sceneID: ids[0])
        advance(rotation, seconds: 120)
        XCTAssertEqual(applied, [])
        XCTAssertEqual(rotation.statusText, "No scenes are in rotation.")
        rotation.setEnabled(true, sceneID: ids[0])
        rotation.setEnabled(true, sceneID: ids[2])
        advance(rotation, seconds: 60)
        XCTAssertEqual(applied.count, 1, "two enabled scenes: rotation starts")
    }

    func testHoldsAndAPlayingShowPauseRotation() throws {
        try makeShow()
        var held = false
        var plays = false
        let rotation = makeRotation()
        rotation.isHeld = { () -> Bool in held }
        rotation.showPlays = { () -> Bool in plays }
        rotation.update { (s: inout SceneRotationSettings) -> Void in s.intervalSeconds = 30 }
        rotation.setOn(true)
        advance(rotation, seconds: 20)
        plays = true
        advance(rotation, seconds: 100)
        XCTAssertEqual(applied, [], "a timed cue playing wins")
        XCTAssertEqual(rotation.statusText, SceneRotationCoordinator.showPlayingText)
        plays = false
        held = true
        advance(rotation, seconds: 50)
        XCTAssertEqual(rotation.statusText, "Held")
        held = false
        advance(rotation, seconds: 29)
        XCTAssertEqual(applied, [], "the interval restarted when the hold ended")
        advance(rotation, seconds: 2)
        XCTAssertEqual(applied.count, 1)
    }

    func testBarsModeSwitchesOnTheEighthBarLineAtOnce() throws {
        try makeShow()
        var source = TempoSource()
        source.updateEstimate(TempoEstimate(bpm: 120, confidence: 1, beatNanoseconds: 0))
        let tempo: TempoSnapshot = source.snapshot
        let quantizer = ShowCueQuantizer(defaults: defaults)
        quantizer.mode = .bar
        quantizer.schedulesWakeUps = false
        quantizer.tempo = { () -> TempoSnapshot in tempo }
        quantizer.clock = { [unowned self] () -> UInt64 in self.now }
        show.cueQuantizer = quantizer
        let rotation = makeRotation()
        rotation.tempo = { () -> TempoSnapshot in tempo }
        rotation.update { (s: inout SceneRotationSettings) -> Void in
            s.mode = .bars
            s.bars = 8
        }
        now = 3 * Self.second
        rotation.setOn(true)
        XCTAssertEqual(rotation.deadline, SceneRotationSchedule.Deadline(at: 18 * Self.second, onBeat: true), "bar lines every 2 s")
        XCTAssertEqual(rotation.statusText, "Next scene on the bar in 0:15")
        advance(rotation, seconds: 14)
        XCTAssertEqual(applied, [])
        advance(rotation, seconds: 1)
        XCTAssertEqual(applied.count, 1, "on the bar line, not quantized again to the next bar")
        XCTAssertNil(quantizer.step.pending)
    }

    func testTimerSwitchesWaitForTheCueQuantizer() throws {
        try makeShow()
        var source = TempoSource()
        source.updateEstimate(TempoEstimate(bpm: 120, confidence: 1, beatNanoseconds: 0))
        let tempo: TempoSnapshot = source.snapshot
        let quantizer = ShowCueQuantizer(defaults: defaults)
        quantizer.mode = .bar
        quantizer.schedulesWakeUps = false
        quantizer.tempo = { () -> TempoSnapshot in tempo }
        quantizer.clock = { [unowned self] () -> UInt64 in self.now }
        show.cueQuantizer = quantizer
        let rotation = makeRotation()
        rotation.update { (s: inout SceneRotationSettings) -> Void in s.intervalSeconds = 15 }
        now = Self.second / 2
        rotation.setOn(true)
        advance(rotation, seconds: 15)   // 15.5 s: due, queued for the bar at 16 s
        XCTAssertEqual(applied, [])
        XCTAssertNotNil(quantizer.step.pending, "the timed switch waits for the bar (SHOW-003)")
        XCTAssertEqual(rotation.statusText, SceneRotationCoordinator.switchingText)
        quantizer.tick(at: 16 * Self.second)
        XCTAssertEqual(applied.count, 1, "applied at the bar")
        XCTAssertEqual(rotation.statusText, "Next scene in 0:15")
    }

    func testTheSettingsLiveInOneExcludedKey() throws {
        try makeShow()
        let rotation = makeRotation()
        XCTAssertNil(defaults.object(forKey: SceneRotationCoordinator.key), "defaults store nothing")
        rotation.update { (s: inout SceneRotationSettings) -> Void in
            s.mode = .bars
            s.bars = 16
            s.setEnabled(false, sceneID: self.ids[2])
            s.setEnabled(false, sceneID: "5CE7E000-0000-4000-8000-0000000000FF")   // not in the show: pruned
        }
        let reloaded = SceneRotationCoordinator.load(defaults)
        XCTAssertEqual(reloaded.mode, .bars)
        XCTAssertEqual(reloaded.bars, 16)
        XCTAssertEqual(reloaded.disabledSceneIDs, [ids[2]])
        XCTAssertFalse(SceneRotationCoordinator(show: show, defaults: defaults, runsLoop: false).isOn, "off at every launch")
        XCTAssertTrue(AppSettings.allKeys.contains(SceneRotationCoordinator.key), "cleared by -uitestResetNotice")
        XCTAssertTrue(LibrarySettingsPolicy.excludedKeys.contains(SceneRotationCoordinator.key), "never backed up")
        XCTAssertTrue(LibraryErasePolicy.erasableKeys.contains(SceneRotationCoordinator.key), "erased with Settings")
        defaults.set(Data("not json".utf8), forKey: SceneRotationCoordinator.key)
        XCTAssertEqual(SceneRotationCoordinator.load(defaults), SceneRotationSettings(), "unreadable → defaults")
    }

    func testRotationChainsAfterTheTimedAdvance() throws {
        try makeShow()
        let driver = ShowAutoAdvanceCoordinator(show: show, clock: ShowManualClock(), runsLoop: false)
        let rotation = makeRotation()
        rotation.setOn(true)
        XCTAssertTrue(show.setDwell(show.list.cues[1].id, to: try ShowCueDwell(seconds: 10)))
        now = 40 * Self.second
        show.go(to: show.list.cues[1].id)
        XCTAssertNotNil(driver.countdown, "SHOW-002 still hears the step")
        XCTAssertEqual(rotation.deadline?.at, 100 * Self.second, "and rotation restarted its 60 s interval")
    }
}
