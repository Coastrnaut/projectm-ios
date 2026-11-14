// ShowAutoAdvanceCoordinatorTests.swift — SHOW-002-T11: the timed advance in the app with a manual clock (contract
// show-cue-dwell.md D4): one `show.next()` per due cue (its scene applied), manual steps reset the deadline, holds
// keep the remaining time, a dwell edit on the active cue restarts it, a locked scene refuses dwell edits but keeps
// advancing, Duplicate keeps the dwell, the countdown text. `tick()` is called by the test; no task runs and nothing
// waits on the wall clock.
import Foundation
import ParameterGraph
import SceneFormat
import ShowControl
import ShowStorage
import TextLayer
import VisualGenerators
import XCTest
@testable import projectM_iOS

@MainActor
final class ShowAutoAdvanceCoordinatorTests: XCTestCase {
    private struct Rig {
        let show: ShowCoordinator
        let driver: ShowAutoAdvanceCoordinator
        let clock: ShowManualClock
        let applied: () -> [String]
        let ids: [String]
    }

    /// Three cues (dwells 10, 20 and 30 s) over a temporary store; the driver never starts its own task.
    private func rig(held: @escaping () -> Bool = { () -> Bool in false }) throws -> Rig {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ShowAutoAdvance-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let show = ShowCoordinator(store: ShowStore(directory: url), registry: try SceneArchiveService.appRegistry())
        var applied: [String] = []
        show.applyScene = { (document: SceneDocument, _: [SceneIssue]) -> [String] in
            applied.append(document.id)
            return []
        }
        show.announce = { (_: String) in }
        var ids: [String] = []
        for visual in [VisualChoice.circularSpectrum, .linearSpectrum, .text] {
            let look = ShowLook(visual: visual, bars: 64, orientation: .horizontal, spacing: 0.5, glowEnabled: false, glowIntensity: 0.7,
                                glowRadius: 0.03, glowThreshold: 0.4, text: TextOverlaySpec(message: "Hi"), photoID: nil, videoID: nil)
            let document = ShowSceneSnapshot.document(look, id: UUID().uuidString, name: visual.title)
            ids.append(document.id)
            XCTAssertTrue(show.addScene(document, label: visual.title))
        }
        let clock = ShowManualClock()
        let driver = ShowAutoAdvanceCoordinator(show: show, clock: clock, runsLoop: false)
        driver.isHeld = held
        for (n, cue) in show.list.cues.enumerated() { XCTAssertTrue(show.setDwell(cue.id, to: try ShowCueDwell(seconds: (n + 1) * 10))) }
        return Rig(show: show, driver: driver, clock: clock, applied: { applied }, ids: ids)
    }

    /// Ticks once a second up to `end`; returns the times (whole seconds) at which the show moved.
    private func run(_ rig: Rig, until end: Int) -> [Int] {
        var moved: [Int] = []
        var index = rig.show.list.activeIndex
        while rig.clock.now() < .seconds(end) {
            rig.clock.advance(by: .seconds(1))
            rig.driver.tick()
            if rig.show.list.activeIndex != index {
                index = rig.show.list.activeIndex
                moved.append(Int(rig.clock.now().components.seconds))
            }
        }
        return moved
    }

    func testOneAdvancePerDueCueThroughTheShowsNext() throws {
        let rig = try rig()
        XCTAssertNil(rig.driver.countdown, "Standby never counts down")
        rig.show.next()
        XCTAssertEqual(rig.driver.countdown, .init(seconds: 10, held: false))
        XCTAssertEqual(rig.driver.countdownText, "Next in 0:10")
        XCTAssertEqual(rig.driver.spokenCountdown, "next cue in 10 seconds")
        XCTAssertEqual(run(rig, until: 200), [10, 30], "cue 1 → 2 at 10 s, 2 → 3 at 30 s; the last cue stays")
        XCTAssertEqual(rig.applied(), rig.ids, "each advance applied its cue's scene once")
        XCTAssertNil(rig.driver.countdown)
    }

    func testAManualStepResetsTheDeadline() throws {
        let rig = try rig()
        rig.show.next()
        rig.clock.set(.seconds(4))
        rig.show.next()
        XCTAssertEqual(rig.driver.countdown?.seconds, 20)
        XCTAssertEqual(run(rig, until: 40), [24], "10 s never fires; cue 2 ends at 4 + 20 s")
    }

    func testPauseAndBlackoutHoldTheRemainingTime() throws {
        var held = false
        let rig = try rig(held: { () -> Bool in held })
        rig.show.next()
        rig.clock.set(.seconds(6))
        held = true
        rig.driver.tick()
        XCTAssertEqual(rig.driver.countdownText, "Next in 0:04, held")
        XCTAssertEqual(rig.driver.spokenCountdown, "countdown held, 4 seconds left")
        XCTAssertEqual(run(rig, until: 100), [], "nothing advances while held")
        held = false
        rig.driver.tick()   // the hold is re-read on each tick (every 250 ms in the app)
        XCTAssertEqual(rig.driver.countdownText, "Next in 0:04")
        XCTAssertEqual(run(rig, until: 110), [104], "4 s after the hold ends")
    }

    func testADwellEditRestartsTheActiveCueAndTheLockRefusesIt() throws {
        let rig = try rig()
        let suite = "ShowAutoAdvance-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        rig.show.next()
        rig.clock.set(.seconds(8))
        let first = rig.show.list.cues[0].id
        XCTAssertTrue(rig.show.setDwell(first, to: try ShowCueDwell(seconds: 5)))
        XCTAssertEqual(rig.driver.countdown?.seconds, 5, "restarts from the edit")
        XCTAssertTrue(rig.show.setDwell(first, to: nil))
        XCTAssertNil(rig.driver.countdown, "Off cancels")
        XCTAssertTrue(rig.show.setDwell(first, to: try ShowCueDwell(seconds: 5)))

        let lock = SceneLock(defaults: defaults)
        rig.show.sceneLock = lock
        lock.lock()
        XCTAssertFalse(rig.show.setDwell(first, to: try ShowCueDwell(seconds: 60)), "an edit while locked is refused")
        XCTAssertEqual(rig.show.list.cues[0].dwell?.seconds, 5)
        XCTAssertEqual(rig.show.editorMessage, SceneLock.refusalMessage)
        XCTAssertEqual(run(rig, until: 14), [13], "timed advances continue while locked (navigation)")
        lock.unlock()
        XCTAssertNotNil(rig.show.duplicateScene(of: rig.show.list.cues[1].id))
        XCTAssertEqual(rig.show.list.cues[2].dwell?.seconds, 20, "Duplicate keeps the dwell")
    }

    func testRemovingTheActiveCueCancelsItsCountdown() throws {
        let rig = try rig()
        rig.show.go(to: rig.show.list.cues[1].id)
        XCTAssertNotNil(rig.driver.countdown)
        rig.show.remove(rig.show.list.cues[1].id)
        XCTAssertNil(rig.driver.countdown)
        XCTAssertEqual(run(rig, until: 100), [])
    }
}
