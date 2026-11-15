// OutputEffectOrderTests.swift — FX-020-T02: the order model (plain Swift; also runs in the Linux shape).
@testable import Compositor
import XCTest

final class OutputEffectOrderTests: XCTestCase {
    func testStandardIsTrailsThenColor() {
        XCTAssertEqual(OutputEffectOrder.standard.effects, [.trails, .grade, .chromatic, .directionalBlur, .radialBlur, .echo, .mosaic, .edgeOutline, .lensDistortion, .pixelSort, .vignette, .scanlines])   // FX-006, FX-007, FX-008 appended
        XCTAssertFalse(OutputEffectOrder.standard.gradeBeforeTrails)
        XCTAssertTrue(OutputEffectOrder([.grade]).gradeBeforeTrails, "missing Trails appended after Color")
    }

    func testRepeatsDroppedAndMissingAppended() {
        XCTAssertEqual(OutputEffectOrder([.grade, .grade, .trails, .grade]).effects, [.grade, .trails, .chromatic, .directionalBlur, .radialBlur, .echo, .mosaic, .edgeOutline, .lensDistortion, .pixelSort, .vignette, .scanlines])
        XCTAssertEqual(OutputEffectOrder([]).effects, [.trails, .grade, .chromatic, .directionalBlur, .radialBlur, .echo, .mosaic, .edgeOutline, .lensDistortion, .pixelSort, .vignette, .scanlines])
        XCTAssertEqual(OutputEffectOrder([.chromatic]).effects, [.chromatic, .trails, .grade, .directionalBlur, .radialBlur, .echo, .mosaic, .edgeOutline, .lensDistortion, .pixelSort, .vignette, .scanlines])
        XCTAssertEqual(OutputEffectOrder([.directionalBlur]).effects, [.directionalBlur, .trails, .grade, .chromatic, .radialBlur, .echo, .mosaic, .edgeOutline, .lensDistortion, .pixelSort, .vignette, .scanlines])   // FX-007
        XCTAssertEqual(OutputEffectOrder([.radialBlur]).effects, [.radialBlur, .trails, .grade, .chromatic, .directionalBlur, .echo, .mosaic, .edgeOutline, .lensDistortion, .pixelSort, .vignette, .scanlines])   // FX-008
        XCTAssertEqual(OutputEffectOrder([.echo]).effects, [.echo, .trails, .grade, .chromatic, .directionalBlur, .radialBlur, .mosaic, .edgeOutline, .lensDistortion, .pixelSort, .vignette, .scanlines])   // FX-010
    }

    func testMoveUsesSwiftUISemantics() {
        XCTAssertEqual(OutputEffectOrder.standard.moving(from: [1], to: 0).effects, [.grade, .trails, .chromatic, .directionalBlur, .radialBlur, .echo, .mosaic, .edgeOutline, .lensDistortion, .pixelSort, .vignette, .scanlines])
        XCTAssertEqual(OutputEffectOrder.standard.moving(from: [0], to: 2).effects, [.grade, .trails, .chromatic, .directionalBlur, .radialBlur, .echo, .mosaic, .edgeOutline, .lensDistortion, .pixelSort, .vignette, .scanlines])
        XCTAssertEqual(OutputEffectOrder.standard.moving(from: [2], to: 0).effects, [.chromatic, .trails, .grade, .directionalBlur, .radialBlur, .echo, .mosaic, .edgeOutline, .lensDistortion, .pixelSort, .vignette, .scanlines])
        XCTAssertEqual(OutputEffectOrder.standard.moving(from: [3], to: 0).effects, [.directionalBlur, .trails, .grade, .chromatic, .radialBlur, .echo, .mosaic, .edgeOutline, .lensDistortion, .pixelSort, .vignette, .scanlines])
        XCTAssertEqual(OutputEffectOrder.standard.moving(from: [4], to: 0).effects, [.radialBlur, .trails, .grade, .chromatic, .directionalBlur, .echo, .mosaic, .edgeOutline, .lensDistortion, .pixelSort, .vignette, .scanlines])   // FX-008
        XCTAssertEqual(OutputEffectOrder.standard.moving(from: [5], to: 0).effects, [.echo, .trails, .grade, .chromatic, .directionalBlur, .radialBlur, .mosaic, .edgeOutline, .lensDistortion, .pixelSort, .vignette, .scanlines])   // FX-010
        XCTAssertEqual(OutputEffectOrder.standard.moving(from: [0], to: 0), .standard)
        XCTAssertEqual(OutputEffectOrder.standard.moving(from: [6], to: 0).effects.first, .mosaic)   // FX-012
        XCTAssertEqual(OutputEffectOrder.standard.moving(from: [7], to: 0).effects.first, .edgeOutline)   // FX-014
        XCTAssertEqual(OutputEffectOrder.standard.moving(from: [8], to: 0).effects.first, .lensDistortion)   // FX-016
        XCTAssertEqual(OutputEffectOrder.standard.moving(from: [10], to: 0).effects.first, .vignette)   // FX-015
        XCTAssertEqual(OutputEffectOrder.standard.effects.last, .scanlines)   // FX-018: appended after Vignette
        XCTAssertEqual(OutputEffectOrder.standard.effects.firstIndex(of: .pixelSort), 9)   // FX-011: after Lens distortion
        XCTAssertEqual(OutputEffectOrder.standard.moving(from: [9], to: 0).effects.first, .pixelSort)   // FX-011
        XCTAssertEqual(OutputEffectOrder(storageText: "fx.lensDistortion,fx.vignette,fx.scanlines").effects.last, .pixelSort,
                       "a stored order without it reads with it last (FX-011, FX-020's rule)")
        XCTAssertEqual(OutputEffectOrder.standard.moving(from: [99], to: 0), .standard, "out-of-range offsets are ignored")
    }

    func testStorageTextRoundTripsAndToleratesJunk() {
        let order = OutputEffectOrder([.grade, .trails])
        XCTAssertEqual(order.storageText, "fx.grade,fx.trails,fx.chromatic,fx.directionalBlur,fx.radialBlur,fx.echo,fx.mosaic,fx.edgeOutline,fx.lensDistortion,fx.pixelSort,fx.vignette,fx.scanlines")
        XCTAssertEqual(OutputEffectOrder(storageText: "fx.grade,fx.trails,fx.chromatic"), order, "an FX-006 stored order reads with the blurs and Echo last")
        XCTAssertEqual(OutputEffectOrder(storageText: "fx.grade,fx.trails,fx.chromatic,fx.directionalBlur,fx.radialBlur"), order, "an FX-008 stored order reads with Echo last")
        XCTAssertEqual(OutputEffectOrder(storageText: "fx.grade,fx.trails"), order, "an FX-020 stored order reads with the split last")
        XCTAssertEqual(OutputEffectOrder(storageText: order.storageText), order)
        XCTAssertEqual(OutputEffectOrder(storageText: "fx.flashGuard,,fx.grade,banana"), order)
        XCTAssertEqual(OutputEffectOrder(storageText: ""), .standard)
        let fx006: [OutputEffectKind] = OutputEffectOrder(storageText: "fx.chromatic,fx.grade,fx.trails").effects
        XCTAssertEqual(fx006.firstIndex(of: .radialBlur), 4, "an FX-006 stored order reads with the radial blur (FX-008) appended")
        XCTAssertEqual(fx006.firstIndex(of: .echo), 5, "then Echo (FX-010)")
        XCTAssertEqual(OutputEffectOrder(storageText: "fx.chromatic,fx.grade,fx.trails,fx.directionalBlur,fx.radialBlur,fx.echo")
                        .effects.firstIndex(of: .mosaic), 6, "an FX-010 stored order reads with the mosaic appended (FX-012)")
        XCTAssertEqual(OutputEffectOrder(storageText: "fx.chromatic,fx.grade,fx.trails,fx.directionalBlur,fx.radialBlur,fx.echo,fx.mosaic")
                        .effects.firstIndex(of: .edgeOutline), 7, "an FX-012 stored order reads with the edge outline appended (FX-014)")
        XCTAssertEqual(OutputEffectOrder(storageText: "fx.chromatic,fx.grade,fx.trails,fx.directionalBlur,fx.radialBlur,fx.echo,fx.mosaic,fx.edgeOutline")
                        .effects.firstIndex(of: .lensDistortion), 8, "an FX-014 stored order reads with the lens distortion appended (FX-016)")
        XCTAssertEqual(OutputEffectOrder(storageText: "fx.chromatic,fx.grade,fx.trails,fx.directionalBlur,fx.radialBlur,fx.echo,fx.mosaic,fx.edgeOutline,fx.lensDistortion,fx.vignette")
                        .effects.last, .scanlines, "an FX-015 stored order reads with the scanlines appended (FX-018)")
        XCTAssertEqual(OutputEffectOrder(storageText: "fx.mosaic,fx.grade").effects.dropLast().last, .vignette,
                       "a stored order without it reads with the vignette last (FX-015)")
    }

    func testFixedStagesAreNotOrderable() {
        for stage in FixedOutputStage.allCases { XCTAssertNil(OutputEffectKind(rawValue: stage.rawValue)) }
    }
}
