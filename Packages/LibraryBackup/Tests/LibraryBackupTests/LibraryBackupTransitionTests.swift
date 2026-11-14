// LibraryBackupTransitionTests.swift — SCN-007-T07 (SCN-007-R10, S4): FILE-005 re-encodes show.json through
// the show model, so the full backup carries every cue transition, and an exact restore into a fresh sandbox
// gives the same transitions (bit-identical durations, equal curves) and the same show bytes.
import Foundation
import ShowControl
import ShowStorage
import XCTest
@testable import LibraryBackup

final class LibraryBackupTransitionTests: XCTestCase {
    func testABackupRoundTripKeepsEveryTransition() throws {
        let source = BackupFixtures.sandbox(self, "source")
        try BackupFixtures.populate(source)
        let store = ShowStore(directory: source.url(.show))
        var list = store.load().list
        XCTAssertGreaterThanOrEqual(list.cues.count, 2)
        let first = try ShowCueTransition(type: .crossfade, durationSeconds: 0.1 + 0.2)
        let second = try ShowCueTransition(type: .unknown("wipeLeft"), durationSeconds: 2.5)
        try list.setTransition(list.cues[0].id, to: first)
        try list.setTransition(list.cues[1].id, to: second)
        try store.save(list)

        let backup = try BackupFixtures.backup(of: source)
        let fresh = BackupFixtures.sandbox(self, "fresh")
        let outcome = try BackupFixtures.restore(backup, into: fresh, sink: BackupFixtures.SettingsSink())
        guard case .restored = outcome else { return XCTFail("not restored: \(outcome)") }

        let restored = ShowStore(directory: fresh.url(.show)).load()
        XCTAssertNil(restored.refusal)
        XCTAssertEqual(restored.list.cues[0].transition, first)
        XCTAssertEqual(restored.list.cues[0].transition?.durationSeconds.bitPattern, first.durationSeconds.bitPattern)
        XCTAssertEqual(restored.list.cues[1].transition, second, "an unknown type survives the backup")
        XCTAssertEqual(try Data(contentsOf: ShowStore(directory: fresh.url(.show)).showFile), list.encoded())
    }
}
