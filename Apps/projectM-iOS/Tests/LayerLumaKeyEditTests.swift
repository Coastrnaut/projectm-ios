// LayerLumaKeyEditTests.swift — CMP-009-T16: the inspector's luma key rules (CMP-009-R10; contracts/luma-key.md L2):
// on gives the black key and off removes it, Low and High push each other so low ≤ high, edits without a key change
// nothing, the mapping to the compositor's settings, and the history's labels and coalescing keys. Plain values; no clock.
import Compositor
import Foundation
import SceneFormat
import XCTest
@testable import projectM_iOS

@MainActor
final class LayerLumaKeyEditTests: XCTestCase {
    private func set(_ p: LayerInspectorParameter, _ v: Double, _ c: SceneComposite) -> SceneComposite {
        LayerCompositeEdit.setting(p, to: v, on: c)
    }

    func testTurningTheKeyOnGivesTheBlackKeyAndOffRemovesIt() {
        let none = SceneComposite()
        XCTAssertEqual(LayerCompositeEdit.text(.lumaKey, of: none), "Off")
        XCTAssertEqual(set(.lumaLow, 0.5, none), none, "no key: a slider changes nothing")
        let on = set(.lumaKey, 1, none)
        XCTAssertEqual(on.lumaKey, .blackKey)
        XCTAssertEqual(LayerCompositeEdit.text(.lumaKey, of: on), "On")
        XCTAssertEqual(LayerCompositeEdit.text(.lumaHigh, of: on), "0.10")
        let soft = set(.lumaSoftness, 0.3, on)
        XCTAssertEqual(set(.lumaKey, 1, soft), soft, "on again keeps the current key")
        XCTAssertNil(set(.lumaKey, 0, soft).lumaKey)
    }

    func testLowAndHighPushEachOtherAndSoftnessClamps() throws {
        let on = set(.lumaKey, 1, SceneComposite())
        let low = try XCTUnwrap(set(.lumaLow, 0.4, on).lumaKey)
        XCTAssertEqual(low.low, 0.4)
        XCTAssertEqual(low.high, 0.4, "High follows Low up")
        let high = try XCTUnwrap(set(.lumaHigh, 0.2, set(.lumaLow, 0.4, on)).lumaKey)
        XCTAssertEqual(high.low, 0.2, "Low follows High down")
        XCTAssertEqual(high.high, 0.2)
        XCTAssertEqual(set(.lumaSoftness, 3, on).lumaKey?.softness, 0.5)
        XCTAssertEqual(LayerCompositeEdit.range(.lumaSoftness), 0...0.5)
        XCTAssertEqual(LayerCompositeEdit.range(.lumaLow), 0...1)
        XCTAssertEqual(set(.lumaInverted, 1, on).lumaKey?.inverted, true)
    }

    func testMappingReachesTheCompositor() {
        let on = set(.lumaKey, 1, SceneComposite())
        XCTAssertEqual(LayerCompositeMapping.settings(on).lumaKey, .blackKey)
        XCTAssertNil(LayerCompositeMapping.settings(SceneComposite()).lumaKey)
    }

    func testHistoryNamesAndKeys() {
        let on = set(.lumaKey, 1, SceneComposite())
        let toggle = LayerHistoryEdit.describe(from: [:], to: ["photo": on])
        XCTAssertEqual(toggle.label, "Photo Luma Key On")
        XCTAssertNil(toggle.key, "a toggle is its own step")
        let low = LayerHistoryEdit.describe(from: ["photo": on], to: ["photo": set(.lumaLow, 0.05, on)])
        XCTAssertEqual(low.label, "Photo Luma Range 0.05–0.10")
        XCTAssertEqual(low.key, "layer.photo.lumaRange")
        let pushed = LayerHistoryEdit.describe(from: ["photo": on], to: ["photo": set(.lumaLow, 0.3, on)])
        XCTAssertEqual(pushed.label, "Photo Luma Range 0.30–0.30", "one step even when High follows")
        XCTAssertEqual(pushed.key, "layer.photo.lumaRange")
        let soft = LayerHistoryEdit.describe(from: ["photo": on], to: ["photo": set(.lumaSoftness, 0.2, on)])
        XCTAssertEqual(soft.label, "Photo Key Softness 0.20")
        XCTAssertEqual(soft.key, "layer.photo.lumaSoftness")
        let invert = LayerHistoryEdit.describe(from: ["photo": on], to: ["photo": set(.lumaInverted, 1, on)])
        XCTAssertEqual(invert.label, "Photo Invert Key On")
        XCTAssertNil(invert.key)
    }

    func testHelpCoversTheKeyParameters() {
        for parameter in LayerLumaKeyEdit.parameters {
            XCTAssertFalse(parameter.help.isEmpty, parameter.rawValue)
            XCTAssertNotEqual(parameter.title, parameter.rawValue)
        }
    }
}
