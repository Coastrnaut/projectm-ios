// SHD-004-T06, T09 (US1, US2; SHD-004-R1, R2, R3, R5, S1): the catalog's variants are the documented ones,
// every variant's fragment function matches the shared parameters' slots, and the resolution picks the
// selection or falls back to the default with the right notice. CPU parts run on Linux; the slot check needs
// the Metal-only shader source.
import ParameterGraph
@testable import ProceduralMaterials
import ShaderParameterMetadata
import XCTest

final class MaterialVariantCatalogTests: XCTestCase {
    func testCatalogVariants() {
        let expected: [MaterialKind: [String]] = [
            .gradient: ["gradient"], .plasma: ["plasma", "plasmaDetailed"], .noiseFlow: ["noiseFlow", "noiseFlowLite"],
            .tunnel: ["tunnel"], .starfield: ["starfield"],
        ]
        for kind in MaterialKind.allCases {
            let d = ProceduralMaterialCatalog.definition(kind)
            XCTAssertEqual(d.variants.map(\.id), expected[kind], kind.id)
            XCTAssertEqual(d.defaultVariantID, kind.rawValue)
            XCTAssertEqual(d.variants.first?.label, "Standard")
            XCTAssertNil(d.variants.first?.requires, "\(kind.id): the default runs everywhere")
            XCTAssertEqual(d.fragmentFunction(for: d.defaultVariantID), d.fragmentFunction)
        }
        let plasma = ProceduralMaterialCatalog.definition(.plasma)
        XCTAssertEqual(plasma.variant("plasmaDetailed"), ShaderVariantSpec(id: "plasmaDetailed", label: "Detailed", requires: .apple9))
        XCTAssertEqual(ProceduralMaterialCatalog.definition(.noiseFlow).variant("noiseFlowLite"),
                       ShaderVariantSpec(id: "noiseFlowLite", label: "Low cost"))
        XCTAssertNil(plasma.variant("noiseFlowLite"))
    }

    /// SHD-004-D4: every branch of the resolution; the selection is an input only.
    func testResolution() {
        let plasma = ProceduralMaterialCatalog.definition(.plasma)
        let v = plasma.variants
        let family8 = MaterialGPUCapabilities(families: [.apple7, .apple8])
        XCTAssertEqual(MaterialVariantResolution.resolve(selection: nil, variants: v, capabilities: .none, built: nil),
                       MaterialVariantResolution(drawn: "plasma"))
        XCTAssertEqual(MaterialVariantResolution.resolve(selection: "plasma", variants: v, capabilities: .none, built: nil),
                       MaterialVariantResolution(drawn: "plasma"))
        XCTAssertEqual(MaterialVariantResolution.resolve(selection: "plasmaDetailed", variants: v, capabilities: .all, built: nil),
                       MaterialVariantResolution(drawn: "plasmaDetailed"))
        XCTAssertEqual(MaterialVariantResolution.resolve(selection: "plasmaDetailed", variants: v, capabilities: family8, built: nil),
                       MaterialVariantResolution(drawn: "plasma", notice: .unsupported(variant: "plasmaDetailed", requires: .apple9)))
        XCTAssertEqual(MaterialVariantResolution.resolve(selection: "plasmaUltra", variants: v, capabilities: .all, built: nil),
                       MaterialVariantResolution(drawn: "plasma", notice: .unknownVariant("plasmaUltra")))
        XCTAssertEqual(MaterialVariantResolution.resolve(selection: "plasmaDetailed", variants: v, capabilities: .all, built: ["plasma"]),
                       MaterialVariantResolution(drawn: "plasma", notice: .pipelineUnavailable("plasmaDetailed")))
        // A variant without a requirement runs on any GPU.
        let noise = ProceduralMaterialCatalog.definition(.noiseFlow)
        XCTAssertEqual(noise.resolveVariant("noiseFlowLite", capabilities: .none), MaterialVariantResolution(drawn: "noiseFlowLite"))
        XCTAssertTrue(MaterialVariantNotice.unsupported(variant: "plasmaDetailed", requires: .apple9).message.contains("Apple GPU family 9"))
    }

    #if canImport(Metal) && !COMPOSITOR_NO_METAL
    /// SHD-004-R2: every variant's function exists and reads only the shared parameters' slots, as declared.
    func testEveryVariantMatchesItsShaderSlots() throws {
        for kind in MaterialKind.allCases {
            let definition = ProceduralMaterialCatalog.definition(kind)
            let metadata = try XCTUnwrap(definition.metadata)
            for variant in definition.variants {
                let function: String = definition.fragmentFunction(for: variant.id)
                let usage = try XCTUnwrap(ShaderSlotUsage.scan(source: ProceduralMaterialShaders.source, function: function), function)
                XCTAssertFalse(usage.reads.isEmpty, function)
                XCTAssertNoThrow(try metadata.check(against: usage), function)
            }
        }
    }
    #endif
}
