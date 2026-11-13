// SceneHostileInputTests.swift — FILE-007-T09 (FILE-007-R8, S2): the scene document keeps its own
// bounded reader (SCN-001-R8), which already enforces FILE-007's limits. This proves it refuses the
// row's hostile shapes (deep nesting, an oversize payload, a duplicate key) before any typed decoding.
import Foundation
@testable import SceneFormat
import XCTest

final class SceneHostileInputTests: XCTestCase {
    private func refusal(_ bytes: [UInt8]) -> SceneDecodeError? {
        do {
            _ = try SceneDocument.decode(bytes)
            return nil
        } catch {
            return error
        }
    }

    private func repeated(_ text: String, _ times: Int) -> [UInt8] {
        let unit = Array(text.utf8)
        var out: [UInt8] = []
        out.reserveCapacity(unit.count * times)
        for _ in 0..<times { out.append(contentsOf: unit) }
        return out
    }

    func testDeepNestingIsRefusedAtTheDepthLimit() {
        XCTAssertEqual(refusal(repeated("[", 100_000)), .nestingTooDeep(limit: SceneLimits.maximumDepth))
        XCTAssertEqual(refusal(repeated("{\"a\":", 100_000)), .nestingTooDeep(limit: SceneLimits.maximumDepth))
    }

    func testOversizePayloadsAreRefusedBeforeParsing() {
        let tenMegabyteString = [UInt8(ascii: "\"")] + [UInt8](repeating: 0x78, count: 10_000_000) + [UInt8(ascii: "\"")]
        XCTAssertEqual(refusal(tenMegabyteString), .tooLarge(bytes: 10_000_002, limit: SceneLimits.maximumBytes))
        let millionElements = Array("[".utf8) + repeated("0,", 999_999) + Array("0]".utf8)
        XCTAssertEqual(refusal(millionElements), .tooLarge(bytes: 2_000_001, limit: SceneLimits.maximumBytes))
    }

    func testDuplicateKeysAreRefused() {
        XCTAssertEqual(refusal(Array("{\"a\":1,\"a\":2}".utf8)), .duplicateKey(path: "$", key: "a"))
    }
}
