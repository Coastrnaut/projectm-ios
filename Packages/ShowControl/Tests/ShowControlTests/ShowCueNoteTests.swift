// ShowCueNoteTests.swift — SHOW-012-T04 (specs/285-show-012-cue-annotations; R1-R4, S1; contract show-cue-note.md
// N1-N3): the note rules, editing, the `note` key's byte-identical round trip through `show.json` and the store, a
// missing note decoding as nil, an older file keeping its bytes, and the lenient read.
import Foundation
import ShowControl
import ShowStorage
import XCTest

final class ShowCueNoteTests: XCTestCase {
    private static let scene = "6F9619FF-8B86-D011-B42D-00C04FC964FF"
    private static let first = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private static let second = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    /// Line breaks, an emoji with a joiner, a combining mark and a quote: everything the stored form keeps.
    private static let note = "Wait for the drummer's count-in.\nThen \"go\" 👩‍👩‍👧 café"

    private func show() throws -> ShowCueList {
        var list = ShowCueList(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!, name: "Notes")
        try list.append(sceneID: Self.scene, label: "Intro", cueID: Self.first)
        try list.append(sceneID: Self.scene, label: "Drop", cueID: Self.second)
        return list
    }

    // MARK: - R1 rules

    func testCleaningKeepsLineFeedsAndRemovesOtherControlCharacters() {
        XCTAssertEqual(ShowCueNote.cleaned("  a\r\nb\rc\u{2028}d\u{2029}e  \n\n"), "a\nb\nc\nd\ne")
        XCTAssertEqual(ShowCueNote.cleaned("t\u{0}a\tb\u{1B}[0m\u{7F}\u{85}c"), "tab[0mc", "NUL, tab, ESC, DEL, C1 removed")
        XCTAssertEqual(ShowCueNote.cleaned("👩‍👩‍👧"), "👩‍👩‍👧", "a joiner (format, not control) stays")
        XCTAssertNil(ShowCueNote.normalized(" \n\t\n "), "only whitespace is no note")
        XCTAssertEqual(ShowCueNote.normalized(Self.note), Self.note)
    }

    func testTheLimitCountsCharactersAsTheUserSeesThem() {
        let full = String(repeating: "é", count: 500)   // 500 characters, 1,000 UTF-8 bytes
        XCTAssertEqual(ShowCueNote.normalized(full), full)
        XCTAssertNil(ShowCueNote.normalized(full + "x"), "501 characters are refused when edited")
        XCTAssertEqual(ShowCueNote.stored(full + "xyz"), full, "and cut to 500 when read")
        XCTAssertEqual(ShowCueNote.normalized(String(repeating: "👩‍👩‍👧", count: 500))?.count, 500)
    }

    func testPreviewIsTheFirstLineUpToSixtyCharacters() {
        XCTAssertEqual(ShowCueNote.preview("Short"), "Short")
        XCTAssertEqual(ShowCueNote.preview("Line one\nLine two"), "Line one…")
        XCTAssertEqual(ShowCueNote.preview(String(repeating: "a", count: 61)), String(repeating: "a", count: 60) + "…")
    }

    // MARK: - Editing

    func testSetClearAndRefuseNotesWithoutTouchingTheRest() throws {
        var list = try show()
        list.go(to: Self.second)
        let before = list.cues
        XCTAssertEqual(try list.setOperatorNote(Self.first, to: "  Cue the lights\t "), "Cue the lights")
        XCTAssertEqual(list.cues[0].operatorNote, "Cue the lights")
        XCTAssertEqual(list.position, .cue(Self.second), "a note never moves the position")
        XCTAssertEqual(list.cues.map(\.id), before.map(\.id))
        XCTAssertEqual(list.cues[0].label, "Intro")
        XCTAssertThrowsError(try list.setOperatorNote(Self.first, to: String(repeating: "x", count: 501))) { (error: any Error) in
            XCTAssertEqual(error as? ShowEditError, .invalidNote)
        }
        XCTAssertEqual(list.cues[0].operatorNote, "Cue the lights", "a refused note leaves the old one")
        XCTAssertNil(try list.setOperatorNote(Self.first, to: "\n "))
        XCTAssertNil(list.cues[0].operatorNote, "empty text removes the note")
        XCTAssertThrowsError(try list.setOperatorNote(UUID(), to: "x"))
        XCTAssertThrowsError(try ShowCueList(id: UUID(), name: "S", cues: [ShowCue(id: UUID(), sceneID: Self.scene, label: "A",
                                                                                     operatorNote: " untrimmed")],
                                             position: .standby), "stored parts must already be in stored form")
    }

    func testInsertCarriesTheNoteAndMoveKeepsIt() throws {
        var list = try show()
        let copy = try list.insert(sceneID: Self.scene, label: "Intro copy", after: Self.first, operatorNote: "Copied")
        XCTAssertEqual(list.cues[1].operatorNote, "Copied")
        try list.move(fromOffsets: IndexSet(integer: 1), toOffset: 3)
        XCTAssertEqual(list.cues.last?.id, copy.id)
        XCTAssertEqual(list.cues.last?.operatorNote, "Copied")
        XCTAssertThrowsError(try list.insert(sceneID: Self.scene, label: "Bad", after: Self.first, operatorNote: ""))
    }

    // MARK: - R2-R4 file

    func testNoteRoundTripsByteIdenticalAndMissingDecodesAsNil() throws {
        var list = try show()
        try list.setOperatorNote(Self.second, to: Self.note)
        let bytes = list.encoded()
        let text = try XCTUnwrap(String(data: bytes, encoding: .utf8))
        XCTAssertEqual(text.components(separatedBy: "\"note\"").count - 1, 1, "written only for the cue that has one")
        let decoded = try ShowCueList.decode(bytes)
        XCTAssertEqual(decoded.warnings, [])
        XCTAssertNil(decoded.list.cues[0].operatorNote, "a missing note decodes as nil")
        XCTAssertEqual(decoded.list.cues[1].operatorNote, Self.note)
        XCTAssertEqual(Array(decoded.list.cues[1].operatorNote!.utf8), Array(Self.note.utf8), "byte-identical field")
        XCTAssertEqual(decoded.list.encoded(), bytes, "decode → encode is byte-identical")
    }

    func testAShowWithoutNotesKeepsItsBytes() throws {
        let list = try show()
        XCTAssertFalse(String(decoding: list.encoded(), as: UTF8.self).contains("note"))
        var noted = list
        try noted.setOperatorNote(Self.first, to: "x")
        try noted.setOperatorNote(Self.first, to: nil)
        XCTAssertEqual(noted.encoded(), list.encoded(), "removing the last note restores the exact bytes")
    }

    func testLenientReadDropsNonTextAndShortensBadText() throws {
        var list = try show()
        try list.setOperatorNote(Self.first, to: "placeholder")
        try list.setOperatorNote(Self.second, to: "placeholder")
        var text = String(decoding: list.encoded(), as: UTF8.self)
        let long = String(repeating: "n", count: 520)
        var replaced = false
        text = text.replacingOccurrences(of: "\"note\":\"placeholder\"", with: "\"note\":42", options: [], range: nil)
        if let range = text.range(of: "\"note\":42") {   // the second cue gets a long note with a tab
            let rest = text[range.upperBound...]
            if let second = rest.range(of: "\"note\":42") {
                text.replaceSubrange(second, with: "\"note\":\"\\t\(long)\"")
                replaced = true
            }
        }
        XCTAssertTrue(replaced)
        let decoded = try ShowCueList.decode(Data(text.utf8))
        XCTAssertEqual(decoded.warnings, [.droppedNotes(1), .shortenedNotes(1)])
        XCTAssertNil(decoded.list.cues[0].operatorNote)
        XCTAssertEqual(decoded.list.cues[1].operatorNote, String(repeating: "n", count: 500))
        let null = text.replacingOccurrences(of: "\"note\":42", with: "\"note\":null")
        XCTAssertNil(try ShowCueList.decode(Data(null.utf8)).list.cues[0].operatorNote, "null is no note, no warning")
    }

    func testStoreSaveAndLoadKeepTheNote() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("SHOW012-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var list = try show()
        try list.setOperatorNote(Self.first, to: Self.note)
        let store = ShowStore(directory: folder)
        try store.save(list)
        XCTAssertEqual(store.load().list.cues[0].operatorNote, Self.note)
    }
}
