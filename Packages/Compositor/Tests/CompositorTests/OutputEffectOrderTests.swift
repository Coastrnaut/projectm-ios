// OutputEffectOrderTests.swift — FX-020-T02: the order model (plain Swift; also runs in the Linux shape).
@testable import Compositor
import XCTest

final class OutputEffectOrderTests: XCTestCase {
    func testStandardIsTrailsThenColor() {
        XCTAssertEqual(OutputEffectOrder.standard.effects, [.trails, .grade, .chromatic])   // FX-006 appended
        XCTAssertFalse(OutputEffectOrder.standard.gradeBeforeTrails)
        XCTAssertTrue(OutputEffectOrder([.grade]).gradeBeforeTrails, "missing Trails appended after Color")
    }

    func testRepeatsDroppedAndMissingAppended() {
        XCTAssertEqual(OutputEffectOrder([.grade, .grade, .trails, .grade]).effects, [.grade, .trails, .chromatic])
        XCTAssertEqual(OutputEffectOrder([]).effects, [.trails, .grade, .chromatic])
        XCTAssertEqual(OutputEffectOrder([.chromatic]).effects, [.chromatic, .trails, .grade])
    }

    func testMoveUsesSwiftUISemantics() {
        XCTAssertEqual(OutputEffectOrder.standard.moving(from: [1], to: 0).effects, [.grade, .trails, .chromatic])
        XCTAssertEqual(OutputEffectOrder.standard.moving(from: [0], to: 2).effects, [.grade, .trails, .chromatic])
        XCTAssertEqual(OutputEffectOrder.standard.moving(from: [2], to: 0).effects, [.chromatic, .trails, .grade])
        XCTAssertEqual(OutputEffectOrder.standard.moving(from: [0], to: 0), .standard)
        XCTAssertEqual(OutputEffectOrder.standard.moving(from: [5], to: 0), .standard, "out-of-range offsets are ignored")
    }

    func testStorageTextRoundTripsAndToleratesJunk() {
        let order = OutputEffectOrder([.grade, .trails])
        XCTAssertEqual(order.storageText, "fx.grade,fx.trails,fx.chromatic")
        XCTAssertEqual(OutputEffectOrder(storageText: "fx.grade,fx.trails"), order, "an FX-020 stored order reads with the split last")
        XCTAssertEqual(OutputEffectOrder(storageText: order.storageText), order)
        XCTAssertEqual(OutputEffectOrder(storageText: "fx.flashGuard,,fx.grade,banana"), order)
        XCTAssertEqual(OutputEffectOrder(storageText: ""), .standard)
    }

    func testFixedStagesAreNotOrderable() {
        for stage in FixedOutputStage.allCases { XCTAssertNil(OutputEffectKind(rawValue: stage.rawValue)) }
    }
}
