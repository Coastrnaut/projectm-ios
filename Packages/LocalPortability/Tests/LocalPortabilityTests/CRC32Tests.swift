// PRE-014-T03: CRC-32 (IEEE 802.3, the ZIP checksum) against the standard check value.
import XCTest
import LocalPortability

final class CRC32Tests: XCTestCase {
    func testStandardCheckValue() {
        XCTAssertEqual(CRC32.checksum(Array("123456789".utf8)), 0xCBF4_3926)
    }

    func testEmptyIsZero() {
        XCTAssertEqual(CRC32.checksum([UInt8]()), 0)
    }

    func testKnownVectors() {
        XCTAssertEqual(CRC32.checksum(Array("The quick brown fox jumps over the lazy dog".utf8)), 0x414F_A339)
        XCTAssertEqual(CRC32.checksum([0x00]), 0xD202_EF8D)
    }

    func testIncrementalEqualsOneShot() {
        let bytes = Array((0..<10_000).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        let first = CRC32.checksum(bytes[0..<4_321])
        XCTAssertEqual(CRC32.checksum(bytes[4_321...], initial: first), CRC32.checksum(bytes))
    }

    func testDataInput() {
        XCTAssertEqual(CRC32.checksum(Data("123456789".utf8)), 0xCBF4_3926)
    }
}
