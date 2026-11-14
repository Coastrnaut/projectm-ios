// SHD-003-T13 (US3; SHD-003-R7, S3): the control builder makes one control per metadata parameter, in order,
// with the metadata's kind, label, range, step, unit and options, and shows only values that fit. CPU only.
import ParameterGraph
import ShaderParameterMetadata
import XCTest

final class ShaderParameterControlsTests: XCTestCase {
    private let group = ParameterGroup(id: "test.sample", displayName: "Sample")

    private func controls(_ values: [ParameterID: ParameterValue] = [:]) throws -> [ShaderParameterControl] {
        let m = try ShaderMetadataReader.validate(json: ShaderMetadataValidatorTests.valid, document: "test.sample")
        return ShaderParameterControls.controls(for: m, idPrefix: "test.sample", group: group, values: values)
    }

    func testControlsMirrorTheMetadata() throws {
        let c = try controls()
        XCTAssertEqual(c.map(\.kind), [.slider, .stepper, .toggle, .picker, .color])
        XCTAssertEqual(c.map(\.label), ["Speed", "Count", "Mirror", "Shape", "Tint"])
        XCTAssertEqual(c.map(\.id.rawValue), ["test.sample.speed", "test.sample.count", "test.sample.mirror", "test.sample.shape", "test.sample.tint"])
        XCTAssertEqual(c[0].range, 0...1)
        XCTAssertEqual(c[0].step, 0.01)
        XCTAssertEqual(c[0].unit, .perSecond)
        XCTAssertEqual(c[1].range, 1...9)
        XCTAssertEqual(c[1].step, 2)
        XCTAssertNil(c[2].range)
        XCTAssertEqual(c[3].options.map(\.id), ["linear", "radial"])
        XCTAssertEqual(c[3].options.map(\.displayName), ["Linear", "Radial"])
        XCTAssertEqual(c.map(\.value), c.map(\.defaultValue), "no stored values: defaults")
        XCTAssertEqual(c[3].value, .enumeration("radial"))
    }

    func testStoredValuesShownWhenTheyFit() throws {
        let id = { (name: String) -> ParameterID in ParameterID("test.sample." + name) }
        let c = try controls([
            id("speed"): .continuous(7),                // clamped to 1
            id("count"): .integer(6),                   // snapped to a step from 1: 7
            id("mirror"): .boolean(false),
            id("shape"): .enumeration("spiral"),        // unknown case: default
            id("tint"): .continuous(0.5),               // wrong kind: default
        ])
        XCTAssertEqual(c[0].value, .continuous(1))
        XCTAssertEqual(c[1].value, .integer(7))
        XCTAssertEqual(c[2].value, .boolean(false))
        XCTAssertEqual(c[3].value, .enumeration("radial"))
        XCTAssertEqual(c[4].value, c[4].defaultValue)
        let nan = try controls([id("speed"): .continuous(.nan)])
        XCTAssertEqual(nan[0].value, .continuous(0.25))
    }
}
