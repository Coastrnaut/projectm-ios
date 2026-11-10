// T209: scope storage values, stepping with wrap, random never repeating (SC-106).
import Foundation
import XCTest
@testable import PresetLibrary

final class PresetScopeTests: XCTestCase {
    func testStorageRoundTrip() {
        let scopes: [PresetScope] = [.included, .pack("cream-of-the-crop"), .folder("cream-of-the-crop", ["Fractal", "Nested Spiral"]),
                                     .favorites, .all]
        for scope in scopes {
            XCTAssertEqual(PresetScope(storageValue: scope.storageValue), scope, scope.storageValue)
        }
        XCTAssertEqual(PresetScope.search("geiss").storageValue, "all", "no search text is stored")
        XCTAssertNil(PresetScope(storageValue: "bogus"))
        XCTAssertEqual(PresetScope.folder("en-d", ["Episode 1"]).storageValue, "folder:en-d/Episode 1")
    }

    func testStepWrapsBothEnds() throws {
        let members = try Fixtures.library().members(of: .all, unlocked: true, favorites: [], excluded: [])
        XCTAssertEqual(ScopeStepper.step(members, from: members.last, by: 1), members.first)
        XCTAssertEqual(ScopeStepper.step(members, from: members.first, by: -1), members.last)
        XCTAssertEqual(ScopeStepper.step(members, from: nil, by: 1), members.first)
        XCTAssertEqual(ScopeStepper.step(members, from: nil, by: -1), members.last)
        XCTAssertNil(ScopeStepper.step([], from: nil, by: 1))
    }

    func testRandomNeverRepeatsOrLeavesTheScope() throws {
        let members = try Fixtures.library().members(of: .pack("cream-of-the-crop"), unlocked: true, favorites: [], excluded: [])
        var generator = SeededGenerator(seed: 42)
        var current = members[0]
        for _ in 0..<1_000 {
            let pick = try XCTUnwrap(ScopeStepper.random(members, excluding: current, using: &generator))
            XCTAssertNotEqual(pick, current)
            XCTAssertTrue(members.contains(pick))
            current = pick
        }
        XCTAssertEqual(ScopeStepper.random([members[0]], excluding: members[0], using: &generator), members[0])
        XCTAssertNil(ScopeStepper.random([], excluding: nil, using: &generator))
    }
}

struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}
