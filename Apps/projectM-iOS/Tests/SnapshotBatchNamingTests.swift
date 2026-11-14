// SnapshotBatchNamingTests.swift — REC-002-T07 (R5; contract B1): safe names and batch file names.
import XCTest
@testable import projectM_iOS

final class SnapshotBatchNamingTests: XCTestCase {
    func testSafeNames() {
        let cases: [(String, String)] = [
            ("Dawn/Dusk", "Dawn-Dusk"), ("Dawn:Dusk", "Dawn-Dusk"), ("🌅🌅", "Snapshot"), ("Sunset 🌅", "Sunset"),
            ("...", "Snapshot"), ("", "Snapshot"), ("Été  (live)", "Été (live)"), ("a\\b*c?", "a-b-c"),
            ("Tab\there", "Tab here"), ("1️⃣ Intro", "Intro"), ("夜明け", "夜明け"), ("snap_2 - final", "snap_2 - final"),
        ]
        for (input, expected) in cases {
            XCTAssertEqual(SnapshotBatchNaming.safeName(input), expected, input)
        }
        let long = String(repeating: "x", count: 64)
        XCTAssertEqual(SnapshotBatchNaming.safeName(long).count, SnapshotBatchNaming.maximumLength)
    }

    func testFileNamesArePositionedAndUnique() {
        XCTAssertEqual(SnapshotBatchNaming.fileNames(["A", "a", "B"]), ["01-A.png", "02-a.png", "03-B.png"])
        let many: [String] = (1...100).map { (i: Int) -> String in "S" }
        let names = SnapshotBatchNaming.fileNames(many)
        XCTAssertEqual(names.first, "001-S.png")
        XCTAssertEqual(names.last, "100-S.png")
        XCTAssertEqual(Set(names.map { (n: String) -> String in n.lowercased() }).count, 100)
    }
}
