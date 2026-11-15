// FX-003-T10, FX-004-T06, FX-005-T07, FX-013-T09: the colour grade's MOD-001 descriptors (FX-003-R7, FX-004-R7, FX-005-R7). CPU only.
import ColorGradeParameters
import Compositor
import ParameterGraph
import ProceduralMaterials
import VisualParameters
import XCTest

final class ColorGradeCatalogTests: XCTestCase {
    func testTheCatalogValidatesAndMatchesColorGrade() throws {
        let registry: ParameterRegistry = try ColorGradeCatalog.makeRegistry()
        XCTAssertEqual(registry.descriptors.count, 11)   // FX-005: + contrast, contrastStrength; FX-013: + 3
        typealias IDs = ColorGradeParameterIDs
        let expected: [(ParameterID, ClosedRange<Double>, Double, Double)] = [
            (IDs.temperature, ColorGrade.temperatureRange, 0, ColorGrade.temperatureStep),
            (IDs.lift, ColorGrade.liftRange, 0, ColorGrade.liftStep),
            (IDs.gamma, ColorGrade.gammaRange, 1, ColorGrade.gammaStep),
            (IDs.gain, ColorGrade.gainRange, 1, ColorGrade.gainStep),
            (IDs.saturation, ColorGrade.saturationRange, 1, ColorGrade.saturationStep),
            (IDs.hue, ColorGrade.hueRange, 0, ColorGrade.hueStep),
        ]
        XCTAssertEqual(ColorGradeCatalog.descriptors.count, expected.count + 5)
        for (descriptor, row) in zip(ColorGradeCatalog.descriptors.prefix(expected.count), expected) {
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

    func testContrastDescriptors() throws {
        let tail: [ParameterDescriptor] = ColorGradeCatalog.contrastDescriptors
        XCTAssertEqual(tail.map(\.id), [ColorGradeParameterIDs.contrast, ColorGradeParameterIDs.contrastStrength])
        guard case let .enumeration(cases, defaultValue) = tail[0].kind else { return XCTFail("contrast is an enumeration") }
        XCTAssertEqual(cases.map(\.id), ["linear", "sCurve", "filmic"])
        XCTAssertEqual(defaultValue, "linear")
        XCTAssertEqual(tail[0].modulation, .discreteManual)
        guard case let .continuous(minimum, maximum, value, step, _) = tail[1].kind else { return XCTFail("strength is continuous") }
        XCTAssertEqual([minimum, maximum, value, step ?? 0], [0, 1, 0.5, 0.01])
        let values: [ParameterID: ParameterValue] = [ColorGradeParameterIDs.contrast: .enumeration("filmic"),
                                                     ColorGradeParameterIDs.contrastStrength: .continuous(3)]
        XCTAssertEqual(ColorGradeCatalog.grade(from: values), ColorGrade(contrast: .filmic, contrastStrength: 1))
        let unknown: [ParameterID: ParameterValue] = [ColorGradeParameterIDs.contrast: .enumeration("sepia")]
        XCTAssertEqual(ColorGradeCatalog.grade(from: unknown).contrast, .linear)
    }

    func testPosterizeDescriptors() throws {
        let tail: [ParameterDescriptor] = Array(ColorGradeCatalog.descriptors.suffix(3))
        typealias IDs = ColorGradeParameterIDs
        XCTAssertEqual(tail.map(\.id), [IDs.posterize, IDs.posterizeLevels, IDs.posterizeDither])
        XCTAssertEqual(tail.map(\.modulation), [.discreteManual, .discreteManual, .discreteManual])
        guard case let .integer(minimum, maximum, value, step) = tail[1].kind else { return XCTFail("levels is an integer") }
        XCTAssertEqual([minimum, maximum, value, step], [2, 32, 6, 1])
        guard case .boolean(false) = tail[0].kind, case .boolean(false) = tail[2].kind else { return XCTFail("off by default") }
        let values: [ParameterID: ParameterValue] = [IDs.posterize: .boolean(true), IDs.posterizeLevels: .integer(99),
                                                     IDs.posterizeDither: .boolean(true)]
        XCTAssertEqual(ColorGradeCatalog.grade(from: values),
                       ColorGrade(posterize: true, posterizeLevels: 32, posterizeDither: true), "levels clamped")
        XCTAssertFalse(ColorGradeCatalog.grade(from: [:]).posterize)
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
