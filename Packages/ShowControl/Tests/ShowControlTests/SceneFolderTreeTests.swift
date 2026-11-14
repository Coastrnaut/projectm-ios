// SceneFolderTreeTests.swift — SCN-004-T05: the folder tree's rules (spec SCN-004-R1 to R5; contract
// F2, F3): create, rename, move folder (cycle, depth, name collision), move scene, delete with
// re-parenting and suffixes, and the limit. Every refusal changes nothing.
import Foundation
import ShowControl
import XCTest

final class SceneFolderTreeTests: XCTestCase {
    private static func fid(_ n: Int) -> UUID { UUID(uuidString: String(format: "F01DE000-0000-4000-8000-%012d", n))! }

    /// A (1) / B (2) / C (3) and a top-level D (4).
    private func sample() throws -> SceneFolderTree {
        var tree = SceneFolderTree()
        try tree.createFolder(named: "A", in: nil, id: Self.fid(1))
        try tree.createFolder(named: "B", in: Self.fid(1), id: Self.fid(2))
        try tree.createFolder(named: "C", in: Self.fid(2), id: Self.fid(3))
        try tree.createFolder(named: "D", in: nil, id: Self.fid(4))
        return tree
    }

    private func refuses(_ expected: SceneFolderError, _ tree: SceneFolderTree,
                         _ body: (inout SceneFolderTree) throws(SceneFolderError) -> Void, file: StaticString = #filePath, line: UInt = #line) {
        var copy = tree
        do throws(SceneFolderError) {
            try body(&copy)
            XCTFail("expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error, expected, file: file, line: line)
        }
        XCTAssertEqual(copy, tree, "a refusal changes nothing", file: file, line: line)
    }

    func testCreateNestsAndReportsPathsDepthsAndChildrenSortedByName() throws {
        var tree = try sample()
        try tree.createFolder(named: "  alpha  ", in: nil, id: Self.fid(5))
        XCTAssertEqual(tree.children(of: nil).map(\.name), ["A", "alpha", "D"], "trimmed, sorted by folded name")
        XCTAssertEqual(tree.pathText(of: Self.fid(3)), "A / B / C")
        XCTAssertEqual(tree.depth(of: Self.fid(3)), 3)
        XCTAssertEqual(tree.height(of: Self.fid(1)), 3)
        XCTAssertNil(tree.pathText(of: nil))
    }

    func testNamesAreValidatedAndUniqueAmongSiblingsIgnoringCaseAccentsAndWidth() throws {
        var tree = try sample()
        refuses(.invalidName, tree) { (t: inout SceneFolderTree) throws(SceneFolderError) in try t.createFolder(named: "   ", in: nil) }
        refuses(.invalidName, tree) { (t: inout SceneFolderTree) throws(SceneFolderError) in try t.createFolder(named: "a\nb", in: nil) }
        refuses(.invalidName, tree) { (t: inout SceneFolderTree) throws(SceneFolderError) in
            try t.createFolder(named: String(repeating: "x", count: 81), in: nil)
        }
        refuses(.nameTaken("a"), tree) { (t: inout SceneFolderTree) throws(SceneFolderError) in try t.createFolder(named: "a", in: nil) }
        try tree.createFolder(named: "Live", in: nil, id: Self.fid(6))
        refuses(.nameTaken("LÍVE"), tree) { (t: inout SceneFolderTree) throws(SceneFolderError) in try t.createFolder(named: "LÍVE", in: nil) }
        refuses(.nameTaken("ｌｉｖｅ"), tree) { (t: inout SceneFolderTree) throws(SceneFolderError) in try t.renameFolder(Self.fid(4), to: "ｌｉｖｅ") }
        // The same name under another parent is fine; renaming to its own name in another case is fine.
        try tree.createFolder(named: "Live", in: Self.fid(1), id: Self.fid(7))
        try tree.renameFolder(Self.fid(6), to: "LIVE")
        XCTAssertEqual(tree.folder(Self.fid(6))?.name, "LIVE")
    }

    func testMovingAFolderIntoItselfOrADescendantIsRefused() throws {
        let tree = try sample()
        refuses(.intoItself, tree) { (t: inout SceneFolderTree) throws(SceneFolderError) in try t.moveFolder(Self.fid(1), to: Self.fid(1)) }
        refuses(.intoItself, tree) { (t: inout SceneFolderTree) throws(SceneFolderError) in try t.moveFolder(Self.fid(1), to: Self.fid(3)) }
        XCTAssertFalse(tree.canMoveFolder(Self.fid(1), to: Self.fid(2)))
        XCTAssertTrue(tree.canMoveFolder(Self.fid(3), to: nil))
    }

    func testDepthIsLimitedToFiveForCreateAndMove() throws {
        var tree = SceneFolderTree()
        var parent: UUID?
        for n in 1...5 {
            try tree.createFolder(named: "L\(n)", in: parent, id: Self.fid(n))
            parent = Self.fid(n)
        }
        XCTAssertFalse(tree.canCreateFolder(in: Self.fid(5)))
        refuses(.tooDeep(limit: 5), tree) { (t: inout SceneFolderTree) throws(SceneFolderError) in try t.createFolder(named: "L6", in: Self.fid(5)) }
        // A two-level subtree cannot go under level 4.
        try tree.createFolder(named: "X", in: nil, id: Self.fid(10))
        try tree.createFolder(named: "Y", in: Self.fid(10), id: Self.fid(11))
        refuses(.tooDeep(limit: 5), tree) { (t: inout SceneFolderTree) throws(SceneFolderError) in try t.moveFolder(Self.fid(10), to: Self.fid(4)) }
        try tree.moveFolder(Self.fid(10), to: Self.fid(3))
        XCTAssertEqual(tree.pathText(of: Self.fid(11)), "L1 / L2 / L3 / X / Y")
    }

    func testMovingAFolderToAParentWithTheSameNameIsRefused() throws {
        var tree = try sample()
        try tree.createFolder(named: "c", in: nil, id: Self.fid(8))
        refuses(.nameTaken("C"), tree) { (t: inout SceneFolderTree) throws(SceneFolderError) in try t.moveFolder(Self.fid(3), to: nil) }
    }

    func testMoveSceneAndUnknownFolders() throws {
        var tree = try sample()
        XCTAssertTrue(try tree.moveScene("S1", to: Self.fid(1)))
        XCTAssertFalse(try tree.moveScene("S1", to: Self.fid(1)), "already there")
        XCTAssertTrue(try tree.moveScene("S1", to: Self.fid(3)))
        XCTAssertEqual(tree.folderID(ofScene: "S1"), Self.fid(3))
        XCTAssertEqual(tree.sceneIDs(in: Self.fid(3), among: ["S0", "S1"]), ["S1"])
        XCTAssertEqual(tree.sceneIDs(in: nil, among: ["S0", "S1"]), ["S0"])
        refuses(.unknownFolder(Self.fid(99)), tree) { (t: inout SceneFolderTree) throws(SceneFolderError) in
            try t.moveScene("S1", to: Self.fid(99))
        }
        XCTAssertTrue(try tree.moveScene("S1", to: nil))
        XCTAssertNil(tree.folderID(ofScene: "S1"))
    }

    func testDeleteMovesScenesAndSubfoldersToTheParentAndSuffixesCollidingNames() throws {
        var tree = try sample()
        try tree.createFolder(named: "C", in: Self.fid(1), id: Self.fid(5))   // A/C beside A/B
        try tree.moveScene("S1", to: Self.fid(2))
        try tree.moveScene("S2", to: Self.fid(2))
        try tree.moveScene("S3", to: Self.fid(3))
        let deletion = try tree.deleteFolder(Self.fid(2))   // B: scenes S1, S2 and folder C go to A
        XCTAssertEqual(deletion.movedScenes, ["S1", "S2"])
        XCTAssertEqual(deletion.movedFolders, [Self.fid(3)])
        XCTAssertEqual(deletion.renamed, [Self.fid(3): "C 2"])
        XCTAssertNil(tree.folder(Self.fid(2)))
        XCTAssertEqual(tree.folderID(ofScene: "S1"), Self.fid(1))
        XCTAssertEqual(tree.folderID(ofScene: "S3"), Self.fid(3), "a subfolder keeps its scenes")
        XCTAssertEqual(tree.children(of: Self.fid(1)).map(\.name), ["C", "C 2"])
        // A top-level folder's contents go to the top level.
        try tree.deleteFolder(Self.fid(1))
        XCTAssertNil(tree.folderID(ofScene: "S1"))
        XCTAssertEqual(Set(tree.children(of: nil).map(\.name)), ["C", "C 2", "D"])
    }

    func testTheFolderLimitIs256() throws {
        var tree = SceneFolderTree()
        for n in 1...256 { try tree.createFolder(named: "F\(n)", in: nil, id: Self.fid(n)) }
        XCTAssertFalse(tree.canCreateFolder(in: nil))
        refuses(.tooManyFolders(limit: 256), tree) { (t: inout SceneFolderTree) throws(SceneFolderError) in
            try t.createFolder(named: "F257", in: nil)
        }
    }
}
