// FX-003-T10: the colour grade's MOD-001 descriptors (FX-003-R7). CPU only.
import ColorGradeParameters
import Compositor
import ParameterGraph
import ProceduralMaterials
import VisualParameters
import XCTest

final class ColorGradeCatalogTests: XCTestCase {
    func testTheCatalogValidatesAndMatchesColorGrade() throws {
        let registry: ParameterRegistry = try ColorGradeCatalog.makeRegistry()
        XCTAssertEqual(registry.descriptors.count, 5)
        typealias IDs = ColorGradeParameterIDs
        let expected: [(ParameterID, ClosedRange<Double>, Double, Double)] = [
            (IDs.temperature, ColorGrade.temperatureRange, 0, ColorGrade.temperatureStep),
            (IDs.lift, ColorGrade.liftRange, 0, ColorGrade.liftStep),
            (IDs.gamma, ColorGrade.gammaRange, 1, ColorGrade.gammaStep),
            (IDs.gain, ColorGrade.gainRange, 1, ColorGrade.gainStep),
            (IDs.saturation, ColorGrade.saturationRange, 1, ColorGrade.saturationStep),
        ]
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
                                                     ColorGradeParameterIDs.lift: .boolean(true)]
        XCTAssertEqual(ColorGradeCatalog.grade(from: values), ColorGrade(temperature: -0.25, gain: 2))
    }
}
