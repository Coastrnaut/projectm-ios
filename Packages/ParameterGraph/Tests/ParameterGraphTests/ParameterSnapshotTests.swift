// MOD-001-T13: snapshots keyed by ID, the hand-off to scene persistence and the rollback mechanism
// (MOD-001-R9; S5; contract C4).
import Foundation
import ParameterGraph
import XCTest

final class ParameterSnapshotTests: XCTestCase {
    private func changedStore() throws -> ParameterStore {
        let store = ParameterStore(registry: try makeStoreRegistry())
        try store.setDouble(0.25, for: "t.level")
        try store.setInt(8, for: "t.count")
        try store.setBool(true, for: "t.on")
        try store.setEnumCase("horizontal", for: "t.orientation")
        try store.setColor(ParameterColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.4), for: "t.tint")
        return store
    }

    func testJSONRoundTripRestoresEveryKind() throws {
        let source = try changedStore()
        let data = try source.snapshot().encodedJSON()
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.hasPrefix("{\"schemaVersion\":1,\"values\":{\"t.count\":{\"kind\":\"integer\",\"value\":8}"), text)
        XCTAssertEqual(try source.snapshot().encodedJSON(), data) // stable bytes

        let decoded = try JSONDecoder().decode(ParameterSnapshot.self, from: data)
        let target = ParameterStore(registry: try makeStoreRegistry())
        let report = target.restore(decoded)
        XCTAssertEqual(report.applied, ["t.count", "t.level", "t.odd", "t.on", "t.orientation", "t.tint"])
        XCTAssertTrue(report.orphaned.isEmpty && report.rejected.isEmpty && !report.unsupportedVersion)
        XCTAssertEqual(target.snapshot(), source.snapshot())
    }

    func testRestoreReportsOrphansRejectsAndClamps() throws {
        let store = ParameterStore(registry: try makeStoreRegistry())
        let snapshot = ParameterSnapshot(values: [
            "t.level": .continuous(7),             // clamped to 1
            "t.on": .continuous(1),                 // wrong kind
            "t.orientation": .enumeration("up"),    // unknown case
            "visual.gone.away": .boolean(true),     // orphaned
        ])
        let report = store.restore(snapshot)
        XCTAssertEqual(report.applied, ["t.level"])
        XCTAssertEqual(report.orphaned, ["visual.gone.away"])
        XCTAssertEqual(report.rejected.map(\.id), ["t.on", "t.orientation"])
        XCTAssertEqual(report.rejected.map(\.error), [.kindMismatch("t.on", expected: "boolean", got: "continuous"),
                                                      .unknownEnumCase("t.orientation", "up")])
        XCTAssertEqual(store.double("t.level"), 1)
        XCTAssertEqual(store.bool("t.on"), false)
        XCTAssertEqual(store.enumCase("t.orientation"), "vertical")
    }

    func testNewerSchemaIsRejectedWhole() throws {
        let store = ParameterStore(registry: try makeStoreRegistry())
        let report = store.restore(ParameterSnapshot(schemaVersion: ParameterSnapshot.currentSchemaVersion + 1,
                                                     values: ["t.level": .continuous(0.9)]))
        XCTAssertTrue(report.unsupportedVersion)
        XCTAssertTrue(report.applied.isEmpty)
        XCTAssertEqual(store.double("t.level"), 0.5)
        XCTAssertEqual(store.changeCount, 0)
    }

    func testRollbackRestoresAnEarlierSnapshot() throws {
        let store = try changedStore()
        let before = store.snapshot()
        try store.setDouble(0.9, for: "t.level")
        try store.setBool(false, for: "t.on")
        store.resetAll()
        XCTAssertNotEqual(store.snapshot(), before)
        _ = store.restore(before)
        XCTAssertEqual(store.snapshot(), before)
    }
}
