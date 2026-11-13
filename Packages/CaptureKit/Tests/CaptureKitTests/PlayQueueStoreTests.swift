// PlayQueueStoreTests.swift — `queue.json`, the stored queue (AUD-003-T02; AUD-003-R13, R14;
// data-model.md). Foundation only: runs on Linux too.
import Foundation
import XCTest
@testable import CaptureKit

final class PlayQueueStoreTests: XCTestCase {
    private var directory: URL!

    private let idA = "00000000-0000-0000-0000-00000000000A"
    private let idB = "00000000-0000-0000-0000-00000000000B"
    private let idC = "00000000-0000-0000-0000-00000000000C"

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("aud003-store-\(UUID().uuidString)",
                                                                                   isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private var fileURL: URL { directory.appendingPathComponent("queue.json") }
    private var damagedURL: URL { directory.appendingPathComponent("queue.damaged.json") }

    // MARK: - The record

    func testRoundTripUsesVersionOneSortedKeysAndOnlyIdentifiers() throws {
        let record = PlayQueueRecord(trackIDs: [idC, idA, idB], currentTrackID: idA)
        let data = try record.encoded()
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertEqual(text, #"{"currentTrackID":"\#(idA)","schemaVersion":1,"trackIDs":["\#(idC)","\#(idA)","\#(idB)"]}"#)
        XCTAssertEqual(try PlayQueueRecord.decode(data), .record(record))
    }

    func testNoCurrentTrackIsOmitted() throws {
        let record = PlayQueueRecord(trackIDs: [idA], currentTrackID: nil)
        let text = String(decoding: try record.encoded(), as: UTF8.self)
        XCTAssertFalse(text.contains("currentTrackID"))
        XCTAssertEqual(try PlayQueueRecord.decode(try record.encoded()), .record(record))
    }

    func testInvalidAndRepeatedEntriesAreDroppedAndIdentifiersAreCanonical() throws {
        let lower = idB.lowercased()
        let json = #"{"schemaVersion":1,"trackIDs":["\#(idA)","not-a-uuid",42,"\#(lower)","\#(idA)","/etc/passwd"],"currentTrackID":"nope"}"#
        XCTAssertEqual(try PlayQueueRecord.decode(Data(json.utf8)),
                       .record(PlayQueueRecord(trackIDs: [idA, idB], currentTrackID: nil)))
    }

    func testUnknownKeysAreIgnored() throws {
        let json = #"{"schemaVersion":1,"trackIDs":["\#(idA)"],"repeatMode":"all"}"#
        XCTAssertEqual(try PlayQueueRecord.decode(Data(json.utf8)), .record(PlayQueueRecord(trackIDs: [idA], currentTrackID: nil)))
    }

    func testANewerVersionIsReportedAndNothingElseIsRead() throws {
        XCTAssertEqual(try PlayQueueRecord.decode(Data(#"{"schemaVersion":2,"order":{}}"#.utf8)), .newerFormat(2))
    }

    func testNotARecordThrows() {
        XCTAssertThrowsError(try PlayQueueRecord.decode(Data("garbage".utf8)))
        XCTAssertThrowsError(try PlayQueueRecord.decode(Data(#"{"schemaVersion":0,"trackIDs":[]}"#.utf8)))
        XCTAssertThrowsError(try PlayQueueRecord.decode(Data(#"{"trackIDs":[]}"#.utf8)))
        XCTAssertThrowsError(try PlayQueueRecord.decode(Data(#"{"schemaVersion":1}"#.utf8)))
    }

    // MARK: - The store

    func testAMissingFileIsMissing() {
        XCTAssertEqual(PlayQueueStore(directory: directory).load(), .missing)
    }

    func testSaveThenLoad() throws {
        let store = PlayQueueStore(directory: directory)
        let record = PlayQueueRecord(trackIDs: [idB, idA], currentTrackID: idB)
        try store.save(record)
        XCTAssertEqual(store.load(), .record(record))
        XCTAssertEqual(PlayQueueStore(directory: directory).load(), .record(record), "a new store over the same folder")
    }

    func testSaveCreatesTheFolder() throws {
        let nested = directory.appendingPathComponent("AudioLibrary", isDirectory: true)
        let store = PlayQueueStore(directory: nested)
        try store.save(PlayQueueRecord(trackIDs: [idA], currentTrackID: nil))
        XCTAssertEqual(store.load(), .record(PlayQueueRecord(trackIDs: [idA], currentTrackID: nil)))
    }

    func testADamagedFileIsKeptAsideAndReportedOnce() throws {
        try Data("{ not json".utf8).write(to: fileURL)
        let store = PlayQueueStore(directory: directory)
        XCTAssertEqual(store.load(), .damaged)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertEqual(try Data(contentsOf: damagedURL), Data("{ not json".utf8))
        XCTAssertEqual(store.load(), .missing)
    }

    func testAnOversizedFileIsDamaged() throws {
        try Data(repeating: 0x20, count: PlayQueueStore.maxFileBytes + 1).write(to: fileURL)
        XCTAssertEqual(PlayQueueStore(directory: directory).load(), .damaged)
    }

    func testANewerFileIsLeftByteForByte() throws {
        let newer = Data(#"{"schemaVersion":7,"whatever":[1,2,3]}"#.utf8)
        try newer.write(to: fileURL)
        XCTAssertEqual(PlayQueueStore(directory: directory).load(), .newerFormat(7))
        XCTAssertEqual(try Data(contentsOf: fileURL), newer)
        XCTAssertFalse(FileManager.default.fileExists(atPath: damagedURL.path))
    }

    func testAFailedWriteLeavesThePreviousFile() throws {
        let good = PlayQueueStore(directory: directory)
        let first = PlayQueueRecord(trackIDs: [idA, idB], currentTrackID: nil)
        try good.save(first)
        struct DiskFull: Error {}
        let failing = PlayQueueStore(directory: directory, writer: { _, _ in throw DiskFull() })
        XCTAssertThrowsError(try failing.save(PlayQueueRecord(trackIDs: [idC], currentTrackID: nil)))
        XCTAssertEqual(good.load(), .record(first))
    }
}
