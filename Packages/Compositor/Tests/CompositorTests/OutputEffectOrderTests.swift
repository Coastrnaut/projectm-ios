// OutputEffectOrderTests.swift — FX-020-T02: the order model (plain Swift; also runs in the Linux shape).
@testable import Compositor
import XCTest

final class OutputEffectOrderTests: XCTestCase {
    func testStandardIsTrailsThenColor() {
        XCTAssertEqual(OutputEffectOrder.standard.effects, [.trails, .grade, .chromatic, .directionalBlur, .radialBlur, .mosaic])   // FX-006, FX-007, FX-008 appended
        XCTAssertFalse(OutputEffectOrder.standard.gradeBeforeTrails)
        XCTAssertTrue(OutputEffectOrder([.grade]).gradeBeforeTrails, "missing Trails appended after Color")
    }

    func testRepeatsDroppedAndMissingAppended() {
        XCTAssertEqual(OutputEffectOrder([.grade, .grade, .trails, .grade]).effects, [.grade, .trails, .chromatic, .directionalBlur, .radialBlur, .mosaic])
        XCTAssertEqual(OutputEffectOrder([]).effects, [.trails, .grade, .chromatic, .directionalBlur, .radialBlur, .mosaic])
        XCTAssertEqual(OutputEffectOrder([.chromatic]).effects, [.chromatic, .trails, .grade, .directionalBlur, .radialBlur, .mosaic])
        XCTAssertEqual(OutputEffectOrder([.directionalBlur]).effects, [.directionalBlur, .trails, .grade, .chromatic, .radialBlur, .mosaic])   // FX-007
        XCTAssertEqual(OutputEffectOrder([.radialBlur]).effects, [.radialBlur, .trails, .grade, .chromatic, .directionalBlur, .mosaic])   // FX-008
    }

    func testMoveUsesSwiftUISemantics() {
        XCTAssertEqual(OutputEffectOrder.standard.moving(from: [1], to: 0).effects, [.grade, .trails, .chromatic, .directionalBlur, .radialBlur, .mosaic])
        XCTAssertEqual(OutputEffectOrder.standard.moving(from: [0], to: 2).effects, [.grade, .trails, .chromatic, .directionalBlur, .radialBlur, .mosaic])
        XCTAssertEqual(OutputEffectOrder.standard.moving(from: [2], to: 0).effects, [.chromatic, .trails, .grade, .directionalBlur, .radialBlur, .mosaic])
        XCTAssertEqual(OutputEffectOrder.standard.moving(from: [3], to: 0).effects, [.directionalBlur, .trails, .grade, .chromatic, .radialBlur, .mosaic])
        XCTAssertEqual(OutputEffectOrder.standard.moving(from: [4], to: 0).effects, [.radialBlur, .trails, .grade, .chromatic, .directionalBlur, .mosaic])   // FX-008
        XCTAssertEqual(OutputEffectOrder.standard.moving(from: [0], to: 0), .standard)
        XCTAssertEqual(OutputEffectOrder.standard.moving(from: [5], to: 0).effects.first, .mosaic)   // FX-012
        XCTAssertEqual(OutputEffectOrder.standard.moving(from: [99], to: 0), .standard, "out-of-range offsets are ignored")
    }

    func testStorageTextRoundTripsAndToleratesJunk() {
        let order = OutputEffectOrder([.grade, .trails])
        XCTAssertEqual(order.storageText, "fx.grade,fx.trails,fx.chromatic,fx.directionalBlur,fx.radialBlur,fx.mosaic")
        XCTAssertEqual(OutputEffectOrder(storageText: "fx.grade,fx.trails,fx.chromatic"), order, "an FX-006 stored order reads with the blurs last")
        XCTAssertEqual(OutputEffectOrder(storageText: "fx.grade,fx.trails"), order, "an FX-020 stored order reads with the split last")
        XCTAssertEqual(OutputEffectOrder(storageText: order.storageText), order)
        XCTAssertEqual(OutputEffectOrder(storageText: "fx.flashGuard,,fx.grade,banana"), order)
        XCTAssertEqual(OutputEffectOrder(storageText: ""), .standard)
        XCTAssertEqual(OutputEffectOrder(storageText: "fx.chromatic,fx.grade,fx.trails").effects.firstIndex(of: .radialBlur), 4,
                       "an FX-006 stored order reads with the radial blur appended (FX-008)")
        XCTAssertEqual(OutputEffectOrder(storageText: "fx.chromatic,fx.grade,fx.trails,fx.directionalBlur,fx.radialBlur")
                        .effects.firstIndex(of: .mosaic), 5, "an FX-008 stored order reads with the mosaic appended (FX-012)")
    }

    func testFixedStagesAreNotOrderable() {
        for stage in FixedOutputStage.allCases { XCTAssertNil(OutputEffectKind(rawValue: stage.rawValue)) }
    }
}
