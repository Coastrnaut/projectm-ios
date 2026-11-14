// MIDIEndpointModelTests.swift — MIDI-001 pure model: the stable-ID rule, ordering and on-screen names,
// the diff table and the coalescer (MIDI-001-R3-R6, R9; S2, S3, S5). Plain Swift, also in the Linux shape.
import XCTest
@testable import PerformanceControl

final class MIDIEndpointModelTests: XCTestCase {
    private func rec(_ id: Int32, _ direction: MIDIEndpointDirection, _ name: String, device: String = "",
                     offline: Bool = false, virtual: Bool = false,
                     transport: MIDIEndpointTransport = .local) -> MIDIEndpointRecord {
        MIDIEndpointRecord(uniqueID: id, direction: direction, displayName: name, endpointName: name,
                           entityName: device, deviceName: device, isOffline: offline, isVirtual: virtual,
                           transport: transport)
    }

    // MARK: Stable IDs (R3, R4)

    func testSystemNumberIsTheIDWhenNonZeroAndUnique() {
        let ids: [MIDIEndpointID] = MIDIEndpointIdentity.assign([rec(11, .source, "A"), rec(12, .destination, "A")])
        XCTAssertEqual(ids, [.system(11), .system(12)])
        XCTAssertEqual(ids[0].description, "midi:11")
        XCTAssertFalse(ids[0].isFallback)
    }

    func testZeroAndSharedNumbersFallBackAndStayDistinct() {
        let records: [MIDIEndpointRecord] = [
            rec(0, .source, "Keys", device: "Keys"),
            rec(7, .source, "Pad", device: "Pad"),
            rec(7, .source, "Pad", device: "Pad"),     // shared number: both move to the fallback
            rec(8, .source, "Solo"),
        ]
        let ids: [MIDIEndpointID] = MIDIEndpointIdentity.assign(records)
        XCTAssertTrue(ids[0].isFallback)
        XCTAssertTrue(ids[1].isFallback)
        XCTAssertTrue(ids[2].isFallback)
        XCTAssertEqual(ids[3], .system(8))
        XCTAssertEqual(Set(ids).count, 4, "every endpoint has its own ID")
        if case let .fallback(h1, o1) = ids[1], case let .fallback(h2, o2) = ids[2] {
            XCTAssertEqual(h1, h2, "identical names hash alike")
            XCTAssertEqual([o1, o2], [0, 1], "ordinals in enumeration order")
        } else {
            XCTFail("expected fallbacks")
        }
    }

    func testFallbackHashIsDeterministicAndNameBased() {
        let a: MIDIEndpointRecord = rec(0, .source, "Keys", device: "Keys")
        XCTAssertEqual(MIDIEndpointIdentity.fallbackHash(a), MIDIEndpointIdentity.fallbackHash(a))
        // FNV-1a 64 reference value of the empty string.
        XCTAssertEqual(MIDIEndpointIdentity.fnv1a64(""), 0xcbf2_9ce4_8422_2325)
        XCTAssertEqual(MIDIEndpointIdentity.fnv1a64("a"), 0xaf63_dc4c_8601_ec8c)
        let output: MIDIEndpointRecord = rec(0, .destination, "Keys", device: "Keys")
        XCTAssertNotEqual(MIDIEndpointIdentity.fallbackHash(a), MIDIEndpointIdentity.fallbackHash(output), "direction counts")
        let id: MIDIEndpointID = .fallback(hash: 0xab, ordinal: 2)
        XCTAssertEqual(id.description, "midi-fb:00000000000000ab-2")
    }

    // MARK: List order and names (R1, R2, R9)

    func testListOrderNetworkHiddenPlaceholderNames() {
        let list: MIDIEndpointList = MIDIEndpointList.make(from: [
            rec(5, .destination, "zeta"),
            rec(4, .source, "Beta"),
            rec(3, .source, "alpha"),
            rec(2, .source, "Session 1", transport: .network),
            rec(1, .destination, "  "),
            rec(6, .source, "BT Keys", transport: .bluetooth),
        ])
        let names: [String] = list.endpoints.map { (e: MIDIEndpoint) -> String in e.name }
        XCTAssertEqual(names, ["alpha", "Beta", "BT Keys", "MIDI output", "zeta"])
        XCTAssertNil(list.endpoint(.system(2)), "network endpoints are never listed")
        XCTAssertEqual(list.endpoint(.system(6))?.transport, .bluetooth)
    }

    func testIdenticalNamesGetDistinctIDsAndOnScreenNames() {
        let list: MIDIEndpointList = MIDIEndpointList.make(from: [
            rec(21, .source, "Keys", device: "Keys"), rec(22, .source, "Keys", device: "Keys"),
            rec(23, .destination, "Keys", device: "Keys"),
        ])
        XCTAssertEqual(Set(list.endpoints.map { (e: MIDIEndpoint) -> MIDIEndpointID in e.id }).count, 3)
        let names: [MIDIEndpointID: String] = list.displayNames
        XCTAssertEqual(names[.system(21)], "Keys")
        XCTAssertEqual(names[.system(22)], "Keys (2)")
        XCTAssertEqual(names[.system(23)], "Keys", "an output of the same name is not numbered against inputs")
    }

    // MARK: Diff table (R5, S5)

    func testDiffTable() {
        struct Row {
            let name: String
            let old: [MIDIEndpointRecord]
            let new: [MIDIEndpointRecord]
            let expected: [String]
        }
        let a: MIDIEndpointRecord = rec(1, .source, "A")
        let b: MIDIEndpointRecord = rec(2, .source, "B")
        let renamedA: MIDIEndpointRecord = rec(1, .source, "A2")
        let offlineA: MIDIEndpointRecord = rec(1, .source, "A", offline: true)
        let renamedOfflineA: MIDIEndpointRecord = rec(1, .source, "A2", offline: true)
        let rows: [Row] = [
            Row(name: "appeared", old: [a], new: [a, b], expected: ["appeared midi:2"]),
            Row(name: "disappeared", old: [a, b], new: [a], expected: ["disappeared midi:2"]),
            Row(name: "renamed", old: [a], new: [renamedA], expected: ["renamed midi:1 A→A2"]),
            Row(name: "online", old: [a], new: [offlineA], expected: ["online midi:1 false"]),
            Row(name: "renamed and online", old: [a], new: [renamedOfflineA],
                expected: ["renamed midi:1 A→A2", "online midi:1 false"]),
            Row(name: "unchanged", old: [a, b], new: [b, a], expected: []),
            Row(name: "swap", old: [a], new: [b], expected: ["disappeared midi:1", "appeared midi:2"]),
        ]
        for row in rows {
            let changes: [MIDIEndpointChange] = MIDIEndpointDiff.changes(from: .make(from: row.old), to: .make(from: row.new))
            XCTAssertEqual(changes.map(Self.describe), row.expected, row.name)
        }
    }

    static func describe(_ change: MIDIEndpointChange) -> String {
        switch change {
        case .appeared(let e): return "appeared " + e.id.description
        case .disappeared(let e): return "disappeared " + e.id.description
        case let .renamed(id, from, to): return "renamed " + id.description + " " + from + "→" + to
        case let .onlineChanged(id, isOnline): return "online " + id.description + " " + String(isOnline)
        }
    }

    // MARK: Coalescer (R6, S3)

    func testTenSignalsInOneBurstScheduleOneRefresh() {
        var gate = MIDIRefreshCoalescer()
        var schedules = 0
        for _ in 0..<10 where gate.signal() { schedules += 1 }
        XCTAssertEqual(schedules, 1)
        XCTAssertEqual(gate.absorbed, 9)
        gate.beginRefresh()
        XCTAssertTrue(gate.signal(), "a signal after the refresh starts schedules the next one")
        gate.reset()
        XCTAssertFalse(gate.isPending)
    }
}
