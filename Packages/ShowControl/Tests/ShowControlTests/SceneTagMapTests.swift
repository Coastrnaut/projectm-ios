// SceneTagMapTests.swift — SCN-005-T05: the tag rules (spec SCN-005-R2 to R4; research SCN-005-D2,
// D3; contract T3): trimming, folding and deduplication, the adopted spelling, the limits, removal,
// the derived vocabulary and AND matching.
import Foundation
import ShowControl
import XCTest

final class SceneTagMapTests: XCTestCase {
    private func refuses(_ expected: SceneTagError, _ body: () throws(SceneTagError) -> Void,
                         file: StaticString = #filePath, line: UInt = #line) {
        do throws(SceneTagError) {
            try body()
            XCTFail("not refused", file: file, line: line)
        } catch {
            XCTAssertEqual(error, expected, file: file, line: line)
        }
    }

    func testTagsAreTrimmedAndValidated() {
        XCTAssertEqual(SceneTagMap.normalizedTag("  Intro \n"), "Intro")
        XCTAssertNil(SceneTagMap.normalizedTag("   "))
        XCTAssertNil(SceneTagMap.normalizedTag("two\nlines"))
        XCTAssertNil(SceneTagMap.normalizedTag("tab\u{7}bell"))
        XCTAssertEqual(SceneTagMap.normalizedTag(String(repeating: "x", count: 40))?.count, 40)
        XCTAssertNil(SceneTagMap.normalizedTag(String(repeating: "x", count: 41)), "41 characters is too long")
    }

    func testFoldedDuplicatesAreRefusedAndTheShowSpellingIsAdopted() throws {
        var map = SceneTagMap()
        XCTAssertEqual(try map.add(" Intro ", to: "s1"), "Intro")
        refuses(.alreadyTagged("Intro")) { () throws(SceneTagError) in try map.add("  INTRO ", to: "s1") }
        refuses(.alreadyTagged("Intro")) { () throws(SceneTagError) in try map.add("ìntro", to: "s1") }   // accents fold
        XCTAssertEqual(try map.add("intro", to: "s2"), "Intro", "another scene adopts the show's spelling")
        XCTAssertEqual(try map.add("ＬＯＵＤ", to: "s2"), "ＬＯＵＤ")
        XCTAssertEqual(try map.add("loud", to: "s1"), "ＬＯＵＤ", "width folds")
        XCTAssertEqual(map.tags(ofScene: "s1"), ["Intro", "ＬＯＵＤ"])
        XCTAssertEqual(map.vocabulary, ["Intro", "ＬＯＵＤ"])
        XCTAssertEqual(map.count(of: "INTRO"), 2)
    }

    func testEachScenesTagsAreSortedByFoldedText() throws {
        var map = SceneTagMap()
        for tag in ["zeta", "Alpha", "beta"] { try map.add(tag, to: "s") }
        XCTAssertEqual(map.tags(ofScene: "s"), ["Alpha", "beta", "zeta"])
    }

    func testLimitsRefuseWithoutChange() throws {
        var map = SceneTagMap()
        for n in 1...16 { try map.add("t\(n)", to: "s") }
        let before = map
        refuses(.tooManyTags(limit: 16)) { () throws(SceneTagError) in try map.add("t17", to: "s") }
        refuses(.invalidTag) { () throws(SceneTagError) in try map.add(String(repeating: "y", count: 41), to: "s") }
        XCTAssertEqual(map, before, "refusals change nothing")

        var wide = SceneTagMap()
        for n in 0..<256 { try wide.add("d\(n)", to: "scene\(n / 16)") }
        XCTAssertEqual(wide.vocabulary.count, 256)
        refuses(.tooManyDistinctTags(limit: 256)) { () throws(SceneTagError) in try wide.add("new", to: "other") }
        XCTAssertEqual(try wide.add("D0", to: "other"), "d0", "an existing tag is still allowed at the limit")
    }

    func testRemoveCopyPruneAndAndMatching() throws {
        var map = SceneTagMap()
        try map.add("Intro", to: "s1")
        try map.add("Loud", to: "s1")
        try map.add("Intro", to: "s2")
        XCTAssertTrue(map.matches(sceneID: "s1", all: ["intro", "LOUD"]))
        XCTAssertFalse(map.matches(sceneID: "s2", all: ["intro", "LOUD"]), "AND: every selected tag")
        XCTAssertTrue(map.matches(sceneID: "s3", all: []), "no selection matches every scene")
        XCTAssertEqual(try map.remove("loud", from: "s1"), "Loud")
        refuses(.notTagged("Loud")) { () throws(SceneTagError) in try map.remove("Loud", from: "s1") }
        XCTAssertEqual(map.vocabulary, ["Intro"], "an unused tag leaves the vocabulary")
        map.copyTags(from: "s1", to: "s9")
        XCTAssertEqual(map.tags(ofScene: "s9"), ["Intro"])
        try map.remove("Intro", from: "s2")
        XCTAssertNil(map.tags["s2"], "no empty lists are kept")
        XCTAssertEqual(map.prune(keepingScenes: ["s1"]), 1)
        XCTAssertEqual(Set(map.tags.keys), ["s1"])
    }
}
