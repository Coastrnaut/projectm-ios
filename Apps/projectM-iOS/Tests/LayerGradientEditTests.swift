// LayerGradientEditTests.swift — CMP-008-T15: the inspector's gradient rules (CMP-008-R10; contracts/gradient-masks.md G4):
// kind defaults, add keeps the picture, the 2…8 limits, re-sort on move, the angle round trip, the mapping to the
// compositor's settings, and the history's label and coalescing key. Plain values; no clock.
import Compositor
import Foundation
import SceneFormat
import XCTest
@testable import projectM_iOS

@MainActor
final class LayerGradientEditTests: XCTestCase {
    private typealias E = LayerGradientEdit

    private func linear() -> SceneComposite { E.settingKind("linear", on: SceneComposite()) }

    func testKindDefaultsAndRemoval() {
        let none = SceneComposite()
        XCTAssertEqual(E.kindTitle(none), "None")
        let lin = linear()
        XCTAssertEqual(lin.gradientMask, .known(.linearDefault))
        XCTAssertEqual(E.kindTitle(lin), "Linear")
        XCTAssertEqual(LayerCompositeEdit.text(.gradientStops, of: lin), "2 stops")
        // Switching kind keeps the stops and takes the kind's default geometry.
        let edited = E.settingStop(1, .alpha, to: 0.4, on: lin)
        let radial = E.settingKind("radial", on: edited)
        XCTAssertEqual(E.known(radial)?.kind, LayerGradientMask.radialDefault.kind)
        XCTAssertEqual(E.stops(radial), E.stops(edited))
        XCTAssertEqual(E.settingKind("radial", on: radial), radial, "same kind: unchanged")
        XCTAssertNil(E.settingKind(nil, on: radial).gradientMask)
        // An unknown saved kind is kept until a known one is picked.
        var unknown = SceneComposite()
        unknown.gradientMask = .unknown(kind: "conic", object: ["kind": .string("conic")])
        XCTAssertEqual(E.kindTitle(unknown), "Other (conic)")
        XCTAssertEqual(E.addingStop(on: unknown), unknown)
        XCTAssertEqual(E.settingKind("linear", on: unknown).gradientMask, .known(.linearDefault))
    }

    func testAddingAStopKeepsThePictureAndRespectsTheLimits() throws {
        var c = linear()
        let before = try XCTUnwrap(E.known(c))
        c = E.addingStop(on: c)
        let after = try XCTUnwrap(E.known(c))
        XCTAssertEqual(after.stops.count, 3)
        XCTAssertEqual(after.stops[1].position, 0.5, "the middle of the widest gap")
        for t in stride(from: 0.0, through: 1.0, by: 0.05) {
            XCTAssertEqual(after.alpha(at: t), before.alpha(at: t), accuracy: 1e-12, "unchanged at \(t)")
        }
        XCTAssertFalse(E.canAddStop(SceneComposite()))
        for _ in 0..<10 { c = E.addingStop(on: c) }
        XCTAssertEqual(E.stops(c).count, 8, "at most 8")
        XCTAssertFalse(E.canAddStop(c))
        for _ in 0..<10 { c = E.removingStop(0, on: c) }
        XCTAssertEqual(E.stops(c).count, 2, "at least 2")
        XCTAssertFalse(E.canRemoveStop(c))
    }

    func testMovingAStopPastItsNeighbourReSorts() throws {
        var c = E.addingStop(on: linear())   // 0 (1), 0.5 (0.5), 1 (0)
        c = E.settingStop(1, .position, to: 0.9, on: c)
        XCTAssertEqual(E.stops(c).map(\.position), [0, 0.9, 1])
        c = E.settingStop(1, .position, to: 1.5, on: c)   // clamped to 1; the stable sort keeps it before the old stop at 1
        XCTAssertEqual(E.stops(c).map(\.position), [0, 1, 1])
        XCTAssertEqual(E.stops(c).map(\.alpha), [1, 0.5, 0])
        XCTAssertEqual(E.settingStop(9, .alpha, to: 0.3, on: c), c, "no such stop")
        XCTAssertEqual(E.settingStop(0, .alpha, to: .nan, on: c), c)
    }

    func testAngleAndRadius() throws {
        let c = linear()
        XCTAssertEqual(LayerCompositeEdit.value(.gradientAngle, of: c), 0)
        let turned = LayerCompositeEdit.setting(.gradientAngle, to: 90, on: c)
        XCTAssertEqual(LayerCompositeEdit.value(.gradientAngle, of: turned), 90, accuracy: 1e-9)
        guard case let .linear(start, end)? = E.known(turned)?.kind else { return XCTFail("linear") }
        XCTAssertEqual(start.x, 0.5, accuracy: 1e-12)
        XCTAssertEqual(start.y, 0, accuracy: 1e-12)
        XCTAssertEqual(end.y, 1, accuracy: 1e-12, "midpoint and length kept: top to bottom")
        XCTAssertEqual(LayerCompositeEdit.text(.gradientAngle, of: turned), "90°")
        let radial = E.settingKind("radial", on: c)
        XCTAssertEqual(LayerCompositeEdit.setting(.gradientAngle, to: 45, on: radial), radial, "angle only for linear")
        let wider = LayerCompositeEdit.setting(.gradientRadius, to: 5, on: radial)
        XCTAssertEqual(LayerCompositeEdit.value(.gradientRadius, of: wider), 2, "the editor's range")
        XCTAssertEqual(LayerCompositeEdit.text(.gradientRadius, of: wider), "2.00")
    }

    func testMappingReachesTheCompositor() {
        var c = linear()
        var shape = SceneComposite()
        shape = LayerCompositeEdit.settingMask("ellipse", on: shape)
        c.mask = shape.mask
        let settings = LayerCompositeMapping.settings(c)
        XCTAssertEqual(settings.gradientMask, .linearDefault)
        XCTAssertNotNil(settings.mask)
        var unknown = SceneComposite()
        unknown.gradientMask = .unknown(kind: "conic", object: [:])
        XCTAssertNil(LayerCompositeMapping.settings(unknown).gradientMask, "an unknown kind is not drawn")
    }

    func testHistoryNamesAndKeysOneStopEdit() {
        let lin = linear()
        let edited = E.settingStop(1, .alpha, to: 0.25, on: lin)
        let edit = LayerHistoryEdit.describe(from: ["photo": lin], to: ["photo": edited])
        XCTAssertEqual(edit.label, "Photo Gradient Stop 2 Alpha 0.25")
        XCTAssertEqual(edit.key, "layer.photo.gradientStop2.alpha")
        let kindEdit = LayerHistoryEdit.describe(from: [:], to: ["photo": lin])
        XCTAssertEqual(kindEdit.label, "Photo Gradient Linear")
        XCTAssertNil(kindEdit.key, "a choice is its own step")
        let added = LayerHistoryEdit.describe(from: ["photo": lin], to: ["photo": E.addingStop(on: lin)])
        XCTAssertEqual(added.label, "Photo Gradient Stops 3 stops")
        XCTAssertNil(added.key)
        let angle = LayerHistoryEdit.describe(from: ["photo": lin], to: ["photo": LayerCompositeEdit.setting(.gradientAngle, to: 30, on: lin)])
        XCTAssertEqual(angle.key, "layer.photo.gradientAngle")
    }

    func testHelpCoversTheGradientParameters() {
        for parameter in [LayerInspectorParameter.gradientKind, .gradientAngle, .gradientRadius, .gradientStops] {
            XCTAssertFalse(parameter.help.isEmpty, parameter.rawValue)
            XCTAssertNotEqual(parameter.title, parameter.rawValue)
        }
    }
}
