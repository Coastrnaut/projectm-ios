// SceneSnapshotTests.swift — SCN-008-T05 (US2; SCN-008-R2 to R4, R6, R7, S2 to S4; contract N1 to N7): the optional
// `snapshots` list in the scene document, its warnings, editing and the recall plan. CPU only, runs on Linux.
import Foundation
import ParameterGraph
@testable import SceneFormat
import VisualParameters
import XCTest

final class SceneSnapshotTests: XCTestCase {
    private var registry: ParameterRegistry!

    override func setUpWithError() throws {
        registry = try SceneFixtures.registry()
    }

    private static let s1 = #"{"name":"S1","note":"keep me","values":{"effect.bloom.intensity":{"kind":"continuous","value":0.2},"effect.bloom.radius":{"kind":"continuous","value":0.05}}}"#

    private func decode(snapshotsJSON: String) throws -> SceneDocument {
        let text = SceneFixtures.minimalText.dropLast() + ",\"snapshots\":" + snapshotsJSON + "}"
        return try SceneDocument.decode(Array(text.utf8)).document
    }

    private static func entry(_ name: String) -> String { #"{"name":""# + name + #"","values":{}}"# }

    func testSnapshotsRoundTripByteIdenticallyAndReadExactly() throws {
        let document = try decode(snapshotsJSON: "[" + Self.s1 + "]")
        let bytes = document.encoded()
        let again = try SceneDocument.decode(bytes).document
        XCTAssertEqual(again, document)
        XCTAssertEqual(again.encoded(), bytes, "decode → encode is byte-identical")
        XCTAssertEqual(again.snapshots?.first?.fields["note"], .string("keep me"), "unknown entry fields are kept")
        let snapshot = try XCTUnwrap(again.usableSnapshots.first ?? nil)
        XCTAssertEqual(snapshot.name, "S1")
        XCTAssertEqual(snapshot.values[VisualParameterIDs.bloomIntensity], .continuous(0.2))
        XCTAssertEqual(snapshot.values[VisualParameterIDs.bloomRadius], .continuous(0.05))
        XCTAssertTrue(again.validate(registry: registry).isEmpty, "\(again.validate(registry: registry))")
        // Live state and capture carry the list unchanged.
        let live = try again.liveState(registry: registry).state
        XCTAssertEqual(live.snapshots, again.snapshots)
        let saved = try SceneDocument(capturing: live, id: again.id, name: again.name)
        XCTAssertEqual(saved.encoded(), bytes)
        // A snapshot written by the model reads back equal.
        let written = SceneSnapshotEntry(snapshot)
        XCTAssertEqual(SceneSnapshotEntry.read([written]).snapshots, [snapshot])
    }

    func testSceneWithoutSnapshotsEncodesUnchanged() throws {
        let bytes = Array(SceneFixtures.minimalText.utf8)
        let document = try SceneDocument.decode(bytes).document
        XCTAssertNil(document.snapshots)
        XCTAssertEqual(document.encoded(), bytes)
        XCTAssertTrue(document.usableSnapshots.isEmpty)
    }

    func testUnusableEntriesAndUnknownParametersAreReportedAndKept() throws {
        let entries: [String] = [
            #"{"values":{}}"#,                                                       // missing name
            #"{"name":"A","values":[]}"#,                                            // values not an object
            #"{"name":"B","values":{"effect.bloom.radius":{"kind":"continuous","value":"x"}}}"#,   // malformed value
            #"{"name":"C","values":{"effect.bloom.radius":{"kind":"continuous","value":0.03},"effect.future.size":{"kind":"continuous","value":1}}}"#,
        ]
        let document = try decode(snapshotsJSON: "[" + entries.joined(separator: ",") + "]")
        let issues = document.validate(registry: registry)
        XCTAssertEqual(issues.map(\.code), [.invalidSnapshot, .invalidSnapshot, .invalidSnapshot, .unknownSnapshotParameter])
        XCTAssertEqual(issues.map(\.path), ["$.snapshots[0].name", "$.snapshots[1].values",
                                            ScenePath.key("$.snapshots[2].values", "effect.bloom.radius"),
                                            ScenePath.key("$.snapshots[3].values", "effect.future.size")])
        XCTAssertTrue(issues.allSatisfy { (issue: SceneIssue) -> Bool in !issue.isError }, "warnings only")
        XCTAssertEqual(document.usableSnapshots.map { (s: SceneSnapshot?) -> Bool in s != nil }, [false, false, false, true])
        // The scene loads and saves the list back verbatim; the repair report lists both codes.
        let live = try document.liveState(registry: registry).state
        XCTAssertEqual(live.snapshots, document.snapshots)
        let report = SceneRepairReport(document: document, decodeWarnings: [], registry: registry)
        XCTAssertTrue(report.entries.contains { (e: SceneRepairReport.Entry) -> Bool in e.code == "invalidSnapshot" && e.item == "Snapshot 2 (\"A\")" })
        XCTAssertTrue(report.entries.contains { (e: SceneRepairReport.Entry) -> Bool in e.code == "unknownSnapshotParameter" })
        // Recall plan: the unknown ID is skipped and reported, the known one written.
        let c = try XCTUnwrap(document.usableSnapshots[3])
        let plan = SceneSnapshotRecallPlan(c, registry: registry, settable: { (_: ParameterID) -> Bool in true })
        XCTAssertEqual(plan.writes, [SceneSnapshotRecallPlan.Write(id: VisualParameterIDs.bloomRadius, value: .continuous(0.03))])
        XCTAssertEqual(plan.skipped, [SceneSnapshotRecallPlan.Skip(id: "effect.future.size", reason: .unknownParameter)])
    }

    func testRecallPlanSkipsUnsettableAndRejectedValuesAndClamps() throws {
        let snapshot = SceneSnapshot(name: "S", values: [
            VisualParameterIDs.bloomIntensity: .continuous(7),      // clamped to 1
            VisualParameterIDs.bloomRadius: .boolean(true),         // wrong kind: rejected
            VisualParameterIDs.bloomKnee: .continuous(0.1),         // known, no app control
        ])
        let plan = SceneSnapshotRecallPlan(snapshot, registry: registry,
                                           settable: { (id: ParameterID) -> Bool in id != VisualParameterIDs.bloomKnee })
        XCTAssertEqual(plan.writes, [SceneSnapshotRecallPlan.Write(id: VisualParameterIDs.bloomIntensity, value: .continuous(1))])
        XCTAssertEqual(plan.skipped.map(\.id), [VisualParameterIDs.bloomKnee, VisualParameterIDs.bloomRadius].sorted())
        XCTAssertTrue(plan.skipped.contains(SceneSnapshotRecallPlan.Skip(id: VisualParameterIDs.bloomKnee, reason: .notSettable)))
    }

    func testLimitsAndEditing() throws {
        // Seventeen stored entries: the 17th is kept but not used.
        let seventeen = try decode(snapshotsJSON: "[" + (1...17).map { (n: Int) -> String in Self.entry("S\(n)") }.joined(separator: ",") + "]")
        XCTAssertEqual(seventeen.usableSnapshots.count, 17)
        XCTAssertNil(seventeen.usableSnapshots[16])
        XCTAssertEqual(seventeen.validate(registry: registry).map(\.path), ["$.snapshots[16]"])
        XCTAssertEqual(try SceneDocument.decode(seventeen.encoded()).document.snapshots?.count, 17, "kept for re-save")
        // More than 64 entries refuse the file.
        let many: String = Array(repeating: Self.entry("X"), count: 65).joined(separator: ",")
        let text: String = String(SceneFixtures.minimalText.dropLast()) + ",\"snapshots\":[" + many + "]}"
        XCTAssertThrowsError(try SceneDocument.decode(Array(text.utf8))) { (error: any Error) in
            XCTAssertEqual(error as? SceneDecodeError, .tooMany(what: "snapshots", count: 65, limit: SceneLimits.maximumSnapshotEntries))
        }
        // Save refuses a 17th; names are trimmed, 1…64 characters and unique.
        var entries: [SceneSnapshotEntry] = []
        for n in 1...16 {
            let name = SceneSnapshotEditing.nextDefaultName(in: entries)
            XCTAssertEqual(name, "Snapshot \(n)")
            entries = try SceneSnapshotEditing.adding(SceneSnapshot(name: name, values: [:]), to: entries)
        }
        XCTAssertThrowsError(try SceneSnapshotEditing.adding(SceneSnapshot(name: "Extra", values: [:]), to: entries)) { (error: any Error) in
            XCTAssertEqual(error as? SceneSnapshotEditError, .limitReached)
        }
        entries = try SceneSnapshotEditing.removing(at: 1, from: entries)
        XCTAssertEqual(SceneSnapshotEditing.nextDefaultName(in: entries), "Snapshot 2", "the smallest unused number")
        entries = try SceneSnapshotEditing.renaming(at: 0, to: "  Drop  ", in: entries)
        XCTAssertEqual(entries[0].name, "Drop")
        for bad in ["", "   ", String(repeating: "x", count: 65)] {
            XCTAssertThrowsError(try SceneSnapshotEditing.renaming(at: 0, to: bad, in: entries)) { (error: any Error) in
                XCTAssertEqual(error as? SceneSnapshotEditError, .invalidName)
            }
        }
        XCTAssertThrowsError(try SceneSnapshotEditing.renaming(at: 0, to: "snapshot 3", in: entries)) { (error: any Error) in
            XCTAssertEqual(error as? SceneSnapshotEditError, .duplicateName)
        }
        // Rename keeps an entry's other fields.
        let kept = try SceneSnapshotEditing.renaming(at: 0, to: "S9", in: try decode(snapshotsJSON: "[" + Self.s1 + "]").snapshots ?? [])
        XCTAssertEqual(kept[0].fields["note"], .string("keep me"))
        XCTAssertEqual(SceneSnapshotEntry.recallActionID, "scene.snapshot.recall")
    }
}
