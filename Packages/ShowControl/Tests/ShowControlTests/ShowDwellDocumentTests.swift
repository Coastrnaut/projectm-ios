// ShowDwellDocumentTests.swift — SHOW-002-T05: a cue's `advanceAfter` in show.json (SHOW-002-R2, S5; contract
// show-cue-dwell.md D1-D2): exact round trip, unchanged bytes without dwells, lenient reading with a counted
// warning, and a store reload.
import Foundation
import ShowControl
import ShowStorage
import XCTest

final class ShowDwellDocumentTests: XCTestCase {
    private func withDwells() throws -> ShowCueList {
        var list = try ShowFixtures.fiveCues()
        try list.setDwell(ShowFixtures.uuid(1), to: try ShowCueDwell(seconds: 30))
        try list.setDwell(ShowFixtures.uuid(3), to: try ShowCueDwell(seconds: 3600))
        try list.setTransition(ShowFixtures.uuid(3), to: ShowCueTransition.defaultCrossfade)
        return list
    }

    private func file(cueA value: String) throws -> Data {
        let text = String(decoding: try ShowFixtures.fiveCues().encoded(), as: UTF8.self)
        let id = #"{"id":""# + ShowFixtures.uuid(1).uuidString + "\""
        return Data(text.replacingOccurrences(of: id, with: #"{"advanceAfter":"# + value + #","id":""# + ShowFixtures.uuid(1).uuidString + "\"").utf8)
    }

    func testDwellsRoundTripExactly() throws {
        let list = try withDwells()
        let data = list.encoded()
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains(#"{"advanceAfter":30,"id":""#), text)
        XCTAssertEqual(text.components(separatedBy: "advanceAfter").count, 3, "written only for cues with a dwell")
        XCTAssertEqual(text.components(separatedBy: "\"version\":1").count, 2, "version stays 1")
        let decoded = try ShowCueList.decode(data)
        XCTAssertEqual(decoded.warnings, [])
        XCTAssertEqual(decoded.list, list)
        XCTAssertEqual(decoded.list.cues.map { (c: ShowCue) -> Int? in c.dwell?.seconds }, [30, nil, 3600, nil, nil])
        XCTAssertEqual(decoded.list.encoded(), data, "decode → encode is byte-identical")
    }

    func testAShowWithoutDwellsKeepsItsBytes() throws {
        let plain = try ShowFixtures.fiveCues().encoded()
        XCTAssertFalse(String(decoding: plain, as: UTF8.self).contains("advanceAfter"))
        var cleared = try withDwells()
        for n in 1...5 { try cleared.setDwell(ShowFixtures.uuid(n), to: nil) }
        try cleared.setTransition(ShowFixtures.uuid(3), to: nil)
        XCTAssertEqual(cleared.encoded(), plain, "turning every dwell off gives the SHOW-001 bytes")
        let nulled = try ShowCueList.decode(try file(cueA: "null"))
        XCTAssertEqual(nulled.warnings, [])
        XCTAssertNil(nulled.list.cues[0].dwell)
        XCTAssertEqual(nulled.list.encoded(), plain)
    }

    func testAWholeNumberWrittenAsADecimalIsRead() throws {
        let decoded = try ShowCueList.decode(try file(cueA: "45.0"))
        XCTAssertEqual(decoded.warnings, [])
        XCTAssertEqual(decoded.list.cues[0].dwell?.seconds, 45)
    }

    func testInvalidDwellsAreDroppedWithACountedWarning() throws {
        for value in ["0", "-5", "3601", "2.5", #""30""#, "true", "{}", "[30]", "1e9"] {
            let decoded = try ShowCueList.decode(try file(cueA: value))
            XCTAssertEqual(decoded.warnings, [.droppedDwells(1)], value)
            XCTAssertNil(decoded.list.cues[0].dwell, value)
            XCTAssertEqual(decoded.list.cues.count, 5, "the show loads: \(value)")
            XCTAssertEqual(decoded.list.encoded(), try ShowFixtures.fiveCues().encoded(), "dropped on write: \(value)")
        }
    }

    func testAStoreReloadRestoresDwells() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("show002-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let list = try withDwells()
        try ShowStore(directory: directory).save(list)
        let loaded = ShowStore(directory: directory).load()
        XCTAssertEqual(loaded.warnings, [])
        XCTAssertEqual(loaded.list.cues.map { (c: ShowCue) -> Int? in c.dwell?.seconds }, [30, nil, 3600, nil, nil])
    }
}
