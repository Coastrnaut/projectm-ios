// PRE-003-T06: the tag rules (spec PRE-003-R2, R4, R7; research PRE-003-D2, D4). Mirrors SCN-005's
// SceneTagMapTests: trimming, folding and dedup, adopted spelling, limits, removal, repair.
import XCTest
@testable import PresetLibrary

final class PresetTagMapTests: XCTestCase {
    func testTrimmingFoldingAndAdoptedSpelling() throws {
        var map = PresetTagMap()
        XCTAssertEqual(try map.add("  Calm ", to: "a"), "Calm")
        // Case, accents and width fold to the same tag: refused on the same preset…
        for variant in ["CALM", "cälm", "ＣＡＬＭ"] {
            XCTAssertThrowsError(try map.add(variant, to: "a")) { XCTAssertEqual($0 as? PresetTagError, .alreadyTagged("Calm")) }
        }
        // …and adopted in its existing spelling on another preset.
        XCTAssertEqual(try map.add("cälm", to: "b"), "Calm")
        XCTAssertEqual(map.tags(of: "b"), ["Calm"])
        XCTAssertTrue(map.has("b", tag: "CALM"))
        // Each preset's tags are sorted by folded text.
        try map.add("slow", to: "a")
        try map.add("Ambient", to: "a")
        XCTAssertEqual(map.tags(of: "a"), ["Ambient", "Calm", "slow"])
        XCTAssertEqual(PresetTagMap.fold("Ｃａｌｍ É"), PresetTagMap.fold("calm e"))
    }

    func testInvalidTagsAreRefusedWithoutChange() {
        var map = PresetTagMap()
        for bad in ["", "   ", String(repeating: "x", count: 41), "two\nlines", "tab\u{7}bell"] {
            XCTAssertThrowsError(try map.add(bad, to: "a")) { XCTAssertEqual($0 as? PresetTagError, .invalidTag) }
        }
        XCTAssertThrowsError(try map.add("Calm", to: "")) { XCTAssertEqual($0 as? PresetTagError, .invalidTag) }
        XCTAssertNoThrow(try map.add(String(repeating: "x", count: 40), to: "a"))
        XCTAssertEqual(map.tags.count, 1)
    }

    func testLimitsRefuseWithoutChange() throws {
        var map = PresetTagMap()
        for i in 0..<PresetTagMap.maximumTagsPerPreset { try map.add("t\(i)", to: "a") }
        let before = map
        XCTAssertThrowsError(try map.add("one more", to: "a")) { XCTAssertEqual($0 as? PresetTagError, .tooManyTags(limit: 16)) }
        XCTAssertEqual(map, before)

        var wide = PresetTagMap()
        for i in 0..<PresetTagMap.maximumDistinctTags { try wide.add("tag \(i)", to: "p\(i / 16)") }
        XCTAssertThrowsError(try wide.add("new", to: "z")) { XCTAssertEqual($0 as? PresetTagError, .tooManyDistinctTags(limit: 256)) }
        XCTAssertNoThrow(try wide.add("tag 0", to: "z"))   // an existing tag is still fine
    }

    func testTaggedPresetCap() throws {
        var stored: [String: [String]?] = [:]
        for i in 0..<PresetTagMap.maximumTaggedPresets { stored["p\(i)"] = ["Calm"] }
        var map = PresetTagMap.repaired(stored).map
        XCTAssertEqual(map.tags.count, 20_000)
        XCTAssertThrowsError(try map.add("Calm", to: "new")) { XCTAssertEqual($0 as? PresetTagError, .tooManyTaggedPresets(limit: 20_000)) }
        XCTAssertNoThrow(try map.add("Slow", to: "p0"))   // a preset that has tags can take more
    }

    func testRemoveAndPrune() throws {
        var map = PresetTagMap()
        try map.add("Calm", to: "a")
        try map.add("Slow", to: "a")
        XCTAssertEqual(try map.remove("calm", from: "a"), "Calm")
        XCTAssertThrowsError(try map.remove("Calm", from: "a")) { XCTAssertEqual($0 as? PresetTagError, .notTagged("Calm")) }
        XCTAssertTrue(map.prune("a"))
        XCTAssertFalse(map.prune("a"))
        XCTAssertTrue(map.isEmpty)
    }

    func testRepairDropsAndCountsEveryBrokenEntry() {
        let stored: [String: [String]?] = [
            "a": ["Calm", "calm", " Padded ", "", String(repeating: "x", count: 41), "Slow"],   // dup, padded, empty, long
            "b": nil,                                                                             // not a list
            "": ["Calm"],                                                                         // empty ID
            "c": [],                                                                              // empty list
            "d": (0..<17).map { "t\($0)" },                                                       // a 17th tag
        ]
        let (map, dropped) = PresetTagMap.repaired(stored)
        XCTAssertEqual(map.tags(of: "a"), ["Calm", "Slow"])
        XCTAssertEqual(map.tags(of: "d").count, 16)
        XCTAssertNil(map.tags["b"])
        XCTAssertEqual(dropped, 4 + 1 + 1 + 1 + 1)
        XCTAssertEqual(PresetTagMap.repaired(stored).map, map, "deterministic")
    }
}
