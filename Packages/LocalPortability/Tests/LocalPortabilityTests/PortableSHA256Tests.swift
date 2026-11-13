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
}
