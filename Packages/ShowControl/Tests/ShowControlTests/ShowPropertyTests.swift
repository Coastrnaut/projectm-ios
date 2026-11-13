// ShowPropertyTests.swift — SHOW-001-S3: a fixed-seed sequence of 1,000 random edits and steps keeps
// the show valid at every step, and replaying it gives the same show and the same step results.
import Foundation
import ShowControl
import XCTest

/// SplitMix64: a small, fully specified generator, so the sequence is the same on every platform.
struct SplitMix64 {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func below(_ bound: Int) -> Int { Int(next() % UInt64(bound)) }
}

final class ShowPropertyTests: XCTestCase {
    static let seed: UInt64 = 0x5_0001
    static let operations = 1_000

    private func check(_ list: ShowCueList, step: Int) {
        XCTAssertLessThanOrEqual(list.cues.count, ShowCueList.maximumCues, "step \(step)")
        XCTAssertEqual(Set(list.cues.map(\.id)).count, list.cues.count, "duplicate cue ID at step \(step)")
        if case let .cue(id) = list.position {
            XCTAssertTrue(list.cues.contains { (c: ShowCue) -> Bool in c.id == id }, "position names no cue at step \(step)")
        }
        for cue in list.cues {
            XCTAssertTrue(ShowCueList.isSceneID(cue.sceneID), "step \(step)")
            XCTAssertEqual(ShowCueList.normalizedLabel(cue.label), cue.label, "step \(step)")
        }
    }

    /// Runs the seeded sequence; returns the final show and every operation's observable result.
    private func runSequence() -> (list: ShowCueList, trace: [String]) {
        var rng = SplitMix64(state: Self.seed)
        var list = ShowCueList(id: ShowFixtures.uuid(0))
        var trace: [String] = []
        var nextCue = 1
        for step in 0..<Self.operations {
            let pick = rng.below(9)
            var result: String
            switch pick {
            case 0, 1:
                let scene = ShowFixtures.sceneID(rng.below(12))
                do {
                    try list.append(sceneID: scene, label: "Cue \(nextCue)", cueID: ShowFixtures.uuid(nextCue))
                    result = "append \(nextCue)"
                } catch {
                    result = "append refused \(error)"
                }
                nextCue += 1
            case 2:
                result = "next \(list.next().outcome.rawValue)"
            case 3:
                result = "previous \(list.previous().outcome.rawValue)"
            case 4:
                let target = list.cues.isEmpty ? ShowFixtures.uuid(0) : list.cues[rng.below(list.cues.count)].id
                result = "go \(list.go(to: target).outcome.rawValue)"
            case 5:
                if list.cues.isEmpty { result = "remove none"; break }
                let target = list.cues[rng.below(list.cues.count)].id
                result = "remove \((try? list.remove(target))?.id.uuidString ?? "refused")"
            case 6:
                if list.cues.isEmpty { result = "move none"; break }
                let from = rng.below(list.cues.count)
                let to = rng.below(list.cues.count + 1)
                result = "move \(from)->\(to) \((try? list.move(fromOffsets: IndexSet(integer: from), toOffset: to)) != nil)"
            case 7:
                if list.cues.isEmpty { result = "rename none"; break }
                let target = list.cues[rng.below(list.cues.count)].id
                result = "rename \((try? list.rename(target, to: "Renamed \(step)")) != nil)"
            default:
                // Save and load in the middle of the sequence: nothing observable changes.
                let reloaded = try? ShowCueList.decode(list.encoded()).list
                XCTAssertEqual(reloaded, list, "round trip at step \(step)")
                result = "roundtrip"
            }
            check(list, step: step)
            trace.append(result + " @" + list.positionText)
        }
        return (list, trace)
    }

    func testSeededSequenceKeepsTheShowValidAndReplaysIdentically() {
        let first = runSequence()
        let second = runSequence()
        XCTAssertEqual(first.trace, second.trace)
        XCTAssertEqual(first.list, second.list)
        XCTAssertEqual(first.list.encoded(), second.list.encoded())
        XCTAssertFalse(first.list.cues.isEmpty, "the sequence exercises a non-empty show")
        XCTAssertGreaterThan(first.trace.filter { (t: String) -> Bool in t.hasPrefix("next moved") }.count, 10)
    }
}
