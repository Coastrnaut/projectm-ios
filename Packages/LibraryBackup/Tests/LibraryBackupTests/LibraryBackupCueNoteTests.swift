// LibraryBackupCueNoteTests.swift — SHOW-012-T05 (specs/285-show-012-cue-annotations; R4, S1; contract
// show-cue-note.md N5): the FILE-005 library backup carries the show's cue notes; restoring it into an empty library
// (exact mode) gives every note back, byte for byte, and the show file identical to the source's.
import Foundation
import ShowControl
import ShowStorage
import XCTest
@testable import LibraryBackup

final class LibraryBackupCueNoteTests: XCTestCase {
    private static let notes = ["Wait for the count-in.\nThen \"go\" 🎛️", "Strobe off here — café ✨"]

    func testABackupAndExactRestoreKeepEveryCueNote() throws {
        let source = BackupFixtures.sandbox(self, "source")
        try BackupFixtures.populate(source)
        let store = ShowStore(directory: source.url(.show))
        var list = store.load().list
        for (index, note) in Self.notes.enumerated() {
            XCTAssertEqual(try list.setOperatorNote(list.cues[index].id, to: note), note)
        }
        try store.save(list)
        let sourceShow = try Data(contentsOf: store.showFile)

        let backup = try BackupFixtures.backup(of: source)
        let fresh = BackupFixtures.sandbox(self, "fresh")
        let outcome = try BackupFixtures.restore(backup, into: fresh, sink: BackupFixtures.SettingsSink())
        guard case .restored = outcome else { return XCTFail("not restored: \(outcome)") }

        let restoredStore = ShowStore(directory: fresh.url(.show))
        let restored = restoredStore.load().list
        XCTAssertEqual(restored.cues.map(\.operatorNote), [Self.notes[0], Self.notes[1], nil])
        for (index, note) in Self.notes.enumerated() {
            XCTAssertEqual(Array(restored.cues[index].operatorNote?.utf8 ?? "".utf8), Array(note.utf8), "byte-identical note")
        }
        XCTAssertEqual(try Data(contentsOf: restoredStore.showFile), sourceShow, "the show file comes back identical")
    }
}
