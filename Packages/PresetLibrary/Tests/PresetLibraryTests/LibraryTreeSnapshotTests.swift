// FILE-003-T01: the byte-for-byte snapshot notices a changed byte, an added empty folder and a
// removed file, and equal trees give equal snapshots.
import Foundation
import XCTest
@testable import PresetLibrary

final class LibraryTreeSnapshotTests: XCTestCase {
    private func makeTree() throws -> URL {
        let root = try UserPresetFixtures.tempDirectory(self)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Files"), withIntermediateDirectories: true)
        try Data("index".utf8).write(to: root.appendingPathComponent("index.json"))
        try Data("text".utf8).write(to: root.appendingPathComponent("Files/a.milk"))
        return root
    }

    func testEqualTreesGiveEqualSnapshots() throws {
        let root = try makeTree()
        let first = LibraryTreeSnapshot.take([root])
        let second = LibraryTreeSnapshot.take([root])
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.digest, second.digest)
        XCTAssertEqual(first.files.count, 2)
        XCTAssertEqual(first.directories, ["0/", "0/Files"])
    }

    func testAChangedByteIsNoticed() throws {
        let root = try makeTree()
        let before = LibraryTreeSnapshot.take([root])
        try Data("tExt".utf8).write(to: root.appendingPathComponent("Files/a.milk"))
        let after = LibraryTreeSnapshot.take([root])
        XCTAssertNotEqual(before, after)
        XCTAssertEqual(after.differences(from: before), ["file 0/Files/a.milk"])
        XCTAssertNotEqual(before.digest, after.digest)
    }

    func testAnAddedEmptyFolderAndARemovedFileAreNoticed() throws {
        let root = try makeTree()
        let before = LibraryTreeSnapshot.take([root])
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Staging"), withIntermediateDirectories: true)
        XCTAssertEqual(LibraryTreeSnapshot.take([root]).differences(from: before), ["directory 0/Staging"])
        try FileManager.default.removeItem(at: root.appendingPathComponent("Staging"))
        try FileManager.default.removeItem(at: root.appendingPathComponent("index.json"))
        XCTAssertEqual(LibraryTreeSnapshot.take([root]).differences(from: before), ["file 0/index.json"])
    }

    func testAMissingRootDiffersFromAnEmptyOne() throws {
        let parent = try UserPresetFixtures.tempDirectory(self)
        let root = parent.appendingPathComponent("Library", isDirectory: true)
        let missing = LibraryTreeSnapshot.take([root])
        XCTAssertTrue(missing.directories.isEmpty)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        XCTAssertNotEqual(LibraryTreeSnapshot.take([root]), missing)
    }
}
