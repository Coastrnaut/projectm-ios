// SHD-003-T09, T12, T13 (US1-US3; SHD-003-R1, R4, R5, R6, R7; S1, S3, S4): every bundled material document
// validates, matches the slots its fragment function reads, drives the catalog, and yields one inspector
// control per parameter; on the GPU, Gradient Field's Shape changes the next frame (Radial golden). The CPU
// parts run on Linux; the shader and GPU parts need Metal (skipped without a device).
import ParameterGraph
@testable import ProceduralMaterials
import ShaderParameterMetadata
import XCTest

final class MaterialMetadataTests: XCTestCase {
    func testEveryBundledDocumentValidatesAndDrivesTheCatalog() throws {
        for kind in MaterialKind.allCases {
            let m = try ShaderMetadataReader.validate(json: MaterialParameterMetadata.json(kind), document: kind.id,
                                                      requiredParameters: MaterialParameterMetadata.requiredParameters)
            XCTAssertEqual(m.variant, kind.rawValue)
            let definition = ProceduralMaterialCatalog.definition(kind)
            XCTAssertEqual(definition.metadata, m)
            XCTAssertEqual(definition.displayName, m.name)
            XCTAssertEqual(definition.summary, m.summary)
            XCTAssertEqual(definition.parameters.map(\.id.rawValue), m.parameters.map { (p: ShaderParameterSpec) -> String in kind.id + "." + p.id })
            XCTAssertEqual(definition.parameters.map(\.displayName), m.parameters.map(\.label))
            XCTAssertEqual(definition.parameters.map(\.kind), m.parameters.map(\.kind.parameterKind))
            XCTAssertEqual(definition.parameters.map(\.unit), m.parameters.map(\.unit))
        }
    }

    func testGradientShapeIsAnEnumOnSlotFive() throws {
        let d = ProceduralMaterialCatalog.definition(.gradient)
        let shape = d.parameterID("shape")
        XCTAssertEqual(d.slot(of: shape), 5)
        XCTAssertEqual(d.parameters[5].kind, .enumeration(cases: [ParameterEnumCase(id: "linear", displayName: "Linear"),
                                                                  ParameterEnumCase(id: "radial", displayName: "Radial")],
                                                          defaultValue: "linear"))
        var values = MaterialParameterValues(d)
        XCTAssertEqual(values.slot(5).x, 0)
        try values.set(.enumeration("radial"), for: shape)
        XCTAssertEqual(values.slot(5).x, 1)
        XCTAssertThrowsError(try values.set(.enumeration("spiral"), for: shape))
        XCTAssertEqual(values.value(for: shape), .enumeration("radial"), "an unknown case keeps the stored value")
    }

    /// S3: the controls equal the metadata for every material (29 parameters).
    func testControlsEqualTheMetadata() throws {
        var total = 0
        for kind in MaterialKind.allCases {
            let definition = ProceduralMaterialCatalog.definition(kind)
            let metadata = try XCTUnwrap(definition.metadata)
            let controls = definition.controls(values: [:])
            XCTAssertEqual(controls.map(\.descriptor), definition.parameters, kind.id)
            for (control, spec) in zip(controls, metadata.parameters) {
                XCTAssertEqual(control.label, spec.label)
                switch spec.kind {
                case let .float(minimum, maximum, step, _):
                    XCTAssertEqual(control.kind, .slider)
                    XCTAssertEqual(control.range, minimum...maximum)
                    XCTAssertEqual(control.step, step)
                case let .int(minimum, maximum, step, _):
                    XCTAssertEqual(control.kind, .stepper)
                    XCTAssertEqual(control.range, Double(minimum)...Double(maximum))
                    XCTAssertEqual(control.step, Double(step))
                case .bool:
                    XCTAssertEqual(control.kind, .toggle)
                case let .enumeration(cases, _):
                    XCTAssertEqual(control.kind, .picker)
                    XCTAssertEqual(control.options, cases)
                case .color:
                    XCTAssertEqual(control.kind, .color)
                }
                XCTAssertEqual(control.value, control.defaultValue)
                total += 1
            }
        }
        XCTAssertEqual(total, 29)
    }

    #if canImport(Metal) && !COMPOSITOR_NO_METAL
    /// R4: every document matches the slots its fragment function reads in the module's shader source.
    func testEveryDocumentMatchesItsShaderSlots() throws {
        for kind in MaterialKind.allCases {
            let definition = ProceduralMaterialCatalog.definition(kind)
            let metadata = try XCTUnwrap(definition.metadata)
            let usage = try XCTUnwrap(ShaderSlotUsage.scan(source: ProceduralMaterialShaders.source, function: definition.fragmentFunction))
            XCTAssertFalse(usage.reads.isEmpty, kind.id)
            XCTAssertNoThrow(try metadata.check(against: usage), kind.id)
        }
        // A colour moved to a number's slot is caught against the real source.
        let swapped = MaterialParameterMetadata.gradient
            .replacingOccurrences(of: "\"kind\": \"color\", \"slot\": 0, \"default\": [0.02, 0.04, 0.15, 1]",
                                  with: "\"kind\": \"float\", \"slot\": 0, \"min\": 0, \"max\": 1, \"step\": 0.1, \"default\": 0")
        let bad = try ShaderMetadataReader.validate(json: swapped, document: "material.gradient")
        XCTAssertThrowsError(try bad.check(source: ProceduralMaterialShaders.source, function: "mat_gradient")) { (error: Error) in
            XCTAssertEqual(error as? ShaderMetadataError,
                           .slotTypeMismatch(document: "material.gradient", parameterID: "colorA", slot: 0, kind: "float", read: "a vector"))
        }
    }

    /// S4: Shape set through the inspector's control value changes the next frame; Radial matches its golden
    /// (frame 30, no music, 64 × 64; recorded 2026-11-14 on the Mac Studio host GPU) and Linear keeps SHD-001's.
    func testRadialShapeTakesEffectAndMatchesItsGolden() throws {
        let rig = try MaterialGPURig()
        let linear = try MaterialGPURig.Driver(rig: rig, layer: ProceduralMaterialCatalog.makeLayer(.gradient))
        let layer = ProceduralMaterialCatalog.makeLayer(.gradient)
        let radial = try MaterialGPURig.Driver(rig: rig, layer: layer)
        let control = try XCTUnwrap(layer.definition.controls(values: [:]).first { $0.kind == .picker })
        let choice = try XCTUnwrap(control.options.last)
        XCTAssertEqual(choice.id, "radial")
        for _ in 0...30 { try linear.step() }
        try radial.step()
        try layer.set(.enumeration(choice.id), for: control.id)
        for _ in 0..<30 { try radial.step() }
        let a = try linear.read(), b = try radial.read()
        XCTAssertEqual(invalidPixelCount(b), 0)
        let at = { (p: [Pixel], x: Int, y: Int) -> Float in let q = p[y * 64 + x]; return q.x + q.y + q.z }
        XCTAssertNotEqual(a, b, "the parameter change reached the GPU")
        // Radial: colorA (dark) at the centre, colorB (lighter) at the corners.
        XCTAssertLessThan(at(b, 32, 32), at(b, 2, 2))
        let s = Self.signature(b)
        let text = s.map { (v: Float) -> String in String(format: "%.4f", v) }.joined(separator: ", ")
        XCTAssertEqual(Self.radialGolden.count, s.count, "radial signature: [\(text)]")
        for (i, (e, v)) in zip(Self.radialGolden, s).enumerated() {
            XCTAssertEqual(v, e, accuracy: 0.02, "radial signature value \(i): [\(text)]")
        }
    }

    /// Mean RGB, peak RGB, then pixels (32,32), (8,8), (56,16), (16,56) — SHD-001's signature.
    private static let radialGolden: [Float] = [
        0.1084, 0.0447, 0.1761, 0.1799, 0.0600, 0.2400, 0.0120, 0.0240, 0.0900,
        0.1594, 0.0556, 0.2216, 0.1377, 0.0509, 0.2023, 0.1377, 0.0509, 0.2023,
    ]

    private static func signature(_ pixels: [Pixel]) -> [Float] {
        let mean = pixels.reduce(Pixel.zero, +) / Float(pixels.count)
        let peak = pixels.reduce(Pixel.zero) { (m: Pixel, p: Pixel) -> Pixel in pointwiseMax(m, p) }
        var s: [Float] = [mean.x, mean.y, mean.z, peak.x, peak.y, peak.z]
        for (x, y) in [(32, 32), (8, 8), (56, 16), (16, 56)] {
            let p = pixels[y * 64 + x]
            s += [p.x, p.y, p.z]
        }
        return s
    }
    #endif
}
