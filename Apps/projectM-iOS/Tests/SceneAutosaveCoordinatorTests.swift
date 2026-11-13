// SceneAutosaveCoordinatorTests.swift — SCN-002-T08, T11: debounced commits on a fake clock, commit
// triggers, restore is not an edit, failed writes are retried (SCN-002-R2 to R4, R7, R10; S4). The
// timer is off (`schedulesTimer: false`); `tick()` and `drain()` drive time and the write queue.
import Foundation
import ParameterGraph
import SceneFormat
import VisualParameters
import XCTest
@testable import projectM_iOS

@MainActor
final class SceneAutosaveCoordinatorTests: XCTestCase {
    private typealias F = SceneAutosaveFixtures

    /// The fake clock and the app's inputs.
    private final class World {
        var now = 0.0
        var inputs = SceneAutosaveFixtures.inputs()
    }

    private func make(_ folder: URL, _ world: World) throws -> SceneAutosaveCoordinator {
        let coordinator = SceneAutosaveCoordinator(store: SceneAutosaveStore(directory: folder), registry: try F.registry(),
                                                   clock: { () -> Double in world.now }, schedulesTimer: false)
        coordinator.inputs = { () -> SceneInputs in world.inputs }
        return coordinator
    }

    private func committedBars(_ folder: URL) throws -> String? {
        F.bars(SceneAutosaveStore(directory: folder).load(registry: try F.registry(), assets: nil).document)
    }

    /// S4: ten edits 0.1 s apart → one commit, 1 s after the last edit, of the last state.
    func testBurstCommitsOnceAfterTheQuietPeriod() throws {
        let folder = F.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let world = World()
        let c = try make(folder, world)
        c.startTracking(observeLifecycle: false)
        for (i, bars) in [16, 32, 64, 128, 16, 32, 64, 128, 16, 32].enumerated() {
            world.now = Double(i) * 0.1
            world.inputs.bars = bars
            c.inputsChanged()
            c.tick()
        }
        XCTAssertEqual(c.editRevision, 10)
        world.now = 1.85
        c.tick()
        c.drain()
        XCTAssertEqual(c.committedRevision, 0, "not before the quiet period")
        XCTAssertFalse(FileManager.default.fileExists(atPath: c.store.main.path))
        world.now = 1.9
        c.tick()
        c.drain()
        XCTAssertEqual(c.committedRevision, 10)
        XCTAssertFalse(c.isPending)
        XCTAssertEqual(try committedBars(folder), "32")
    }

    /// S4: continuous edits still commit at the maximum latency.
    func testContinuousEditsCommitAtTheMaximumLatency() throws {
        let folder = F.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let world = World()
        let c = try make(folder, world)
        c.startTracking(observeLifecycle: false)
        for i in 0..<10 {
            world.now = Double(i) * 0.5
            world.inputs.glowIntensity = Double(i) / 10
            c.inputsChanged()
            c.tick()
        }
        c.drain()
        XCTAssertEqual(c.committedRevision, 0, "nothing before 5 s")
        world.now = 5
        c.tick()
        c.drain()
        XCTAssertEqual(c.committedRevision, 10)
    }

    /// A4: a visual change and Settings closing (`commitNow`) commit at once; nothing pending, no write.
    func testTriggersCommitAtOnce() throws {
        let folder = F.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let world = World()
        let c = try make(folder, world)
        c.startTracking(observeLifecycle: false)
        c.commitNow()
        c.drain()
        XCTAssertFalse(FileManager.default.fileExists(atPath: c.store.main.path), "nothing pending: no write")

        world.inputs.visual = .text
        c.inputsChanged()
        c.drain()
        XCTAssertEqual(c.committedRevision, 1, "a visual change commits at once")

        world.inputs.bars = 16
        c.commitNow()   // Settings closed before the observation callback ran: caught up and committed
        c.drain()
        XCTAssertEqual(c.committedRevision, 2)
        XCTAssertEqual(try committedBars(folder), "16")

        world.inputs.bars = 128
        c.flushSynchronously()   // terminate
        XCTAssertEqual(c.committedRevision, 3)
        XCTAssertEqual(try committedBars(folder), "128")
    }

    /// R10: a restore is not an edit; the restored scene is the committed one.
    func testRestoreIsNotAnEdit() throws {
        let folder = F.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let world = World()
        world.inputs.bars = 16
        let first = try make(folder, world)
        first.startTracking(observeLifecycle: false)
        world.inputs.visual = .linearSpectrum
        first.inputsChanged()
        first.drain()

        world.inputs = F.inputs()   // the settings differ (an uncommitted edit, for example)
        let second = try make(folder, world)
        let values = try XCTUnwrap(second.restore(assets: nil))
        XCTAssertEqual(values.parameters[VisualParameterIDs.circularSpectrumBarCount], .enumeration("16"))
        world.inputs.bars = 16   // the app applied it
        second.startTracking(observeLifecycle: false)
        XCTAssertEqual(second.editRevision, 0)
        XCTAssertEqual(second.probe, "restored=main committed=0 pending=0 events=0")
    }

    /// A failed write keeps the previous scene, records an event and is retried by the next trigger.
    func testFailedWriteIsRetried() throws {
        let folder = F.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let world = World()
        let c = try make(folder, world)
        c.startTracking(observeLifecycle: false)
        world.inputs.bars = 16
        c.commitNow()
        c.drain()
        c.store.fault = { (step: SceneAutosaveStep) throws -> Void in
            if step == .replaceMain { throw CocoaError(.fileWriteOutOfSpace) }
        }
        world.inputs.bars = 32
        c.commitNow()
        c.drain()
        XCTAssertEqual(c.events, [.writeFailed("replaceMain")])
        XCTAssertTrue(c.isPending)
        XCTAssertEqual(try committedBars(folder), "16", "the previous scene stays")
        c.store.fault = nil
        c.commitNow()
        c.drain()
        XCTAssertFalse(c.isPending)
        XCTAssertEqual(try committedBars(folder), "32")
    }
}
