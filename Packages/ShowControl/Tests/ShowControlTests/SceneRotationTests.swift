// SceneRotationTests.swift — SHOW-013-T03: the seeded plan (roadmap acceptance: "Seeded rotation excludes disabled scenes
// and avoids immediate repeats"), the collection, the schedule and the stored settings (SHOW-013-S1, S2; contract C1, C2).
import Foundation
import XCTest
@testable import ShowControl

final class SceneRotationTests: XCTestCase {
    private let scenes: [String] = ["s1", "s2", "s3", "s4", "s5"]

    /// Each pick starting from the previous one, `steps` times.
    private func run(_ plan: SceneRotationPlan, seed: UInt64, steps: Int, start: String? = nil) -> [String] {
        var current: String? = start
        var picks: [String] = []
        picks.reserveCapacity(steps)
        for step in 0..<steps {
            guard case let .scene(id) = plan.pick(current: current, seed: seed, step: Int64(step)) else {
                XCTFail("step \(step) picked nothing")
                return picks
            }
            picks.append(id)
            current = id
        }
        return picks
    }

    func testSeededRotationExcludesDisabledScenesAndAvoidsImmediateRepeats() {
        let plan = SceneRotationPlan(collection: scenes, disabled: ["s2", "s4"])
        let picks: [String] = run(plan, seed: 0xC0FFEE, steps: 1000, start: "s1")
        XCTAssertEqual(picks.count, 1000)
        XCTAssertEqual(picks.filter { (id: String) -> Bool in id == "s2" || id == "s4" }.count, 0, "disabled scenes never appear")
        var previous: String = "s1"
        var repeats: Int = 0
        for id in picks {
            if id == previous { repeats += 1 }
            previous = id
        }
        XCTAssertEqual(repeats, 0, "no immediate repeat")
        XCTAssertEqual(Set(picks), ["s1", "s3", "s5"], "every enabled scene is reached")
        XCTAssertEqual(run(plan, seed: 0xC0FFEE, steps: 1000, start: "s1"), picks, "the same seed gives the same sequence")
        XCTAssertNotEqual(run(plan, seed: 7, steps: 1000, start: "s1"), picks, "another seed gives another sequence")
    }

    func testPicksAreRoughlyUniformOverTheOtherScenes() {
        let plan = SceneRotationPlan(collection: scenes, disabled: [])
        var counts: [String: Int] = [:]
        for step in 0..<2000 {
            if case let .scene(id) = plan.pick(current: "s1", seed: 42, step: Int64(step)) { counts[id, default: 0] += 1 }
        }
        XCTAssertNil(counts["s1"], "never the current scene")
        for id in ["s2", "s3", "s4", "s5"] {
            XCTAssertGreaterThan(counts[id] ?? 0, 400, "\(id) drawn about a quarter of the time: \(counts)")
        }
    }

    func testOneOrZeroEnabledScenesNeverSwitch() {
        let one = SceneRotationPlan(collection: scenes, disabled: ["s1", "s2", "s3", "s4"])
        XCTAssertEqual(one.pick(current: "s5", seed: 1, step: 0), .idle(.oneScene))
        XCTAssertEqual(one.pick(current: "other", seed: 1, step: 3), .idle(.oneScene))
        let none = SceneRotationPlan(collection: scenes, disabled: Set(scenes))
        XCTAssertEqual(none.pick(current: "s1", seed: 1, step: 0), .idle(.noScenes))
        XCTAssertEqual(SceneRotationPlan(collection: [], disabled: []).pick(current: nil, seed: 1, step: 0), .idle(.noScenes))
    }

    func testACurrentSceneOutsideTheCollectionLetsEveryEnabledSceneBePicked() {
        let plan = SceneRotationPlan(collection: ["a", "b"], disabled: [])
        var seen: Set<String> = []
        for step in 0..<64 {
            if case let .scene(id) = plan.pick(current: "outside", seed: 9, step: Int64(step)) { seen.insert(id) }
        }
        XCTAssertEqual(seen, ["a", "b"])
        XCTAssertEqual(plan.pick(current: "a", seed: 9, step: 5), .scene("b"), "two scenes alternate")
    }

    func testTheCollectionIsAFolderWithItsSubfolders() throws {
        let ids: [String] = (1...5).map { (n: Int) -> String in "5CE7E000-0000-4000-8000-00000000000\(n)" }
        var list = ShowCueList(id: UUID(), name: "Show")
        for (index, id) in ids.enumerated() { _ = try list.append(sceneID: id, label: "Cue \(index + 1)") }
        _ = try list.append(sceneID: ids[0], label: "again")   // a scene used twice counts once
        let setA = UUID(uuidString: "F0000000-0000-4000-8000-000000000001")!
        let encore = UUID(uuidString: "F0000000-0000-4000-8000-000000000002")!
        try list.createFolder(named: "Set A", in: nil, id: setA)
        try list.createFolder(named: "Encore", in: setA, id: encore)
        try list.moveScene(ids[1], to: setA)
        try list.moveScene(ids[3], to: encore)
        XCTAssertEqual(SceneRotationPlan.collection(of: list, folder: nil), ids)
        XCTAssertEqual(SceneRotationPlan.collection(of: list, folder: setA), [ids[1], ids[3]])
        XCTAssertEqual(SceneRotationPlan.collection(of: list, folder: encore), [ids[3]])
        XCTAssertEqual(SceneRotationPlan.collection(of: list, folder: UUID()), ids, "an unknown folder counts as all scenes")
        let plan = SceneRotationPlan(list: list, folder: setA, disabled: [])
        XCTAssertEqual(Set(run(plan, seed: 3, steps: 50)), [ids[1], ids[3]])
    }

    // MARK: Schedule (C2)

    private let second: UInt64 = 1_000_000_000

    /// 120 BPM bars (2 s) anchored at 0: the first bar line strictly after t.
    private func bars120(_ t: UInt64) -> UInt64? { (t / (2 * second) + 1) * 2 * second }

    func testTimerDeadlineIsTheIntervalAfterTheArmTime() {
        let settings = SceneRotationSettings(mode: .timer, intervalSeconds: 30)
        let deadline = SceneRotationSchedule.deadline(after: 5 * second, settings: settings, reduceFlashing: false,
                                                      barLine: { (_: UInt64) -> UInt64? in nil })
        XCTAssertEqual(deadline, SceneRotationSchedule.Deadline(at: 35 * second, onBeat: false))
    }

    func testBarsDeadlineIsTheNthBarLineAfterTheArmTime() {
        let settings = SceneRotationSettings(mode: .bars, bars: 8)
        let deadline = SceneRotationSchedule.deadline(after: 3 * second, settings: settings, reduceFlashing: false,
                                                      barLine: bars120)
        XCTAssertEqual(deadline, SceneRotationSchedule.Deadline(at: 18 * second, onBeat: true), "bar lines 4, 6 … 18 s")
        let onLine = SceneRotationSchedule.deadline(after: 4 * second, settings: settings, reduceFlashing: false, barLine: bars120)
        XCTAssertEqual(onLine.at, 20 * second, "strictly after: armed on a bar line counts 8 more")
    }

    func testBarsWithoutTempoFallBackToTheTimer() {
        let settings = SceneRotationSettings(mode: .bars, intervalSeconds: 45, bars: 8)
        let deadline = SceneRotationSchedule.deadline(after: 0, settings: settings, reduceFlashing: false,
                                                      barLine: { (_: UInt64) -> UInt64? in nil })
        XCTAssertEqual(deadline, SceneRotationSchedule.Deadline(at: 45 * second, onBeat: false))
    }

    func testBarsKeepAMinimumGapAndALongerOneWithReduceFlashing() {
        let settings = SceneRotationSettings(mode: .bars, bars: 1)
        let half: UInt64 = second / 2
        let fast: (UInt64) -> UInt64? = { (t: UInt64) -> UInt64? in (t / half + 1) * half }   // 480 BPM bars
        let normal = SceneRotationSchedule.deadline(after: 0, settings: settings, reduceFlashing: false, barLine: fast)
        XCTAssertEqual(normal, SceneRotationSchedule.Deadline(at: 4 * second, onBeat: true))
        let reduced = SceneRotationSchedule.deadline(after: 0, settings: settings, reduceFlashing: true, barLine: fast)
        XCTAssertEqual(reduced, SceneRotationSchedule.Deadline(at: 15 * second, onBeat: true))
    }

    // MARK: Settings (R8)

    func testSettingsDecodeDefaultsAndClampValues() throws {
        let decoder = JSONDecoder()
        let empty = try decoder.decode(SceneRotationSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(empty, SceneRotationSettings())
        XCTAssertEqual(empty.mode, .timer)
        XCTAssertEqual(empty.intervalSeconds, 60)
        XCTAssertEqual(empty.bars, 8)
        let odd = try decoder.decode(SceneRotationSettings.self,
                                     from: Data(#"{"mode":"spin","intervalSeconds":2,"bars":900,"folderID":"x","disabledSceneIDs":["b","a","b"]}"#.utf8))
        XCTAssertEqual(odd.mode, .timer)
        XCTAssertEqual(odd.intervalSeconds, 15)
        XCTAssertEqual(odd.bars, 64)
        XCTAssertNil(odd.folderID)
        XCTAssertEqual(odd.disabledSceneIDs, ["a", "b"])
        var settings = SceneRotationSettings(mode: .bars, intervalSeconds: 30, bars: 4, folderID: UUID())
        settings.setEnabled(false, sceneID: "s2")
        settings.setEnabled(false, sceneID: "gone")
        XCTAssertFalse(settings.isEnabled("s2"))
        settings.prune(keepingScenes: ["s1", "s2"])
        XCTAssertEqual(settings.disabledSceneIDs, ["s2"])
        settings.intervalSeconds = 9999
        XCTAssertEqual(settings.intervalSeconds, 600)
        let round = try decoder.decode(SceneRotationSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(round, settings)
    }
}
