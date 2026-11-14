// CMP-011-T05: the plain-Swift group model (CMP-011-R1 to R5, R7; research CMP-011-D1 to D3). CPU
// only: runs on every host and in the Linux shape.
import Compositor
import XCTest

final class LayerGroupStackTests: XCTestCase {
    private static let kind = LayerKind("cmp011.plain")

    private func stack(_ count: Int) throws -> (LayerStack, [LayerInstanceID]) {
        var s = LayerStack()
        var ids: [LayerInstanceID] = []
        for _ in 0..<count { ids.append(try s.add(LayerDescriptor(kind: Self.kind))) }
        return (s, ids)
    }

    private func groupOf(_ s: LayerStack) -> [UInt64?] { s.entries.map { (e: LayerStackEntry) -> UInt64? in e.group?.rawValue } }

    // MARK: Operations

    func testMakeGroupAndUngroupKeepLocalSettings() throws {
        var (s, ids) = try stack(4)
        let local = try LayerTransform(translation: LayerPoint(x: 0.1, y: -0.2), uniformScale: 0.5, rotation: 0.3)
        try s.setSettings(LayerCompositeSettings(opacity: 0.7, blendMode: .screen, transform: local), of: ids[2])
        let before = s.entry(ids[2])
        let g = try s.makeGroup([ids[2], ids[1]], settings: LayerGroupSettings(name: "Logo", opacity: 0.5))
        XCTAssertEqual(groupOf(s), [nil, g.rawValue, g.rawValue, nil])
        XCTAssertEqual(s.members(of: g), [ids[1], ids[2]])
        XCTAssertEqual(s.group(g)?.settings.name, "Logo")
        let moved = try LayerTransform(translation: LayerPoint(x: 0.25, y: 0))
        try s.setGroupSettings(LayerGroupSettings(name: "Logo", opacity: 0.5, transform: moved), of: g)
        XCTAssertEqual(s.entry(ids[2])?.settings, before?.settings, "moving the group keeps the local transform")
        let removed = try s.ungroup(g)
        XCTAssertEqual(removed.settings.transform, moved)
        XCTAssertEqual(groupOf(s), [nil, nil, nil, nil])
        XCTAssertEqual(s.entry(ids[2])?.settings, before?.settings, "ungrouping bakes nothing in")
        XCTAssertTrue(s.groups.isEmpty)
    }

    func testRefusalsLeaveTheStackUnchanged() throws {
        var (s, ids) = try stack(4)
        let g = try s.makeGroup([ids[0], ids[1]])
        let snapshot = s
        XCTAssertThrowsError(try s.makeGroup([])) { XCTAssertEqual($0 as? LayerStackError, .emptyGroup(nil)) }
        XCTAssertThrowsError(try s.makeGroup([ids[1], ids[2]])) { XCTAssertEqual($0 as? LayerStackError, .layerAlreadyGrouped(ids[1])) }
        XCTAssertThrowsError(try s.makeGroup([ids[2], LayerInstanceID(rawValue: 99)])) {
            XCTAssertEqual($0 as? LayerStackError, .unknownLayer(LayerInstanceID(rawValue: 99)))
        }
        var (t, tids) = try stack(4)
        XCTAssertThrowsError(try t.makeGroup([tids[0], tids[2]])) { XCTAssertEqual($0 as? LayerStackError, .layersNotContiguous) }
        XCTAssertEqual(t.groups.count, 0)
        let unknown = LayerGroupID(rawValue: 42)
        XCTAssertThrowsError(try s.ungroup(unknown)) { XCTAssertEqual($0 as? LayerStackError, .unknownGroup(unknown)) }
        XCTAssertThrowsError(try s.setGroupSettings(LayerGroupSettings(), of: unknown))
        XCTAssertThrowsError(try s.moveGroup(g, to: 3)) {
            XCTAssertEqual($0 as? LayerStackError, .indexOutOfRange(index: 3, validRange: 0...2))
        }
        XCTAssertEqual(s, snapshot)
    }

    // MARK: Membership rule (research CMP-011-D2)

    func testInsertInsideARunJoinsAndAtItsEdgeDoesNot() throws {
        var (s, ids) = try stack(3)
        let g = try s.makeGroup([ids[0], ids[1]])
        try s.add(LayerDescriptor(kind: Self.kind), at: 1)
        XCTAssertEqual(groupOf(s), [g.rawValue, g.rawValue, g.rawValue, nil], "between two members: joins")
        try s.add(LayerDescriptor(kind: Self.kind), at: 3)
        XCTAssertEqual(groupOf(s), [g.rawValue, g.rawValue, g.rawValue, nil, nil], "above the run: stays ungrouped")
        try s.add(LayerDescriptor(kind: Self.kind), at: 0)
        XCTAssertEqual(groupOf(s).first, .some(nil), "below the run: stays ungrouped")
    }

    func testMovingOutLeavesAndMovingInJoins() throws {
        var (s, ids) = try stack(5)
        let g = try s.makeGroup([ids[0], ids[1], ids[2]])
        try s.move(ids[1], to: 4)
        XCTAssertEqual(s.entry(ids[1])?.group, nil, "moved out of its run: leaves")
        XCTAssertEqual(s.members(of: g), [ids[0], ids[2]])
        try s.move(ids[3], to: 1)
        XCTAssertEqual(s.entry(ids[3])?.group, g, "moved between two members: joins")
        try s.move(ids[0], to: 2)
        XCTAssertEqual(s.entry(ids[0])?.group, g, "reordered inside its run: stays")
        XCTAssertEqual(s.members(of: g).count, 3)
    }

    func testDuplicateJoinsAndRemovingTheLastMemberRemovesTheGroup() throws {
        var (s, ids) = try stack(3)
        let g = try s.makeGroup([ids[2]])
        let copy = try s.duplicate(ids[2])
        XCTAssertEqual(s.entry(copy)?.group, g)
        try s.remove(ids[2])
        XCTAssertEqual(s.groups.count, 1)
        try s.remove(copy)
        XCTAssertTrue(s.groups.isEmpty)
    }

    func testMovingAGroupLastMemberAloneKeepsItsSingletonGroup() throws {
        var (s, ids) = try stack(3)
        let g = try s.makeGroup([ids[0]])
        try s.move(ids[0], to: 2)
        XCTAssertEqual(s.entry(ids[0])?.group, g, "a one-member group is always one run")
    }

    func testMoveGroupMovesTheRunAndRefusesASplit() throws {
        var (s, ids) = try stack(5)
        let a = try s.makeGroup([ids[0], ids[1]])
        let b = try s.makeGroup([ids[3], ids[4]])
        try s.moveGroup(a, to: 3)
        XCTAssertEqual(s.ids, [ids[2], ids[3], ids[4], ids[0], ids[1]])
        XCTAssertEqual(s.groups.map(\.id), [b, a], "records follow the runs")
        let snapshot = s
        XCTAssertThrowsError(try s.moveGroup(a, to: 2)) { XCTAssertEqual($0 as? LayerStackError, .splitsGroup(b)) }
        XCTAssertEqual(s, snapshot)
        try s.moveGroup(a, to: 0)
        XCTAssertEqual(s.ids, [ids[0], ids[1], ids[2], ids[3], ids[4]])
    }

    // MARK: Restore

    func testRestoreValidatesGroups() throws {
        let kind = LayerDescriptor(kind: Self.kind)
        let g1 = LayerGroupID(rawValue: 7), g2 = LayerGroupID(rawValue: 9)
        func entry(_ id: UInt64, _ g: LayerGroupID?) -> LayerStackEntry {
            LayerStackEntry(id: LayerInstanceID(rawValue: id), descriptor: kind, group: g)
        }
        var s = try LayerStack(restoring: [entry(1, g1), entry(2, g1), entry(3, nil)], groups: [LayerGroup(id: g1)])
        XCTAssertEqual(s.members(of: g1).map(\.rawValue), [1, 2])
        let next = try s.makeGroup([LayerInstanceID(rawValue: 3)])
        XCTAssertEqual(next.rawValue, 8, "group IDs continue after the largest restored one")
        XCTAssertThrowsError(try LayerStack(restoring: [entry(1, g1)], groups: [LayerGroup(id: g1), LayerGroup(id: g1)])) {
            XCTAssertEqual($0 as? LayerStackError, .duplicateGroup(g1))
        }
        XCTAssertThrowsError(try LayerStack(restoring: [entry(1, g2)], groups: [LayerGroup(id: g1)])) {
            XCTAssertEqual($0 as? LayerStackError, .unknownGroup(g2))
        }
        XCTAssertThrowsError(try LayerStack(restoring: [entry(1, g1)], groups: [LayerGroup(id: g1), LayerGroup(id: g2)])) {
            XCTAssertEqual($0 as? LayerStackError, .emptyGroup(g2))
        }
        XCTAssertThrowsError(try LayerStack(restoring: [entry(1, g1), entry(2, nil), entry(3, g1)], groups: [LayerGroup(id: g1)])) {
            XCTAssertEqual($0 as? LayerStackError, .groupNotContiguous(g1))
        }
    }

    func testEqualityIncludesGroups() throws {
        var (a, ids) = try stack(2)
        let b = a
        try a.makeGroup([ids[0]])
        XCTAssertNotEqual(a, b)
    }

    // MARK: Composition (research CMP-011-D3)

    func testComposedMatrixAgainstHandValues() throws {
        let aspect: Double = 16.0 / 9.0
        let move = try LayerTransform(translation: LayerPoint(x: 0.25, y: -0.1))
        let local = try LayerTransform(translation: LayerPoint(x: 0.1, y: 0.2), uniformScale: 0.5)
        let m = LayerGroupComposition.matrix(group: move, local: local, aspect: aspect)
        // Local: scale 0.5 about (0.5, 0.5), then +(0.1, 0.2): x' = 0.5x + 0.35, y' = 0.5y + 0.45; group adds (0.25, −0.1).
        XCTAssertEqual(m.m00, 0.5, accuracy: 1e-12)
        XCTAssertEqual(m.m02, 0.6, accuracy: 1e-12)
        XCTAssertEqual(m.m12, 0.35, accuracy: 1e-12)
        // A group scaled 2× about the output centre doubles a child's offset from the centre.
        let zoom = try LayerTransform(uniformScale: 2)
        let p: LayerPoint = LayerGroupComposition.matrix(group: zoom, local: local, aspect: aspect).apply(LayerPoint(x: 0.5, y: 0.5))
        XCTAssertEqual(p.x, 0.5 + 2 * 0.1, accuracy: 1e-12)
        XCTAssertEqual(p.y, 0.5 + 2 * 0.2, accuracy: 1e-12)
        // A quarter turn about the centre on 16:9 keeps pixel lengths: (+0.1 w) → (+0.1 w in pixels) downwards.
        let turn = try LayerTransform(rotation: Double.pi / 2)
        let q: LayerPoint = LayerGroupComposition.matrix(group: turn, local: local, aspect: aspect).apply(LayerPoint(x: 0.5, y: 0.5))
        let dxPixels: Double = (q.x - 0.5) * 1920
        let dyPixels: Double = (q.y - 0.5) * 1080
        XCTAssertEqual(dxPixels, -0.2 * 1080, accuracy: 1e-9)
        XCTAssertEqual(dyPixels, 0.1 * 1920, accuracy: 1e-9)
    }

    func testIdentityGroupGivesTheLocalMatrixBitForBit() throws {
        let local = try LayerTransform(translation: LayerPoint(x: 0.13, y: -0.07), scale: LayerPoint(x: 0.7, y: 1.3), rotation: 0.41)
        let m = LayerGroupComposition.matrix(group: .identity, local: local, outputWidth: 96, outputHeight: 64)
        XCTAssertEqual(m, local.matrix(outputWidth: 96, outputHeight: 64))
    }

    func testIsolationRule() {
        XCTAssertFalse(LayerGroupComposition.needsIsolation(opacity: 1, modes: [LayerBlendMode.normal, .normal]))
        XCTAssertTrue(LayerGroupComposition.needsIsolation(opacity: 0.999, modes: [LayerBlendMode.normal]))
        XCTAssertTrue(LayerGroupComposition.needsIsolation(opacity: 1, modes: [LayerBlendMode.normal, .screen]))
        XCTAssertEqual(LayerGroupSettings(opacity: .nan).opacity, 1)
        XCTAssertEqual(LayerGroupSettings(opacity: 2).opacity, 1)
        XCTAssertEqual(LayerGroupSettings(opacity: -1).opacity, 0)
    }
}
