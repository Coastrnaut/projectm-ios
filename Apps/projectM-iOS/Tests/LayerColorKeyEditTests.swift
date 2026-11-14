// LayerColorKeyEditTests.swift — CMP-010-T16: the inspector's colour key rules (CMP-010-R10; contracts/color-key.md C4):
// on gives the green key and off removes it, the picked colour is stored opaque, clamped and rounded, sliders clamp,
// edits without a key change nothing, the mapping to the compositor's settings, and the history's labels and
// coalescing keys. Plain values; no clock.
import Compositor
import Foundation
import SceneFormat
import XCTest
@testable import projectM_iOS

@MainActor
final class LayerColorKeyEditTests: XCTestCase {
    private func set(_ p: LayerInspectorParameter, _ v: Double, _ c: SceneComposite) -> SceneComposite {
        LayerCompositeEdit.setting(p, to: v, on: c)
    }

    func testTurningTheKeyOnGivesTheGreenKeyAndOffRemovesIt() {
        let none = SceneComposite()
        XCTAssertEqual(LayerCompositeEdit.text(.colorKey, of: none), "Off")
        XCTAssertEqual(set(.colorTolerance, 0.5, none), none, "no key: a slider changes nothing")
        XCTAssertEqual(LayerColorKeyEdit.settingColor(red: 1, green: 0, blue: 0, on: none), none, "no key: a colour changes nothing")
        let on = set(.colorKey, 1, none)
        XCTAssertEqual(on.colorKey, .greenKey)
        XCTAssertEqual(LayerCompositeEdit.text(.colorKey, of: on), "On")
        XCTAssertEqual(LayerCompositeEdit.text(.colorKeyColor, of: on), "#00FF00")
        XCTAssertEqual(LayerCompositeEdit.text(.colorTolerance, of: on), "0.20")
        let wide = set(.colorTolerance, 0.4, on)
        XCTAssertEqual(set(.colorKey, 1, wide), wide, "on again keeps the current key")
        XCTAssertNil(set(.colorKey, 0, wide).colorKey)
    }

    func testPickedColourIsOpaqueClampedAndRounded() throws {
        let on = set(.colorKey, 1, SceneComposite())
        // A wide-gamut pick arrives as extended sRGB (components outside 0…1); opacity is never passed.
        let picked = try XCTUnwrap(LayerColorKeyEdit.settingColor(red: 1.2, green: -0.05, blue: 0.123456, on: on).colorKey)
        XCTAssertEqual(picked.red, 1)
        XCTAssertEqual(picked.green, 0)
        XCTAssertEqual(picked.green.sign, .plus)
        XCTAssertEqual(picked.blue, 0.123)
        XCTAssertEqual(picked.tolerance, 0.2, "the sliders' values stay")
        XCTAssertEqual(LayerColorKeyEdit.hex(picked), "#FF001F")
        let same = LayerColorKeyEdit.settingColor(red: 1.0000001, green: 0, blue: 0.1230004, on: SceneComposite(colorKey: picked))
        XCTAssertEqual(same.colorKey, picked, "round trips through the picker do not drift")
        XCTAssertEqual(LayerColorKeyEdit.settingColor(red: .nan, green: 0.5, blue: 0.5, on: on).colorKey?.red, 0, "non-finite keeps the component")
    }

    func testSlidersClampAndUseTheModelRanges() {
        let on = set(.colorKey, 1, SceneComposite())
        XCTAssertEqual(set(.colorTolerance, 3, on).colorKey?.tolerance, 1)
        XCTAssertEqual(set(.colorFeather, 3, on).colorKey?.feather, 0.5)
        XCTAssertEqual(set(.colorFeather, -1, on).colorKey?.feather, 0)
        XCTAssertEqual(LayerCompositeEdit.range(.colorTolerance), 0...1)
        XCTAssertEqual(LayerCompositeEdit.range(.colorFeather), 0...0.5)
        XCTAssertEqual(LayerCompositeEdit.step(.colorFeather), 0.02)
    }

    func testMappingReachesTheCompositor() {
        let on = set(.colorKey, 1, SceneComposite())
        XCTAssertEqual(LayerCompositeMapping.settings(on).colorKey, .greenKey)
        XCTAssertNil(LayerCompositeMapping.settings(SceneComposite()).colorKey)
        XCTAssertEqual(LayerCompositeMapping.normalized(["photo": on])["photo"], on, "a keyed composite is not the default")
    }

    func testHistoryNamesAndKeys() {
        let on = set(.colorKey, 1, SceneComposite())
        let toggle = LayerHistoryEdit.describe(from: [:], to: ["photo": on])
        XCTAssertEqual(toggle.label, "Photo Color Key On")
        XCTAssertNil(toggle.key, "a toggle is its own step")
        let red = LayerColorKeyEdit.settingColor(red: 1, green: 0, blue: 0, on: on)
        let colour = LayerHistoryEdit.describe(from: ["photo": on], to: ["photo": red])
        XCTAssertEqual(colour.label, "Photo Key Color #FF0000")
        XCTAssertEqual(colour.key, "layer.photo.colorKeyColor", "picker updates coalesce")
        let tolerance = LayerHistoryEdit.describe(from: ["photo": on], to: ["photo": set(.colorTolerance, 0.3, on)])
        XCTAssertEqual(tolerance.label, "Photo Color Tolerance 0.30")
        XCTAssertEqual(tolerance.key, "layer.photo.colorTolerance")
        let feather = LayerHistoryEdit.describe(from: ["photo": on], to: ["photo": set(.colorFeather, 0.2, on)])
        XCTAssertEqual(feather.label, "Photo Color Feather 0.20")
        XCTAssertEqual(feather.key, "layer.photo.colorFeather")
    }

    func testHelpCoversTheKeyParameters() {
        for parameter in LayerColorKeyEdit.parameters {
            XCTAssertFalse(parameter.help.isEmpty, parameter.rawValue)
            XCTAssertNotEqual(parameter.title, parameter.rawValue)
        }
    }
}
