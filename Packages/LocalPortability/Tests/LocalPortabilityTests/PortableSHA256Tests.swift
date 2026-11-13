// PRE-014-T03: SHA-256 (moved from PresetLibrary.ContentHash) against the FIPS 180 examples.
import XCTest
import LocalPortability

final class PortableSHA256Tests: XCTestCase {
    func testFIPSVectors() {
        XCTAssertEqual(PortableSHA256.hex([]), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual(PortableSHA256.hex(Array("abc".utf8)), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(PortableSHA256.hex(Array("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".utf8)),
                       "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
    }

    func testMillionA() {
        XCTAssertEqual(PortableSHA256.hex([UInt8](repeating: 0x61, count: 1_000_000)),
                       "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0")
    }

    func testDataInputEqualsArrayInput() {
        let bytes = Array("projectM".utf8)
        XCTAssertEqual(PortableSHA256.hex(Data(bytes)), PortableSHA256.hex(bytes))
    }

    // FILE-002-T08: the incremental hasher equals the one-shot digest for every chunk size, and the
    // published one-million-"a" vector (FILE-002-S3).
    func testIncrementalHashingEqualsOneShotForEveryChunkSize() {
        let bytes = (0..<10_000).map { (i: Int) -> UInt8 in UInt8(truncatingIfNeeded: i &* 7 &+ 3) }
        let expected = PortableSHA256.hex(bytes)
        for chunk in [1, 63, 64, 65, 4_096] {
            var hasher = PortableSHA256.Hasher()
            var start = 0
            while start < bytes.count {
                let end = min(start + chunk, bytes.count)
                hasher.update(Array(bytes[start..<end]))
                start = end
            }
            XCTAssertEqual(hasher.finalize(), expected, "chunk \(chunk)")
        }
        XCTAssertEqual(PortableSHA256.Hasher().finalize(), PortableSHA256.hex([]))
        for length in [55, 56, 57, 63, 64, 65, 119, 120, 128] {
            let input = [UInt8](repeating: 0x5A, count: length)
            var hasher = PortableSHA256.Hasher()
            hasher.update(Data(input))
            XCTAssertEqual(hasher.finalize(), PortableSHA256.hex(input), "length \(length)")
        }
    }

    func testIncrementalMillionA() {
        var hasher = PortableSHA256.Hasher()
        let chunk = [UInt8](repeating: 0x61, count: 1_000)
        for _ in 0..<1_000 { hasher.update(chunk) }
        XCTAssertEqual(hasher.finalize(), "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0")
        hasher.update(Array("x".utf8))
        XCTAssertNotEqual(hasher.finalize(), "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0", "update after finalize continues the message")
    }
}
