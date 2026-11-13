// ShowDocumentTests.swift — the show file's round trip (SHOW-001-S2, contract S1), the load
// validation table (SHOW-001-R11) and the editing rules (SHOW-001-R6).
import Foundation
import ShowControl
import XCTest

final class ShowDocumentTests: XCTestCase {
    // MARK: Round trip

    func testRoundTripKeepsIDsLabelsOrderAndPositionAndReencodesByteIdentically() throws {
        var list = try ShowFixtures.fiveCues()
        try list.move(fromOffsets: IndexSet(integer: 4), toOffset: 0)
        list.go(to: ShowFixtures.uuid(3))
        let bytes = list.encoded()
        let decoded = try ShowCueList.decode(bytes)
        XCTAssertEqual(decoded.warnings, [])
        XCTAssertEqual(decoded.list, list)
        XCTAssertEqual(decoded.list.cues.map(\.id), [5, 1, 2, 3, 4].map { (n: Int) -> UUID in ShowFixtures.uuid(n) })
        XCTAssertEqual(decoded.list.cues.map(\.sceneID), [5, 1, 2, 3, 4].map { (n: Int) -> String in ShowFixtures.sceneID(n) })
        XCTAssertEqual(decoded.list.position, .cue(ShowFixtures.uuid(3)))
        XCTAssertEqual(decoded.list.encoded(), bytes)
        XCTAssertEqual(list.encoded(), bytes, "encoding twice gives the same bytes")
    }

    func testStandbyIsWrittenAsNullAndReadBack() throws {
        let list = try ShowFixtures.fiveCues()
        let text = String(decoding: list.encoded(), as: UTF8.self)
        XCTAssertTrue(text.contains("\"position\":null"), text)
        XCTAssertTrue(text.hasPrefix("{\"cues\":["), "keys are sorted")
        XCTAssertEqual(try ShowCueList.decode(list.encoded()).list.position, .standby)
    }

    // MARK: Validation table

    private func file(format: String = "\"projectm-ios.show\"", version: String = "1", id: String? = nil,
                      cues: String = "[]", position: String = "null") -> Data {
        let showID = id ?? ShowFixtures.showID.uuidString
        return Data("{\"format\":\(format),\"version\":\(version),\"id\":\"\(showID)\",\"name\":\"Show\",\"cues\":\(cues),\"position\":\(position)}".utf8)
    }

    private func cue(_ n: Int, scene: String? = nil, label: String = "L", id: String? = nil) -> String {
        "{\"id\":\"\(id ?? ShowFixtures.uuid(n).uuidString)\",\"scene\":\"\(scene ?? ShowFixtures.sceneID(n))\",\"label\":\"\(label)\"}"
    }

    func testValidationTable() {
        let tooMany = "[" + (1...257).map { (n: Int) -> String in cue(n) }.joined(separator: ",") + "]"
        let cases: [(name: String, data: Data, expected: ShowDecodeError)] = [
            ("not JSON", Data("show".utf8), .malformed),
            ("empty", Data(), .malformed),
            ("wrong format", file(format: "\"projectm-ios.scene\""), .wrongFormat("projectm-ios.scene")),
            ("newer version", file(version: "2"), .newerVersion(2)),
            ("version 0", file(version: "0"), .unsupportedVersion(0)),
            ("missing field", Data("{\"format\":\"projectm-ios.show\",\"version\":1}".utf8), .malformed),
            ("lowercase show ID", file(id: "abcdef00-0000-4000-8000-000000000001"), .invalidID("abcdef00-0000-4000-8000-000000000001")),
            ("bad cue ID", file(cues: "[\(cue(1, id: "cue-1"))]"), .invalidID("cue-1")),
            ("duplicate cue ID", file(cues: "[\(cue(1)),\(cue(2, id: ShowFixtures.uuid(1).uuidString))]"), .invalid(.duplicateCueID(ShowFixtures.uuid(1)))),
            ("bad scene ID", file(cues: "[\(cue(1, scene: "scene"))]"), .invalid(.invalidSceneID("scene"))),
            ("empty label", file(cues: "[\(cue(1, label: ""))]"), .invalid(.invalidLabel)),
            ("untrimmed label", file(cues: "[\(cue(1, label: " L"))]"), .invalid(.invalidLabel)),
            ("label of 81 characters", file(cues: "[\(cue(1, label: String(repeating: "x", count: 81)))]"), .invalid(.invalidLabel)),
            ("line break in label", file(cues: "[\(cue(1, label: "a\\nb"))]"), .invalid(.invalidLabel)),
            ("257 cues", file(cues: tooMany), .invalid(.tooManyCues(limit: 256))),
        ]
        for entry in cases {
            XCTAssertThrowsError(try ShowCueList.decode(entry.data), entry.name) { (error: any Error) in
                XCTAssertEqual(error as? ShowDecodeError, entry.expected, entry.name)
            }
        }
        // Size is checked before parsing.
        let big = Data(repeating: 0x20, count: ShowCueList.maximumFileBytes + 1)
        XCTAssertThrowsError(try ShowCueList.decode(big)) { (error: any Error) in
            XCTAssertEqual(error as? ShowDecodeError, .tooLarge(bytes: ShowCueList.maximumFileBytes + 1, limit: ShowCueList.maximumFileBytes))
        }
    }

    func testAcceptedFilesAndWarnings() throws {
        // 256 cues and an 80-character label are accepted; a dangling position is a warning (Standby).
        let full = "[" + (1...256).map { (n: Int) -> String in cue(n) }.joined(separator: ",") + "]"
        XCTAssertEqual(try ShowCueList.decode(file(cues: full)).list.cues.count, 256)
        let label = String(repeating: "é", count: 80)
        XCTAssertEqual(try ShowCueList.decode(file(cues: "[\(cue(1, label: label))]")).list.cues.first?.label, label)
        let dangling = try ShowCueList.decode(file(cues: "[\(cue(1))]", position: "\"\(ShowFixtures.uuid(9).uuidString)\""))
        XCTAssertEqual(dangling.list.position, .standby)
        XCTAssertEqual(dangling.warnings, [.danglingPosition(ShowFixtures.uuid(9).uuidString)])
        // Two cues may share a scene; unknown keys are ignored.
        let shared = try ShowCueList.decode(Data("{\"format\":\"projectm-ios.show\",\"version\":1,\"id\":\"\(ShowFixtures.showID.uuidString)\",\"name\":\"Show\",\"cues\":[\(cue(1)),\(cue(2, scene: ShowFixtures.sceneID(1)))],\"position\":null,\"later\":true}".utf8))
        XCTAssertEqual(shared.list.sceneIDs, [ShowFixtures.sceneID(1)])
    }

    // MARK: Editing (SHOW-001-R6)

    func testEditsKeepThePositionOnItsCue() throws {
        var list = try ShowFixtures.fiveCues()
        list.go(to: ShowFixtures.uuid(2))
        try list.move(fromOffsets: IndexSet(integer: 1), toOffset: 5)   // cue 2 to the end
        XCTAssertEqual(list.cues.map(\.id), [1, 3, 4, 5, 2].map { (n: Int) -> UUID in ShowFixtures.uuid(n) })
        XCTAssertEqual(list.position, .cue(ShowFixtures.uuid(2)))
        XCTAssertEqual(list.positionText, "Cue 5 of 5")
        try list.move(fromOffsets: IndexSet([0, 2]), toOffset: 4)   // cues 1 and 4 before cue 2
        XCTAssertEqual(list.cues.map(\.id), [3, 5, 1, 4, 2].map { (n: Int) -> UUID in ShowFixtures.uuid(n) })
        try list.rename(ShowFixtures.uuid(2), to: "  Finale  ")
        XCTAssertEqual(list.activeCue?.label, "Finale")
        XCTAssertEqual(list.activeSceneID, ShowFixtures.sceneID(2))
        XCTAssertThrowsError(try list.move(fromOffsets: IndexSet(integer: 5), toOffset: 0))
        XCTAssertThrowsError(try list.move(fromOffsets: IndexSet(integer: 0), toOffset: 6))
    }

    func testRemovingTheActiveCueStandsOnTheCueBeforeIt() throws {
        var list = try ShowFixtures.fiveCues()
        list.go(to: ShowFixtures.uuid(3))
        try list.remove(ShowFixtures.uuid(3))
        XCTAssertEqual(list.position, .cue(ShowFixtures.uuid(2)))
        XCTAssertEqual(list.next().sceneID, ShowFixtures.sceneID(4), "Next plays the cue that followed the removed one")
        list.go(to: ShowFixtures.uuid(1))
        try list.remove(ShowFixtures.uuid(1))
        XCTAssertEqual(list.position, .standby)
        XCTAssertEqual(list.next().sceneID, ShowFixtures.sceneID(2))
        try list.remove(ShowFixtures.uuid(5))   // not active: position unchanged
        XCTAssertEqual(list.position, .cue(ShowFixtures.uuid(2)))
        XCTAssertThrowsError(try list.remove(ShowFixtures.uuid(5))) { (error: any Error) in
            XCTAssertEqual(error as? ShowEditError, .unknownCue(ShowFixtures.uuid(5)))
        }
    }

    func testAppendRules() throws {
        var list = ShowCueList(id: ShowFixtures.showID)
        XCTAssertThrowsError(try list.append(sceneID: "x", label: "L"))
        XCTAssertThrowsError(try list.append(sceneID: ShowFixtures.sceneID(1).lowercased(), label: "L"))
        XCTAssertThrowsError(try list.append(sceneID: ShowFixtures.sceneID(1), label: "   "))
        try list.append(sceneID: ShowFixtures.sceneID(1), label: "A", cueID: ShowFixtures.uuid(1))
        XCTAssertThrowsError(try list.append(sceneID: ShowFixtures.sceneID(1), label: "B", cueID: ShowFixtures.uuid(1))) { (error: any Error) in
            XCTAssertEqual(error as? ShowEditError, .duplicateCueID(ShowFixtures.uuid(1)))
        }
        for n in 2...256 { try list.append(sceneID: ShowFixtures.sceneID(1), label: "C", cueID: ShowFixtures.uuid(n)) }
        XCTAssertThrowsError(try list.append(sceneID: ShowFixtures.sceneID(1), label: "D")) { (error: any Error) in
            XCTAssertEqual(error as? ShowEditError, .tooManyCues(limit: 256))
        }
        XCTAssertEqual(list.position, .standby, "adding never moves the show")
    }
}
