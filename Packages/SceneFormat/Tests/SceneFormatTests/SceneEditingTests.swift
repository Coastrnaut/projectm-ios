// SceneEditingTests.swift — SCN-003-T03: duplicate and rename at the document level (SCN-003-S1 to
// S4; contract D1). "Kept exactly" = the copy's canonical bytes with the original's id and name put
// back equal the original's (research SCN-003-D2).
import ParameterGraph
@testable import SceneFormat
import XCTest

final class SceneEditingTests: XCTestCase {
    static let copyID = "0C0C0C0C-0000-4000-8000-000000000003"

    /// The bytes of `d` with its id and name replaced (to compare everything else).
    private func bytes(_ d: SceneDocument, id: String, name: String) -> [UInt8] {
        var copy = d
        copy.id = id
        copy.name = name
        return copy.encoded()
    }

    // MARK: S4 — the name rule

    func testNameTable() {
        let max = String(repeating: "a", count: SceneLimits.maximumNameLength)
        let flags = String(repeating: "🇳🇴", count: SceneLimits.maximumNameLength)   // 120 graphemes, 240 scalars
        let table: [(text: String, expected: String?)] = [
            ("Build B", "Build B"),
            ("  Build B \n", "Build B"),
            ("Ü", "Ü"),
            (max, max),
            (flags, flags),
            ("  " + max + "  ", max),
            ("", nil),
            ("   ", nil),
            ("\n\t", nil),
            (max + "a", nil),
            ("Build\nB", nil),
            ("Build\tB", nil),
            ("Build\u{0}B", nil),
            ("Build\u{7F}B", nil),
        ]
        for (text, expected) in table {
            XCTAssertEqual(SceneDocument.normalizedName(text), expected, "\(text.debugDescription)")
            XCTAssertEqual(SceneDocument.isValidName(text.trimmingCharacters(in: .whitespacesAndNewlines)), expected != nil,
                           "\(text.debugDescription)")
        }
    }

    func testTheValidatorUsesTheSameRule() throws {
        let registry = try SceneFixtures.registry()
        for name in ["Ok", "Build\nB", "", String(repeating: "x", count: 121)] {
            let d = SceneDocument(id: SceneFixtures.sceneID, name: name)
            let flagged = d.validate(registry: registry).contains { (i: SceneIssue) -> Bool in i.code == .invalidName }
            XCTAssertEqual(flagged, !SceneDocument.isValidName(name), name.debugDescription)
        }
    }

    func testCopyNamesFitTheLimit() {
        XCTAssertEqual(SceneDocument.copyName("Build"), "Build copy")
        XCTAssertEqual(SceneDocument.copyName("  Build "), "Build copy")
        XCTAssertEqual(SceneDocument.copyName(""), "Scene copy")
        XCTAssertEqual(SceneDocument.copyName("a\nb"), "Scene copy")
        let long = SceneDocument.copyName(String(repeating: "w", count: 120))
        XCTAssertEqual(long.count, SceneLimits.maximumNameLength)
        XCTAssertTrue(long.hasSuffix(" copy"))
        let spaced = SceneDocument.copyName(String(repeating: "w", count: 114) + " " + String(repeating: "z", count: 5))
        XCTAssertEqual(spaced, String(repeating: "w", count: 114) + " copy", "re-trimmed after shortening")
        XCTAssertNotNil(SceneDocument.normalizedName(long))
    }

    // MARK: S1 — the row's acceptance at the scene level

    func testTheDuplicateLoadsIndependentlyWithADistinctIDAndAnEqualLiveState() throws {
        let original = try SceneFixtures.allKinds()
        let copy = try original.duplicated(newID: Self.copyID, name: SceneDocument.copyName(original.name))
        XCTAssertNotEqual(copy.id, original.id)
        XCTAssertEqual(copy.id, Self.copyID)
        XCTAssertEqual(copy.name, original.name + " copy")

        // Each decodes from its own bytes alone.
        let registry = try SceneFixtures.registry()
        let a = try SceneDocument.decode(original.encoded())
        let b = try SceneDocument.decode(copy.encoded())
        XCTAssertEqual(a.document.id, original.id)
        XCTAssertEqual(b.document.id, Self.copyID)
        let liveA = try a.document.liveState(registry: registry, assets: FakeAvailability())
        let liveB = try b.document.liveState(registry: registry, assets: FakeAvailability())
        XCTAssertEqual(liveA.state, liveB.state, "the same look")
        XCTAssertEqual(liveA.warnings, liveB.warnings)

        // Everything but id and name is kept exactly (layers, instance IDs, parameters, bindings,
        // modulation edges, asset store IDs, embedded text and graph, unknown content).
        XCTAssertEqual(bytes(copy, id: original.id, name: original.name), original.encoded())
        XCTAssertEqual(copy.assets, original.assets, "media shared by store ID, embedded documents copied")
        XCTAssertEqual(copy.modulation, original.modulation)
        XCTAssertEqual(copy.layers.map(\.instance), original.layers.map(\.instance))
    }

    // MARK: S2 — rename

    func testRenameKeepsTheIDAndEverythingElse() throws {
        let original = try SceneFixtures.allKinds()
        let renamed = try original.renamed(to: "  Build B ")
        XCTAssertEqual(renamed.id, original.id)
        XCTAssertEqual(renamed.name, "Build B")
        XCTAssertEqual(bytes(renamed, id: original.id, name: original.name), original.encoded())
        XCTAssertEqual(try SceneDocument.decode(renamed.encoded()).document, renamed)
    }

    func testRefusals() throws {
        let original = try SceneFixtures.allKinds()
        XCTAssertThrowsError(try original.renamed(to: " ")) { (e: Error) in XCTAssertEqual(e as? SceneEditError, .invalidName) }
        XCTAssertThrowsError(try original.duplicated(newID: original.id, name: "x")) { (e: Error) in
            XCTAssertEqual(e as? SceneEditError, .sameSceneID)
        }
        for bad in ["", "0c0c0c0c-0000-4000-8000-000000000003", "not-a-uuid", "../x"] {
            XCTAssertThrowsError(try original.duplicated(newID: bad, name: "x")) { (e: Error) in
                XCTAssertEqual(e as? SceneEditError, .invalidSceneID(bad))
            }
        }
        XCTAssertThrowsError(try original.duplicated(newID: Self.copyID, name: "a\u{0}")) { (e: Error) in
            XCTAssertEqual(e as? SceneEditError, .invalidName)
        }
    }

    // MARK: S3 — property test (fixed seed, ≤ 1 s)

    func testTwoHundredSeededRandomScenesKeepEverythingButIDAndName() throws {
        var generator = SceneGenerator(rng: SplitMix64(state: 0x5C3_0003))
        for n in 0..<200 {
            let original = generator.document()
            let newID = String(format: "%08X-0000-4000-8000-000000000001", n + 1)
            let name = "Scene \(n)"
            let copy = try original.duplicated(newID: newID, name: name)
            XCTAssertEqual(copy.id, newID, "scene \(n)")
            XCTAssertEqual(bytes(copy, id: original.id, name: original.name), original.encoded(), "scene \(n)")
            XCTAssertEqual(try SceneDocument.decode(copy.encoded()).document, copy, "scene \(n): the copy round-trips")
            let renamed = try original.renamed(to: name)
            XCTAssertEqual(renamed.id, original.id, "scene \(n)")
            XCTAssertEqual(bytes(renamed, id: original.id, name: original.name), original.encoded(), "scene \(n)")
        }
    }
}
