// PRE-014-T05: the path rules every archive entry name must follow (research D5).
import XCTest
import LocalPortability

final class ArchivePathTests: XCTestCase {
    func testAcceptsSafeRelativePaths() throws {
        for path in ["manifest.json", "presets/0f1e2d3c-aaaa-bbbb-cccc-0123456789ab.milk", "a/b/c/d/e/f/g/h.txt",
                     "Préréglages/水.milk", "with space/and-dash_underscore.milk", String(repeating: "a", count: 255)] {
            XCTAssertEqual(try ArchivePath.validate(path), path, path)
            XCTAssertTrue(ArchivePath.isSafe(path), path)
        }
    }

    func testRefusesUnsafePaths() {
        let cases: [(String, ArchivePathError)] = [
            ("", .empty),
            ("/x", .absolute),
            ("../x", .dotComponent),
            ("a/../x", .dotComponent),
            ("./x", .dotComponent),
            ("a/.", .dotComponent),
            ("a//b", .emptyComponent),
            ("a\\b", .backslash),
            ("C:x", .colon),
            ("a/b:c", .colon),
            ("a\u{0}b", .controlCharacter),
            ("a\nb", .controlCharacter),
            ("a\u{202E}b", .controlCharacter),   // right-to-left override (format character)
            (String(repeating: "a", count: 256), .tooLong),
            (String(repeating: "é", count: 128), .tooLong),   // 256 UTF-8 bytes
            ("1/2/3/4/5/6/7/8/9", .tooDeep),
            ("a/", .trailingSlash),
        ]
        for (path, expected) in cases {
            XCTAssertThrowsError(try ArchivePath.validate(path), path.debugDescription) { error in
                XCTAssertEqual(error as? ArchivePathError, expected, path.debugDescription)
            }
            XCTAssertFalse(ArchivePath.isSafe(path), path.debugDescription)
        }
    }

    func testCollisionKeyFoldsCaseAndNormalization() {
        XCTAssertEqual(ArchivePath.collisionKey("Presets/A.milk"), ArchivePath.collisionKey("presets/a.milk"))
        XCTAssertEqual(ArchivePath.collisionKey("caf\u{E9}.milk"), ArchivePath.collisionKey("cafe\u{301}.milk"))
        XCTAssertNotEqual(ArchivePath.collisionKey("a.milk"), ArchivePath.collisionKey("b.milk"))
    }

    func testErrorsHaveWords() {
        XCTAssertFalse(ArchivePathError.dotComponent.message.isEmpty)
    }
}
