// MaterialInspectorTests.swift — SHD-003-T16 (US3; SHD-003-R7, R8, S3): the inspector's controls for every
// material equal its validated metadata (kinds, labels, ranges, steps, options, order), each control's
// accessibility value is the formatted current value, and the seeded scene's material layer carries them.
// Plain values; no clock.
import ParameterGraph
import ProceduralMaterials
import SceneFormat
import ShaderParameterMetadata
import XCTest
@testable import projectM_iOS

@MainActor
final class MaterialInspectorTests: XCTestCase {
    private typealias Model = MaterialInspectorModel

    func testControlsEqualTheMetadataForEveryMaterial() throws {
        var count = 0
        for definition in ProceduralMaterialCatalog.materials {
            let metadata = try XCTUnwrap(definition.metadata, definition.id)
            let controls = Model.controls(for: .material(id: definition.id), parameters: [:])
            XCTAssertEqual(controls.map(\.label), metadata.parameters.map(\.label), definition.id)
            XCTAssertEqual(controls.map(\.id.rawValue), metadata.parameters.map { (p: ShaderParameterSpec) -> String in definition.id + "." + p.id })
            for (control, spec) in zip(controls, metadata.parameters) {
                let expectedKind: ShaderParameterControl.Kind
                switch spec.kind {
                case let .float(minimum, maximum, step, _):
                    expectedKind = .slider
                    XCTAssertEqual(control.range, minimum...maximum)
                    XCTAssertEqual(control.step, step)
                    let slider = try XCTUnwrap(Model.sliderSpec(control))
                    XCTAssertEqual(slider.label, spec.label)
                    XCTAssertEqual(slider.range, minimum...maximum)
                    XCTAssertEqual(slider.id, "materialControl." + control.id.rawValue)
                case let .int(minimum, maximum, step, _):
                    expectedKind = .stepper
                    XCTAssertEqual(control.range, Double(minimum)...Double(maximum))
                    XCTAssertEqual(control.step, Double(step))
                case .bool:
                    expectedKind = .toggle
                case let .enumeration(cases, _):
                    expectedKind = .picker
                    XCTAssertEqual(control.options, cases)
                case .color:
                    expectedKind = .color
                }
                XCTAssertEqual(control.kind, expectedKind, control.id.rawValue)
                XCTAssertEqual(control.unit, spec.unit)
                XCTAssertFalse(Model.spoken(control).isEmpty, control.id.rawValue)
                count += 1
            }
        }
        XCTAssertEqual(count, 29)
    }

    /// The accessibility values are the formatted values (ACC-005 for sliders, UIX-003 otherwise).
    func testAccessibilityValuesAreTheFormattedValues() {
        let plasma = Model.controls(for: .material(id: "material.plasma"), parameters: [ParameterID("material.plasma.brightness"): .continuous(0.3)])
        XCTAssertEqual(plasma.map(\.kind), [.slider, .slider, .slider, .slider, .slider])
        XCTAssertEqual(Model.display(plasma[0]), "2.00")
        XCTAssertEqual(Model.display(plasma[2]), "30%", "the scene's value")
        XCTAssertEqual(Model.spoken(plasma[2]), SpokenValueFormatter.text(0.3, unit: .percent(decimals: 0)))
        XCTAssertEqual(Model.display(plasma[1]), "0.12/s")

        let gradient = Model.controls(for: .material(id: "material.gradient"), parameters: [ParameterID("material.gradient.shape"): .enumeration("radial")])
        XCTAssertEqual(gradient.map(\.kind), [.color, .color, .slider, .slider, .slider, .picker])
        XCTAssertEqual(Model.spoken(gradient[5]), "Radial")
        XCTAssertEqual(Model.identifier(gradient[5]), "materialControl.material.gradient.shape")
        XCTAssertTrue(Model.spoken(gradient[0]).hasPrefix("Red 0.02"), Model.spoken(gradient[0]))

        let noise = Model.controls(for: .material(id: "material.noiseFlow"), parameters: [ParameterID("material.noiseFlow.octaves"): .integer(9)])
        XCTAssertEqual(noise[2].kind, .stepper)
        XCTAssertEqual(Model.spoken(noise[2]), "5", "shown clamped, as the layer would store it")
    }

    func testOnlyCatalogMaterialsHaveControls() {
        XCTAssertTrue(Model.controls(for: .material(id: "material.custom"), parameters: [:]).isEmpty)
        XCTAssertTrue(Model.controls(for: .circularSpectrum, parameters: [:]).isEmpty)
    }

    /// The seeded scene's carried Plasma layer carries the generated controls (read-only).
    func testSeededMaterialRowCarriesItsControls() {
        let document = SceneDocument(id: "shd3", name: "SHD-003", layers: UITestLayerInspectorFixture.carriedLayers)
        let rows = LayerInspectorScene.rows(document: document, visual: .photo)
        let material = rows.first { (r: LayerInspectorRow) -> Bool in r.kind == "material" }
        XCTAssertEqual(material?.materialControls.count, 5)
        XCTAssertEqual(material?.isEditable, false)
        XCTAssertTrue(rows.filter { (r: LayerInspectorRow) -> Bool in r.kind != "material" }.allSatisfy { $0.materialControls.isEmpty })
    }
}
