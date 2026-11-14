// CMP-012-T03: the plain-Swift solo/mute overlay (CMP-012-R2 to R5; research CMP-012-D2, D3). CPU only:
// runs on every host and in the Linux shape.
import Compositor
import XCTest

final class LayerSoloMuteTests: XCTestCase {
    private static let kind = LayerKind("cmp012.plain")

    /// Five layers; layers 1 and 2 (0-based) form group G.
    private func fixture() throws -> (LayerStack, [LayerInstanceID], LayerGroupID) {
        var s = LayerStack()
        var ids: [LayerInstanceID] = []
        for _ in 0..<5 { ids.append(try s.add(LayerDescriptor(kind: Self.kind))) }
        let g = try s.makeGroup([ids[1], ids[2]], settings: LayerGroupSettings(name: "G"))
        return (s, ids, g)
    }

    func testAnEmptyOverlayLetsEveryLayerThrough() throws {
        let (s, ids, _) = try fixture()
        let o = LayerSoloMute()
        XCTAssertTrue(o.isEmpty)
        XCTAssertFalse(o.isSoloActive(in: s))
        XCTAssertEqual(o.hiddenLayers(in: s), [])
        XCTAssertEqual(o.visibleLayers(in: s), ids)
    }

    func testSoloIsolatesAndSolosCombineAsAUnion() throws {
        let (s, ids, _) = try fixture()
        var o = LayerSoloMute()
        o.setSolo(true, layer: ids[3])
        XCTAssertTrue(o.isSoloActive(in: s))
        XCTAssertEqual(o.visibleLayers(in: s), [ids[3]])
        o.setSolo(true, layer: ids[0])
        XCTAssertEqual(o.visibleLayers(in: s), [ids[0], ids[3]], "union, stack order")
        o.setSolo(false, layer: ids[0])
        o.setSolo(false, layer: ids[3])
        XCTAssertEqual(o.visibleLayers(in: s), ids)
        XCTAssertTrue(o.isEmpty)
    }

    func testMuteHidesAndWinsOverSoloWhileTheSoloStaysActive() throws {
        let (s, ids, _) = try fixture()
        var o = LayerSoloMute()
        o.setMute(true, layer: ids[4])
        XCTAssertEqual(o.visibleLayers(in: s), Array(ids[0..<4]))
        o.setSolo(true, layer: ids[4])
        XCTAssertTrue(o.isMuted(layer: ids[4]) && o.isSoloed(layer: ids[4]))
        XCTAssertTrue(o.isSoloActive(in: s), "a muted solo still counts")
        XCTAssertEqual(o.visibleLayers(in: s), [], "mute wins; the other layers stay hidden")
        o.setSolo(true, layer: ids[0])
        XCTAssertEqual(o.visibleLayers(in: s), [ids[0]])
    }

    func testGroupSoloChildSoloAndGroupMute() throws {
        let (s, ids, g) = try fixture()
        var groupSolo = LayerSoloMute()
        groupSolo.setSolo(true, group: g)
        XCTAssertEqual(groupSolo.visibleLayers(in: s), [ids[1], ids[2]])
        groupSolo.setMute(true, layer: ids[2])
        XCTAssertEqual(groupSolo.visibleLayers(in: s), [ids[1]], "a member's own mute still wins")

        var childSolo = LayerSoloMute()
        childSolo.setSolo(true, layer: ids[2])
        XCTAssertEqual(childSolo.visibleLayers(in: s), [ids[2]], "only that child of the group")

        var groupMute = LayerSoloMute()
        groupMute.setMute(true, group: g)
        XCTAssertEqual(groupMute.visibleLayers(in: s), [ids[0], ids[3], ids[4]])
        groupMute.setSolo(true, layer: ids[1])
        XCTAssertEqual(groupMute.visibleLayers(in: s), [], "group mute wins over a child solo")
    }

    func testASwitchedOffGroupStaysHiddenUnderSolo() throws {
        var (s, ids, g) = try fixture()
        try s.setGroupSettings(LayerGroupSettings(isEnabled: false), of: g)
        var o = LayerSoloMute()
        o.setSolo(true, layer: ids[1])
        XCTAssertTrue(o.lets(try XCTUnwrap(s.entry(ids[1])), in: s), "the overlay lets it through …")
        XCTAssertEqual(o.visibleLayers(in: s), [], "… but solo never overrides a saved enable flag")
        o.setSolo(true, group: g)
        XCTAssertEqual(o.visibleLayers(in: s), [])
    }

    func testASoloOnAnEmptyLayerKeepsSoloActive() throws {
        var (s, ids, _) = try fixture()
        try s.setSettings(LayerCompositeSettings(opacity: 0), of: ids[0])
        var o = LayerSoloMute()
        o.setSolo(true, layer: ids[0])
        XCTAssertTrue(o.isSoloActive(in: s))
        XCTAssertEqual(o.visibleLayers(in: s), [], "the performer sees that the soloed layer is empty")
    }

    func testStaleIDsAreIgnoredAndPruned() throws {
        var (s, ids, g) = try fixture()
        var o = LayerSoloMute()
        o.setSolo(true, layer: ids[4])
        o.setMute(true, group: g)
        try s.remove(ids[4])
        try s.ungroup(g)
        XCTAssertFalse(o.isSoloActive(in: s), "a removed layer's solo cannot black out the picture")
        XCTAssertEqual(o.visibleLayers(in: s), Array(ids[0..<4]))
        let tidy = o.pruned(to: s)
        XCTAssertTrue(tidy.isEmpty)
        XCTAssertFalse(o.isEmpty, "pruned returns a copy")
        o.clear()
        XCTAssertEqual(o, LayerSoloMute())
    }

    /// CMP-012-R2: the overlay is a separate value; using it never changes the stack.
    func testTheOverlayNeverChangesTheStack() throws {
        let (s, ids, g) = try fixture()
        let before = s
        let beforeEntries = s.entries
        let beforeGroups = s.groups
        var o = LayerSoloMute()
        o.setSolo(true, layer: ids[0])
        o.setMute(true, layer: ids[3])
        o.setSolo(true, group: g)
        _ = o.visibleLayers(in: s)
        _ = o.hiddenLayers(in: s)
        _ = o.pruned(to: s)
        XCTAssertEqual(s, before)
        XCTAssertEqual(s.entries, beforeEntries)
        XCTAssertEqual(s.groups, beforeGroups)
        XCTAssertEqual(o.hiddenLayers(in: s), [ids[3], ids[4]])
    }
}
