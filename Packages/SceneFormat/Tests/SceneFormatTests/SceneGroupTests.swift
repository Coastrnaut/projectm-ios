// CMP-011-T14 (US4; CMP-011-S4, R11, R12): the scene format stores layer groups as the optional top-level
// `groups`, written only when set; valid groups reach the live stack with every child's own transform
// unchanged; damaged groups are warnings (`invalidGroup`), drawn ungrouped, kept verbatim, listed by the
// repair report with `repairGroups`. CPU only, runs on Linux.
import Compositor
import Foundation
import ParameterGraph
@testable import SceneFormat
import XCTest

final class SceneGroupTests: XCTestCase {
    // SceneFixtures.allKinds() layers by index: 0 camera #1, 1 spectrum #2, 2 photo #9, 3 video #10,
    // 4 text #11, 5 material #12, 6 graph #13, 7 unknown kind #40.

    private static func moved() throws -> LayerTransform {
        try LayerTransform(translation: LayerPoint(x: 0.25, y: -0.125), scale: LayerPoint(x: 0.75, y: 1.5), rotation: 0.3,
                           anchor: LayerPoint(x: 0.4, y: 0.6))
    }

    private func scene(_ groups: [SceneGroup]) throws -> SceneDocument {
        var document = try SceneFixtures.allKinds()
        document.groups = groups
        return document
    }

    private func grouped() throws -> SceneDocument {
        try scene([
            SceneGroup(id: 3, name: "Media", opacity: 1, transform: try Self.moved(), children: [.layer(9), .layer(10)]),
            SceneGroup(id: 7, name: "Overlay", enabled: false, opacity: 0.5, children: [.layer(11), .layer(12)],
                       extra: ["futureBlend": .string("multiply")]),
        ])
    }

    private func text(_ document: SceneDocument) -> String { String(decoding: document.encoded(), as: UTF8.self) }

    // MARK: Round trips

    func testGroupsSurviveDecodeLoadCaptureAndEncodeByteForByte() throws {
        let registry = try SceneFixtures.registry()
        let document = try grouped()
        let bytes = document.encoded()
        XCTAssertTrue(text(document).contains("\"groups\":[{\"children\":[9,10],\"enabled\":true,\"id\":3,\"name\":\"Media\""))
        let decoded = try SceneDocument.decode(bytes)
        XCTAssertEqual(decoded.warnings, [])
        XCTAssertEqual(decoded.document.groups, document.groups)
        XCTAssertEqual(decoded.document.encoded(), bytes, "decode → encode byte for byte")
        XCTAssertFalse(document.validate(registry: registry).contains { $0.code == .invalidGroup })

        let loaded = try document.liveState(registry: registry)
        let stack = loaded.state.stack
        XCTAssertEqual(stack.groups.map(\.id.rawValue), [3, 7])
        XCTAssertEqual(stack.members(of: LayerGroupID(rawValue: 3)).map(\.rawValue), [9, 10])
        XCTAssertEqual(stack.group(LayerGroupID(rawValue: 3))?.settings.transform, try Self.moved())
        XCTAssertEqual(stack.group(LayerGroupID(rawValue: 7))?.settings.isEnabled, false)
        XCTAssertEqual(stack.group(LayerGroupID(rawValue: 7))?.settings.opacity, 0.5)
        // The acceptance's "preserves local transforms": each child's own transform is the saved one.
        for (index, instance) in [(2, UInt64(9)), (3, UInt64(10))] {
            XCTAssertEqual(stack.entry(LayerInstanceID(rawValue: instance))?.settings.transform, document.layers[index].composite.transform)
        }
        XCTAssertEqual(loaded.state.preservedGroups, [])
        let captured = try SceneDocument(capturing: loaded.state, id: document.id, name: document.name)
        XCTAssertEqual(captured.groups[0], document.groups[0], "a live group is captured as saved")
        var overlay = document.groups[1]
        overlay.extra = [:]   // the live record keeps no unknown group fields (as capture drops layers' extra fields)
        XCTAssertEqual(captured.groups[1], overlay)
        let again = try SceneDocument.decode(captured.encoded()).document
        XCTAssertEqual(try again.liveState(registry: registry).state.stack, stack, "load → capture → load is a fixed point")
        XCTAssertEqual(try SceneDocument(capturing: try again.liveState(registry: registry).state, id: again.id, name: again.name).encoded(),
                       captured.encoded(), "capture → encode → decode → capture is byte-identical")
    }

    func testAMovedGroupKeepsEveryChildsLocalTransformThroughSaveAndLoad() throws {
        let registry = try SceneFixtures.registry()
        var state = try grouped().liveState(registry: registry).state
        let id = LayerGroupID(rawValue: 3)
        let before = state.stack.entries.map(\.settings)
        let farther = try LayerTransform(translation: LayerPoint(x: -0.5, y: 0.25), uniformScale: 2, rotation: -1)
        try state.stack.setGroupSettings(LayerGroupSettings(name: "Media", transform: farther), of: id)
        XCTAssertEqual(state.stack.entries.map(\.settings), before, "moving a group changes no child")
        let saved = try SceneDocument(capturing: state, id: SceneFixtures.sceneID, name: "Moved").encoded()
        let reloaded = try SceneDocument.decode(saved).document.liveState(registry: registry).state.stack
        XCTAssertEqual(reloaded.group(id)?.settings.transform, farther)
        XCTAssertEqual(reloaded.entries.map(\.settings), before)
    }

    func testAScenewithoutGroupsIsUnchanged() throws {
        let document = try SceneFixtures.allKinds()
        XCTAssertFalse(text(document).contains("\"groups\""), "not written when empty")
        let decoded = try SceneDocument.decode(document.encoded())
        XCTAssertEqual(decoded.document.groups, [])
        XCTAssertEqual(decoded.document.encoded(), document.encoded())
        XCTAssertEqual(decoded.migration.migrated, false, "format version unchanged")
        XCTAssertEqual(SceneDocument.currentVersion, 1)
    }

    func testDefaultsClampingAndUnknownFields() throws {
        let doc = """
        {"assets":{},"bindings":[],"format":"projectm-ios.scene","id":"\(SceneFixtures.sceneID)","layers":[{"instance":1,"kind":"camera"}],
        "name":"G","parameters":{},"version":1,"groups":[{"id":5,"opacity":1.5,"children":[1],"future":{"x":1}}]}
        """
        let result = try SceneDocument.decode(Array(doc.utf8))
        let group = try XCTUnwrap(result.document.groups.first)
        XCTAssertEqual(group.name, "")
        XCTAssertTrue(group.enabled)
        XCTAssertEqual(group.opacity, 1)
        XCTAssertEqual(group.transform, .identity)
        XCTAssertEqual(group.extra["future"], try SceneFixtures.json("{\"x\":1}"))
        XCTAssertEqual(result.warnings.map(\.code), [.valueClamped])
        XCTAssertEqual(result.warnings.first?.path, "$.groups[0].opacity")
        XCTAssertTrue(String(decoding: result.document.encoded(), as: UTF8.self).contains("\"future\":{\"x\":1}"), "unknown fields kept")
    }

    func testTooManyGroupsOrChildrenAreRefusedBeforeTypedDecoding() throws {
        var groups: [String] = []
        for k in 1...9 { groups.append("{\"id\":\(k),\"children\":[]}") }
        let many = String(SceneFixtures.minimalText.dropLast()) + ",\"groups\":[" + groups.joined(separator: ",") + "]}"
        XCTAssertThrowsError(try SceneDocument.decode(Array(many.utf8))) {
            XCTAssertEqual($0 as? SceneDecodeError, .tooMany(what: "groups", count: 9, limit: 8))
        }
        let wide = String(SceneFixtures.minimalText.dropLast()) + ",\"groups\":[{\"id\":1,\"children\":[1,2,3,4,5,6,7,8,9]}]}"
        XCTAssertThrowsError(try SceneDocument.decode(Array(wide.utf8))) {
            XCTAssertEqual($0 as? SceneDecodeError, .tooMany(what: "children in group 0", count: 9, limit: 8))
        }
    }

    // MARK: Degenerate structures (CMP-011-R12)

    private static func degenerate() throws -> [(String, [SceneGroup], [String])] {
        let nested: SceneJSON = try SceneFixtures.json("{\"group\":2}")
        return [
            ("missing child", [SceneGroup(id: 1, children: [.layer(9), .layer(77)])], ["$.groups[0].children[1]"]),
            ("repeated child", [SceneGroup(id: 1, children: [.layer(9), .layer(9)])], ["$.groups[0].children[1]"]),
            ("layer in two groups", [SceneGroup(id: 1, children: [.layer(9), .layer(10)]), SceneGroup(id: 2, children: [.layer(10), .layer(11)])],
             ["$.groups[1].children[0]"]),
            ("gap", [SceneGroup(id: 1, children: [.layer(9), .layer(11)])], ["$.groups[0].children"]),
            ("empty", [SceneGroup(id: 1)], ["$.groups[0].children"]),
            ("repeated ID", [SceneGroup(id: 4, children: [.layer(9)]), SceneGroup(id: 4, children: [.layer(11)])], ["$.groups[1].id"]),
            ("ID 0", [SceneGroup(id: 0, children: [.layer(9)])], ["$.groups[0].id"]),
            ("nested child", [SceneGroup(id: 1, children: [.layer(9), .other(nested)])], ["$.groups[0].children[1]"]),
        ]
    }

    func testEveryDegenerateStructureIsAWarningDrawnUngroupedAndKept() throws {
        let registry = try SceneFixtures.registry()
        for (name, groups, paths) in try Self.degenerate() {
            let document = try scene(groups)
            let bytes = document.encoded()
            let decoded = try SceneDocument.decode(bytes)
            XCTAssertEqual(decoded.document.encoded(), bytes, "\(name): kept verbatim by decode → encode")
            let issues = document.validate(registry: registry).filter { $0.code == .invalidGroup }
            XCTAssertEqual(issues.map(\.path), paths, "\(name)")
            XCTAssertTrue(issues.allSatisfy { !$0.isError }, "\(name): a warning, never a refusal")

            let report = SceneRepairReport(document: document, registry: registry)
            let entries = report.entries.filter { $0.code == "invalidGroup" }
            XCTAssertEqual(entries.count, paths.count, "\(name): listed by the repair report")
            XCTAssertTrue(entries.allSatisfy { $0.group == .damagedFile && $0.severity == .problem && $0.actions == [.repairGroups] }, "\(name)")
            XCTAssertTrue(entries.allSatisfy { $0.item.hasPrefix("Group ") }, "\(name): \(entries.map(\.item))")
            XCTAssertTrue(report.canOpenAsIs, "\(name): the scene opens")

            let loaded = try document.liveState(registry: registry)
            let valid = Set(document.analyzeGroups().valid)
            XCTAssertEqual(loaded.state.stack.groups.count, valid.count, "\(name): only valid groups are live")
            let invalid = groups.enumerated().filter { !valid.contains($0.offset) }.map(\.element)
            XCTAssertEqual(loaded.state.preservedGroups, invalid, "\(name): damaged groups are preserved")
            let captured = try SceneDocument(capturing: loaded.state, id: document.id, name: document.name)
            for group in invalid { XCTAssertTrue(captured.groups.contains(group), "\(name): re-saved verbatim") }

            let repaired = document.repairing(report.repairActions, registry: registry)
            XCTAssertFalse(repaired.validate(registry: registry).contains { $0.code == .invalidGroup }, "\(name): repaired")
            XCTAssertEqual(repaired.repairing([.repairGroups], registry: registry), repaired, "\(name): idempotent")
            XCTAssertEqual(repaired.layers, document.layers, "\(name): layers untouched")
        }
    }

    func testRepairDropsOnlyTheBadReferenceAndKeepsTheRestOfTheGroup() throws {
        let registry = try SceneFixtures.registry()
        let document = try scene([SceneGroup(id: 1, name: "Keep", transform: try Self.moved(), children: [.layer(9), .layer(77), .layer(10)])])
        let repaired = document.repairing([.repairGroups], registry: registry)
        XCTAssertEqual(repaired.groups, [SceneGroup(id: 1, name: "Keep", transform: try Self.moved(), children: [.layer(9), .layer(10)])])
        let gap = try scene([SceneGroup(id: 1, children: [.layer(9), .layer(11)])]).repairing([.repairGroups], registry: registry)
        XCTAssertEqual(gap.groups, [], "a gap cannot be fixed by dropping references: the group goes, its layers stay")
    }

    func testRemovingALayerByRepairDropsItsGroupReference() throws {
        let registry = try SceneFixtures.registry()
        var document = try scene([SceneGroup(id: 1, children: [.layer(12), .layer(13)]), SceneGroup(id: 2, children: [.layer(11)])])
        document.layers[5].content = .material(id: "material.doesNotExist")   // #12: removeBrokenLayers removes it
        document.layers[4].content = .material(id: "material.alsoMissing")    // #11: and this one, emptying group 2
        let repaired = document.repairing([.removeBrokenLayers], registry: registry)
        XCTAssertEqual(repaired.groups, [SceneGroup(id: 1, children: [.layer(13)])])
        XCTAssertFalse(repaired.validate(registry: registry).contains { $0.code == .invalidGroup })
    }

    func testAGroupOfOnlyUnknownKindLayersIsPreserved() throws {
        let registry = try SceneFixtures.registry()
        let document = try scene([SceneGroup(id: 1, name: "Future", children: [.layer(40)])])
        XCTAssertFalse(document.validate(registry: registry).contains { $0.code == .invalidGroup })
        let state = try document.liveState(registry: registry).state
        XCTAssertEqual(state.stack.groups, [])
        XCTAssertEqual(state.preservedGroups, document.groups)
    }
}
