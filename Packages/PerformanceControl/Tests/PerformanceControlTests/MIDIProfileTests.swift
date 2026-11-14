// MIDI-012-T05, T11, T12: MIDI mapping profiles (specs/171-midi-012-profiles, contract P1).
// * The row's acceptance (S1): a profile with every line kind survives the store file and the exported document with
//   every line byte-identical (UTF-8) and in order: channels 1 and 16, controller 119, a note, `ccbtn`, `rt`, `pc`,
//   the position mode and unknown lines.
// * Malformed and oversized documents and store files are refused (S2); names, limits, links and the suggestion.
// Pure Swift: runs on the host and on Linux (no Apple-only API in the tested files).
import Foundation
import ParameterGraph
import ParameterGraph
@testable import PerformanceControl
import XCTest

final class MIDIProfileTests: XCTestCase {
    /// Every line kind, in a deliberately non-canonical order (the coordinator would write CC, triggers, scenes).
    static let everyKind: [String] = [
        "note:15:60=blackout;mode=hold",                       // a note trigger on channel 16, held
        "cc:0:7=effect.bloom.intensity",                       // channel 1
        "cc:15:119=effect.bloom.radius;curve=log:9.0;invert=1",   // channel 16, the highest learnable controller
        "ccbtn:3:64=transport.toggle",                          // a CC button
        "rt:start=transport.play", "rt:stop=transport.pause",    // real time
        "pc:0:5=cue.go:5CE7E000-0000-4000-8000-00000000000A",   // program change selects a scene
        "note:9:36=cue.go:5CE7E000-0000-4000-8000-00000000000B",   // a note selects a scene
        "note:9:37=cue.go:Scène-ü",                            // a scene line this version cannot read (non-ASCII)
        "pc:*:*=cue.position",                                 // the position mode
        "osc:/projectm/glow=effect.bloom.intensity",           // an unknown kind (newer version)
        "cc:0:200=effect.bloom.knee",                          // an unreadable control line
    ]

    private func assertBytesEqual(_ lines: [String], _ expected: [String], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(lines.map { (text: String) -> [UInt8] in Array(text.utf8) },
                       expected.map { (text: String) -> [UInt8] in Array(text.utf8) }, file: file, line: line)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MIDIProfileTests-" + UUID().uuidString, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url.appendingPathComponent("MIDIProfiles", isDirectory: true)
    }

    // MARK: S1 — the row's acceptance

    func testProfileRoundTripPreservesChannelControlAndDestinationIDs() throws {
        let directory: URL = try temporaryDirectory()
        let store = MIDIProfileFileStore(directory: directory)
        var list = MIDIProfileList()
        let saved: MIDIProfile = try list.saveCurrent(Self.everyKind, id: "A")
        XCTAssertEqual(saved.name, "Profile 1")
        try store.write(list)

        // In-store round trip.
        let reloaded: MIDIProfileList = try store.load().get()
        let stored: MIDIProfile = try XCTUnwrap(reloaded.profile(id: "A"))
        assertBytesEqual(stored.lines, Self.everyKind)

        // Export → import.
        let document: Data = MIDIProfileDocument.encode(name: stored.name, lines: stored.lines)
        let imported = try MIDIProfileDocument.decode(document)
        XCTAssertEqual(imported.name, "Profile 1")
        assertBytesEqual(imported.lines, Self.everyKind)
        var other = MIDIProfileList()
        let added: MIDIProfile = try other.add(name: imported.name, lines: imported.lines, id: "B")
        assertBytesEqual(added.lines, Self.everyKind)
        XCTAssertTrue(MIDIProfileList.inUse(added, current: Self.everyKind))

        // The parsed values are the same bindings: channel, control and destination.
        let cc = MIDIBindingList(storageLines: added.lines, allowedTargets: [ParameterIDFixture.intensity, ParameterIDFixture.radius])
        XCTAssertEqual(cc.bindings.map { (binding: MIDIControlBinding) -> String in binding.storageLine },
                       ["cc:0:7=effect.bloom.intensity", "cc:15:119=effect.bloom.radius;curve=log:9.0;invert=1"])
        let triggers = MIDINoteBindingList(storageLines: added.lines)
        XCTAssertEqual(triggers.storageLines, ["note:15:60=blackout;mode=hold", "ccbtn:3:64=transport.toggle",
                                               "rt:start=transport.play", "rt:stop=transport.pause"])
        let scenes = MIDISceneBindingList(storageLines: added.lines)
        XCTAssertEqual(scenes.storageLines, ["pc:0:5=cue.go:5CE7E000-0000-4000-8000-00000000000A",
                                             "note:9:36=cue.go:5CE7E000-0000-4000-8000-00000000000B", "pc:*:*=cue.position",
                                             "note:9:37=cue.go:Scène-ü"], "bindings, the mode, then the kept line")

        // The report counts each kind.
        let report = MIDIProfileReport(lines: imported.lines)
        XCTAssertEqual(report.counts[.controlChange], 2)
        XCTAssertEqual(report.counts[.noteTrigger], 1)
        XCTAssertEqual(report.counts[.ccButton], 1)
        XCTAssertEqual(report.counts[.realTime], 2)
        XCTAssertEqual(report.counts[.scene], 3)
        XCTAssertEqual(report.unread, 3)
        XCTAssertEqual(report.summary, "2 controls, 1 note trigger, 1 button, 2 Start/Stop triggers, 3 scene triggers. "
                       + "3 lines are not used by this version and are kept as they are.")
    }

    func testTheExportCarriesNoLinkAndIsStable() throws {
        var list = MIDIProfileList()
        let profile: MIDIProfile = try list.add(name: "Launch Control", lines: ["cc:0:7=effect.bloom.intensity"], id: "A")
        XCTAssertTrue(list.setLink(.unique(0x5EC2E7), for: profile.id))
        let linked: MIDIProfile = try XCTUnwrap(list.profile(id: "A"))
        let data: Data = MIDIProfileDocument.encode(name: linked.name, lines: linked.lines)
        let text: String = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(text.contains("link"), text)
        XCTAssertFalse(text.contains(String(0x5EC2E7)), text)
        XCTAssertTrue(text.contains("\"format\" : \"org.projectmios.midi-profile\""), text)
        XCTAssertEqual(data, MIDIProfileDocument.encode(name: linked.name, lines: linked.lines), "deterministic")
        XCTAssertEqual(MIDIProfileDocument.fileName(for: "Launch/Control: A"), "Launch-Control- A.pmmidi")
        XCTAssertEqual(MIDIProfileDocument.fileName(for: "..."), "MIDI Profile.pmmidi")
    }

    // MARK: S2 — refusals

    private func expectRefusal(_ data: Data, _ expected: MIDIProfileImportError, file: StaticString = #filePath, line: UInt = #line) {
        do {
            _ = try MIDIProfileDocument.decode(data)
            XCTFail("accepted", file: file, line: line)
        } catch {
            XCTAssertEqual(error, expected, file: file, line: line)
            XCTAssertFalse(error.message.isEmpty, file: file, line: line)
        }
    }

    private func json(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object)
    }

    func testMalformedDocumentsAreRefused() throws {
        let format: String = MIDIProfileDocument.format
        expectRefusal(Data(), .empty)
        expectRefusal(Data("cc:0:7=effect.bloom.intensity".utf8), .notAProfile)
        expectRefusal(try json(["format": "something.else", "version": 1, "name": "A", "lines": []]), .notAProfile)
        expectRefusal(try json(["version": 1, "name": "A", "lines": []]), .notAProfile)
        expectRefusal(try json(["format": format, "version": 2, "name": "A", "lines": []]), .newerVersion(2))
        expectRefusal(try json(["format": format, "version": 0, "name": "A", "lines": []]), .notAProfile)
        expectRefusal(try json(["format": format, "version": 1, "lines": []]), .missingName)
        expectRefusal(try json(["format": format, "version": 1, "name": " \u{7} ", "lines": []]), .missingName)
        expectRefusal(try json(["format": format, "version": 1, "name": "A"]), .missingLines)
        expectRefusal(try json(["format": format, "version": 1, "name": "A", "lines": [1, 2]]), .notAProfile)
        expectRefusal(try json(["format": format, "version": 1, "name": "A", "lines": ["cc:0:7=x\ncc:0:8=y"]]), .controlCharacters(index: 0))
        let long: String = "cc:0:7=" + String(repeating: "x", count: 250)
        expectRefusal(try json(["format": format, "version": 1, "name": "A", "lines": ["cc:0:1=a", long]]), .lineTooLong(index: 1))
        let many: [String] = (0..<513).map { (index: Int) -> String in "x" + String(index) }
        expectRefusal(try json(["format": format, "version": 1, "name": "A", "lines": many]), .tooManyLines(513))
        var huge = Data(MIDIProfileDocument.encode(name: "A", lines: []))
        huge.append(Data(repeating: 0x20, count: MIDIProfileLimits.maxImportBytes))
        expectRefusal(huge, .tooLarge)
        // An unknown top-level field is ignored; a version-1 file reads.
        let extra = try json(["format": format, "version": 1, "name": "A", "lines": ["cc:0:7=effect.bloom.intensity"], "future": true])
        XCTAssertEqual(try MIDIProfileDocument.decode(extra).lines, ["cc:0:7=effect.bloom.intensity"])
    }

    func testUnreadableStoreFilesAreReportedAndNeverOverwritten() throws {
        let directory: URL = try temporaryDirectory()
        let store = MIDIProfileFileStore(directory: directory)
        XCTAssertEqual(try store.load().get(), MIDIProfileList(), "no file: empty")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: store.fileURL)
        XCTAssertEqual(store.load().failure, .notAProfile)
        let newer = try json(["format": MIDIProfileList.format, "version": 3, "profiles": []])
        try newer.write(to: store.fileURL)
        XCTAssertEqual(store.load().failure, .newerVersion(3))
        let badLine = try json(["format": MIDIProfileList.format, "version": 1,
                                "profiles": [["id": "A", "name": "A", "lines": ["a\u{0}b"]]]])
        try badLine.write(to: store.fileURL)
        XCTAssertEqual(store.load().failure, .controlCharacters(index: 0))
    }

    // MARK: T12 — names, limits, links, suggestion

    func testNamesAndLimits() throws {
        var list = MIDIProfileList()
        let first: MIDIProfile = try list.saveCurrent([], id: "1")
        XCTAssertEqual(first.name, "Profile 1")
        XCTAssertEqual(try list.saveCurrent([], id: "2").name, "Profile 2")
        XCTAssertEqual(list.rename(id: "1", to: "  Launch\u{9}Control  "), "LaunchControl")
        XCTAssertEqual(list.rename(id: "1", to: "   "), "LaunchControl", "an empty name keeps the old one")
        XCTAssertEqual(list.rename(id: "2", to: "launchcontrol"), "launchcontrol (2)", "unique, ignoring case")
        XCTAssertEqual(try list.saveCurrent([], id: "3").name, "Profile 1", "the lowest free number")
        let longName: String = String(repeating: "N", count: 80)
        XCTAssertEqual(list.rename(id: "3", to: longName)?.count, 60)
        XCTAssertEqual(try list.add(name: longName, lines: [], id: "4").name.count, 60)
        XCTAssertTrue(try XCTUnwrap(list.profile(id: "4")).name.hasSuffix(" (2)"))
        XCTAssertNotNil(list.delete(id: "4"))
        XCTAssertNil(list.delete(id: "4"))
        while !list.isFull { try list.saveCurrent([], id: UUID().uuidString) }
        XCTAssertEqual(list.profiles.count, 32)
        XCTAssertThrowsError(try list.saveCurrent([], id: "x")) { (error: any Error) in
            XCTAssertEqual(error as? MIDIProfileImportError, .storeFull)
            XCTAssertEqual((error as? MIDIProfileImportError)?.message, "No more profiles fit (32). Delete one first.")
        }
    }

    func testDuplicateImportIsReported() throws {
        var list = MIDIProfileList()
        try list.add(name: "Pads", lines: ["note:0:36=cue.next"], id: "A")
        let report = MIDIProfileReport(lines: ["note:0:36=cue.next"], existing: list.profiles)
        XCTAssertEqual(report.duplicateOf, "Pads")
        XCTAssertEqual(report.summary, "1 note trigger. Same mappings as “Pads”.")
        XCTAssertEqual(try list.add(name: "Pads", lines: ["note:0:36=cue.next"], id: "B").name, "Pads (2)")
    }

    func testLinksAndTheSuggestion() throws {
        var list = MIDIProfileList()
        try list.add(name: "Keys", lines: ["cc:0:7=effect.bloom.intensity"], id: "K")
        try list.add(name: "Pads", lines: ["note:0:36=cue.next"], id: "P")
        XCTAssertFalse(list.setLink(.fallback(hash: 1, ordinal: 0), for: "K"), "fallback IDs are never stored")
        XCTAssertNil(list.profile(id: "K")?.link)
        XCTAssertTrue(list.setLink(.unique(42), for: "K"))
        XCTAssertTrue(list.setLink(.unique(43), for: "P"))
        XCTAssertNil(list.suggestion(listed: [], current: []))
        XCTAssertEqual(list.suggestion(listed: [.unique(42), .unique(43)], current: [])?.id, "K", "list order")
        XCTAssertEqual(list.suggestion(listed: [.unique(42), .unique(43)], current: ["cc:0:7=effect.bloom.intensity"])?.id, "P",
                       "a profile already in use is not suggested")
        XCTAssertNil(list.suggestion(listed: [.unique(42)], current: ["cc:0:7=effect.bloom.intensity"]))
        XCTAssertTrue(list.setLink(nil, for: "K"))
        XCTAssertNil(list.suggestion(listed: [.unique(42)], current: []))
    }

    func testInUseComparesBytes() {
        let composed = "note:0:1=cue.go:\u{E9}"          // é precomposed
        let decomposed = "note:0:1=cue.go:e\u{301}"      // e + combining acute
        XCTAssertEqual(composed, decomposed, "Swift strings compare canonically")
        XCTAssertFalse(MIDIProfile.sameBytes([composed], [decomposed]), "profiles compare bytes")
        XCTAssertTrue(MIDIProfile.sameBytes([composed], [composed]))
    }
}

private enum ParameterIDFixture {
    static let intensity = ParameterID("effect.bloom.intensity")
    static let radius = ParameterID("effect.bloom.radius")
}

private extension Result {
    var failure: Failure? {
        if case let .failure(error) = self { return error }
        return nil
    }
}
