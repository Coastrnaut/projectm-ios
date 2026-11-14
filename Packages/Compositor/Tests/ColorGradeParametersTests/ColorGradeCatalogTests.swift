// FX-003-T10, FX-004-T06: the colour grade's MOD-001 descriptors (FX-003-R7, FX-004-R7). CPU only.
import ColorGradeParameters
import Compositor
import ParameterGraph
import ProceduralMaterials
import VisualParameters
import XCTest

final class ColorGradeCatalogTests: XCTestCase {
    func testTheCatalogValidatesAndMatchesColorGrade() throws {
        let registry: ParameterRegistry = try ColorGradeCatalog.makeRegistry()
        XCTAssertEqual(registry.descriptors.count, 6)
        typealias IDs = ColorGradeParameterIDs
        let expected: [(ParameterID, ClosedRange<Double>, Double, Double)] = [
            (IDs.temperature, ColorGrade.temperatureRange, 0, ColorGrade.temperatureStep),
            (IDs.lift, ColorGrade.liftRange, 0, ColorGrade.liftStep),
            (IDs.gamma, ColorGrade.gammaRange, 1, ColorGrade.gammaStep),
            (IDs.gain, ColorGrade.gainRange, 1, ColorGrade.gainStep),
            (IDs.saturation, ColorGrade.saturationRange, 1, ColorGrade.saturationStep),
            (IDs.hue, ColorGrade.hueRange, 0, ColorGrade.hueStep),
        ]
        XCTAssertEqual(ColorGradeCatalog.descriptors.count, expected.count)
        for (descriptor, row) in zip(ColorGradeCatalog.descriptors, expected) {
            XCTAssertEqual(descriptor.id, row.0)
            XCTAssertEqual(descriptor.group.id, "effect.colorGrade")
            XCTAssertEqual(descriptor.modulation, .continuousDefault)
            guard case let .continuous(minimum, maximum, value, step, _) = descriptor.kind else {
                XCTFail("\(descriptor.id) is continuous")
                continue
            }
            XCTAssertEqual(minimum, row.1.lowerBound)
            XCTAssertEqual(maximum, row.1.upperBound)
            XCTAssertEqual(value, row.2, "the default is the neutral value")
            XCTAssertEqual(step, row.3)
            XCTAssertEqual(descriptor.unit, descriptor.id == IDs.hue ? .degrees : ParameterUnit.none)
        }
    }

    func testIDsAreUniqueInTheAppRegistry() throws {
        let all: [ParameterDescriptor] = VisualParameterCatalog.descriptors + ProceduralMaterialCatalog.descriptors
            + ColorGradeCatalog.descriptors
        let registry: ParameterRegistry = try ParameterRegistry(descriptors: all)
        XCTAssertEqual(registry.descriptors.count, all.count)
    }

    func testGradeFromValuesClampsAndDefaultsToNeutral() {
        XCTAssertEqual(ColorGradeCatalog.grade(from: [:]), .neutral)
        let values: [ParameterID: ParameterValue] = [ColorGradeParameterIDs.gain: .continuous(5),
                                                     ColorGradeParameterIDs.temperature: .continuous(-0.25),
                                                     ColorGradeParameterIDs.lift: .boolean(true),
                                                     ColorGradeParameterIDs.hue: .continuous(-500)]
        XCTAssertEqual(ColorGradeCatalog.grade(from: values), ColorGrade(temperature: -0.25, gain: 2, hue: -180))
    }
}

/// FX-009-T08: the Trails descriptors (FX-009-R10). CPU only.
final class MotionFeedbackCatalogTests: XCTestCase {
    func testTheCatalogValidatesAndMatchesMotionFeedback() throws {
        let registry: ParameterRegistry = try MotionFeedbackCatalog.makeRegistry()
        XCTAssertEqual(registry.descriptors.count, 2)
        let enabled: ParameterDescriptor = MotionFeedbackCatalog.descriptors[0]
        XCTAssertEqual(enabled.id, "effect.feedback.enabled")
        XCTAssertEqual(enabled.kind, .boolean(defaultValue: false), "off by default")
        XCTAssertEqual(enabled.modulation, .discreteManual)
        let halfLife: ParameterDescriptor = MotionFeedbackCatalog.descriptors[1]
        XCTAssertEqual(halfLife.id, "effect.feedback.halfLife")
        XCTAssertEqual(halfLife.unit, .seconds)
        XCTAssertEqual(halfLife.group.id, "effect.feedback")
        guard case let .continuous(minimum, maximum, value, step, _) = halfLife.kind else { return XCTFail("continuous") }
        XCTAssertEqual(minimum, MotionFeedback.halfLifeRange.lowerBound)
        XCTAssertEqual(maximum, MotionFeedback.halfLifeRange.upperBound)
        XCTAssertEqual(value, MotionFeedback.defaultHalfLife)
        XCTAssertEqual(step, MotionFeedback.halfLifeStep)
    }

    func testIDsAreUniqueInTheAppRegistry() throws {
        let all: [ParameterDescriptor] = VisualParameterCatalog.descriptors + ProceduralMaterialCatalog.descriptors
            + ColorGradeCatalog.descriptors + MotionFeedbackCatalog.descriptors
        XCTAssertEqual(try ParameterRegistry(descriptors: all).descriptors.count, all.count)
    }

    func testFeedbackFromValuesClampsAndDefaultsToOff() {
        XCTAssertEqual(MotionFeedbackCatalog.feedback(from: [:]), .off)
        let values: [ParameterID: ParameterValue] = [MotionFeedbackParameterIDs.enabled: .boolean(true),
                                                     MotionFeedbackParameterIDs.halfLife: .continuous(9)]
        XCTAssertEqual(MotionFeedbackCatalog.feedback(from: values), MotionFeedback(isEnabled: true, halfLifeSeconds: 0.5))
        let mistyped: [ParameterID: ParameterValue] = [MotionFeedbackParameterIDs.enabled: .continuous(1)]
        XCTAssertEqual(MotionFeedbackCatalog.feedback(from: mistyped), .off)
    }
}
