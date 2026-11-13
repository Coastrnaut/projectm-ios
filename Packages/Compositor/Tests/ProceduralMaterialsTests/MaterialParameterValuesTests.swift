// SHD-001-T12 (US2; SHD-001-R6): values clamp like the MOD-001 store and refusals keep the stored
// value. CPU only; runs on Linux.
import ParameterGraph
import ProceduralMaterials
import XCTest

final class MaterialParameterValuesTests: XCTestCase {
    private let noise = ProceduralMaterialCatalog.definition(.noiseFlow)
    private var speed: ParameterID { noise.parameterID("speed") }
    private var octaves: ParameterID { noise.parameterID("octaves") }
    private var tint: ParameterID { noise.parameterID("tint") }

    func testClampsNumbersToTheRange() throws {
        var values = MaterialParameterValues(noise)
        XCTAssertEqual(try values.set(.continuous(5), for: speed), .continuous(1))
        XCTAssertEqual(values.double(speed), 1)
        XCTAssertEqual(try values.set(.continuous(-3), for: speed), .continuous(0))
        XCTAssertEqual(try values.set(.continuous(0.5), for: speed), .continuous(0.5))
        XCTAssertEqual(values.slot(1), SIMD4<Float>(0.5, 0, 0, 0))
    }

    func testIntegersClampAndColorsClampPerComponent() throws {
        var values = MaterialParameterValues(noise)
        XCTAssertEqual(try values.set(.integer(9), for: octaves), .integer(5))
        XCTAssertEqual(try values.set(.integer(-2), for: octaves), .integer(1))
        XCTAssertEqual(values.slot(2), SIMD4<Float>(1, 0, 0, 0))
        let stored = try values.set(.color(ParameterColor(red: 2, green: -1, blue: 0.5, alpha: 1)), for: tint)
        XCTAssertEqual(stored, .color(ParameterColor(red: 1, green: 0, blue: 0.5, alpha: 1)))
        XCTAssertEqual(values.slot(3), SIMD4<Float>(1, 0, 0.5, 1))
    }

    func testRefusalsKeepTheStoredValue() throws {
        var values = MaterialParameterValues(noise)
        try values.set(.continuous(0.3), for: speed)
        XCTAssertThrowsError(try values.set(.continuous(.nan), for: speed)) { error in
            XCTAssertEqual(error as? MaterialParameterError, .nonFiniteValue(speed))
        }
        XCTAssertThrowsError(try values.set(.continuous(.infinity), for: speed))
        XCTAssertThrowsError(try values.set(.integer(1), for: speed)) { error in
            XCTAssertEqual(error as? MaterialParameterError, .kindMismatch(speed, expected: "continuous", got: "integer"))
        }
        XCTAssertThrowsError(try values.set(.color(ParameterColor(red: .nan, green: 0, blue: 0)), for: tint))
        let unknown = ParameterID("material.noiseFlow.seed")
        XCTAssertThrowsError(try values.set(.continuous(1), for: unknown)) { error in
            XCTAssertEqual(error as? MaterialParameterError, .unknownParameter(unknown))
        }
        XCTAssertThrowsError(try values.set(.continuous(1), for: ProceduralMaterialCatalog.definition(.plasma).speedParameter))
        XCTAssertEqual(values.value(for: speed), .continuous(0.3))
        XCTAssertEqual(values.value(for: tint), noise.parameters[3].defaultValue)
    }

    func testSlotsEncodeDefaultsAndZeroBeyond() {
        let values = MaterialParameterValues(noise)
        XCTAssertEqual(values.slot(0).x, 4)
        XCTAssertEqual(values.slot(3), SIMD4<Float>(0.10, 0.35, 0.45, 1))
        XCTAssertEqual(values.slot(6), .zero)
        XCTAssertEqual(values.slot(-1), .zero)
        XCTAssertNil(values.double(tint))
    }
}
