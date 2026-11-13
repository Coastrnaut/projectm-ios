// GraphImportHostileInputTests.swift — FILE-007-T09 (FILE-007-R8, S2): generator-graph import keeps
// its own pre-checks (SHD-011: 64 KiB before reading, nesting ≤ 8 counted outside strings before
// decoding), which bound the platform decoder as FILE-007 requires. This proves the row's hostile
// shapes are refused before decoding. CPU only; runs on Linux.
import Foundation
import GeneratorGraphImport
import XCTest

final class GraphImportHostileInputTests: XCTestCase {
    private func refusal(_ text: [UInt8]) -> GeneratorGraphImportError? {
        do {
            _ = try GeneratorGraphImporter.importGraph(Data(text), fileName: "graph.json")
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

    func testDeepNestingWithinTheByteLimitIsRefusedBeforeDecoding() {
        let deep = Array("{\"a\":".utf8) + repeated("[", 60_000)
        XCTAssertEqual(refusal(deep), .nestingTooDeep(limit: GraphImportLimits.maximumNesting))
        XCTAssertEqual(refusal(repeated("{\"a\":", 10_000)), .nestingTooDeep(limit: GraphImportLimits.maximumNesting))
    }

    func testOversizePayloadsAreRefusedBeforeReading() {
        XCTAssertEqual(refusal(repeated("[", 100_000)), .tooLarge(bytes: 100_000, limit: GraphImportLimits.maximumBytes))
        let tenMegabytes = Array("{\"a\":\"".utf8) + [UInt8](repeating: 0x78, count: 10_000_000) + Array("\"}".utf8)
        XCTAssertEqual(refusal(tenMegabytes), .tooLarge(bytes: tenMegabytes.count, limit: GraphImportLimits.maximumBytes))
    }
}
