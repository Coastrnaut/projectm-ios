// OSC-001-T04: local-network scope (OSC-001-R4; research OSC-001-D2), port rules (OSC-001-R2) and
// the peer table (OSC-001-R5).
@testable import PerformanceControl
import XCTest

final class OSCPeerAddressTests: XCTestCase {
    private func v6(_ groups: [UInt16]) -> OSCPeerAddress {
        .ipv6(groups.flatMap { [UInt8($0 >> 8), UInt8($0 & 0xFF)] })
    }

    func testLocalAddresses() {
        let local: [OSCPeerAddress] = [
            .ipv4(127, 0, 0, 1), .ipv4(10, 1, 2, 3), .ipv4(172, 16, 0, 1), .ipv4(172, 31, 255, 255),
            .ipv4(192, 168, 1, 20), .ipv4(169, 254, 3, 4),
            v6([0, 0, 0, 0, 0, 0, 0, 1]),                        // ::1
            v6([0xFE80, 0, 0, 0, 0, 0, 0, 1]),                   // fe80::1
            v6([0xFD12, 0, 0, 0, 0, 0, 0, 1]),                   // fd12::1 (unique local)
            v6([0, 0, 0, 0, 0, 0xFFFF, 0xC0A8, 0x0102]),         // ::ffff:192.168.1.2
        ]
        for address in local { XCTAssertTrue(address.isLocal, "\(address)") }
    }

    func testNonLocalAddresses() {
        let remote: [OSCPeerAddress] = [
            .ipv4(8, 8, 8, 8), .ipv4(172, 32, 0, 1), .ipv4(100, 64, 0, 1), .ipv4(192, 169, 0, 1),
            v6([0x2001, 0x0DB8, 0, 0, 0, 0, 0, 1]),              // 2001:db8::1
            v6([0, 0, 0, 0, 0, 0xFFFF, 0x0808, 0x0808]),         // ::ffff:8.8.8.8
            v6([0, 0, 0, 0, 0, 0, 0, 0]),                        // :: (unspecified)
            .ipv6([UInt8](repeating: 0, count: 15)),             // malformed
        ]
        for address in remote { XCTAssertFalse(address.isLocal, "\(address)") }
    }

    func testPortParsing() {
        XCTAssertEqual(OSCPort.parse("9000"), 9000)
        XCTAssertEqual(OSCPort.parse(" 1024 "), 1024)
        XCTAssertEqual(OSCPort.parse("65535"), 65535)
        for bad in ["80", "1023", "65536", "", "9a", "-1", "+9000", "99999999999999999999", "９０００"] {
            XCTAssertNil(OSCPort.parse(bad), bad)
        }
        XCTAssertEqual(OSCPort.defaultPort, 9000)
        XCTAssertTrue(OSCPort.isValid(9000))
        XCTAssertFalse(OSCPort.isValid(0))
    }

    func testPeerTableEvictsTheLeastRecentlyAdmitted() {
        var table = OSCPeerTable<Int>(capacity: 8)
        for key in 1...8 { XCTAssertNil(table.admit(key)) }
        XCTAssertNil(table.admit(3), "a known peer evicts nothing")
        XCTAssertEqual(table.admit(9), 1)
        XCTAssertEqual(table.admit(10), 2)
        table.remove(4)
        XCTAssertNil(table.admit(11))
        XCTAssertEqual(table.count, 8)
        XCTAssertEqual(table.admit(12), 3)
    }
}
