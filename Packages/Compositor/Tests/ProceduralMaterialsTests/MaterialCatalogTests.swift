// SHD-001-T07 (US1; SHD-001-R1, R2, R3, R9, S2): the catalog lists five materials with valid,
// documented, bounded parameters. CPU only; runs on Linux.
import ParameterGraph
import ProceduralMaterials
import XCTest

final class MaterialCatalogTests: XCTestCase {
    private typealias Catalog = ProceduralMaterialCatalog

    /// The data-model table: ID → (minimum, maximum, default) for numbers.
    private let documentedNumbers: [String: (Double, Double, Double)] = [
        "material.gradient.speed": (-0.25, 0.25, 0.02), "material.gradient.brightness": (0, 1, 0.6),
        "material.gradient.audioReactivity": (0, 1, 0.25),
        "material.plasma.scale": (0.5, 8, 2), "material.plasma.speed": (0, 1, 0.12), "material.plasma.brightness": (0, 1, 0.45),
        "material.plasma.saturation": (0, 1, 0.6), "material.plasma.audioReactivity": (0, 1, 0.25),
        "material.noiseFlow.scale": (1, 16, 4), "material.noiseFlow.speed": (0, 1, 0.08), "material.noiseFlow.octaves": (1, 5, 3),
        "material.noiseFlow.brightness": (0, 1, 0.6), "material.noiseFlow.audioReactivity": (0, 1, 0.25),
        "material.tunnel.ringDensity": (2, 24, 8), "material.tunnel.speed": (-1, 1, 0.1), "material.tunnel.contrast": (0, 1, 0.35),
        "material.tunnel.brightness": (0, 1, 0.4), "material.tunnel.audioReactivity": (0, 1, 0.25),
        "material.starfield.density": (0.05, 1, 0.35), "material.starfield.speed": (0, 1, 0.1),
        "material.starfield.starSize": (0.1, 0.9, 0.35), "material.starfield.brightness": (0, 1, 0.7),
        "material.starfield.audioReactivity": (0, 1, 0.25),
    ]
    private let documentedColors: [String: (Double, Double, Double)] = [
        "material.gradient.colorA": (0.02, 0.04, 0.15), "material.gradient.colorB": (0.30, 0.10, 0.40),
        "material.noiseFlow.tint": (0.10, 0.35, 0.45), "material.tunnel.color": (0.85, 0.45, 0.20),
        "material.starfield.color": (0.90, 0.90, 1.00),
    ]

    func testFiveMaterialsInCatalogOrder() {
        XCTAssertEqual(Catalog.materials.map(\.id),
                       ["material.gradient", "material.plasma", "material.noiseFlow", "material.tunnel", "material.starfield"])
        XCTAssertEqual(Catalog.materials.map(\.displayName), ["Gradient Field", "Plasma", "Noise Flow", "Ring Tunnel", "Starfield"])
        for m in Catalog.materials {
            XCTAssertFalse(m.summary.isEmpty, m.id)
            XCTAssertTrue(ParameterID(m.id).isWellFormed, m.id)
            XCTAssertEqual(m.group.id, m.id)
            XCTAssertEqual(m.fragmentFunction, "mat_" + m.kind.rawValue)
            XCTAssertEqual(Catalog.definition(m.kind), m)
        }
    }

    func testRegistryValidates() throws {
        XCTAssertEqual(ParameterRegistry.validate(Catalog.descriptors, retiredIDs: Catalog.retiredIDs), [])
        let registry = try Catalog.makeRegistry()
        XCTAssertEqual(registry.count, 28)
        XCTAssertEqual(registry.groups.map(\.id), Catalog.materials.map(\.id))
    }

    func testParametersArePrefixedBoundedAndComplete() {
        for m in Catalog.materials {
            XCTAssertLessThanOrEqual(m.parameters.count, MaterialDefinition.maximumParameterCount, m.id)
            XCTAssertNotNil(m.slot(of: m.speedParameter), "\(m.id) has a speed")
            XCTAssertNotNil(m.slot(of: m.reactivityParameter), "\(m.id) has an audio reactivity")
            for d in m.parameters {
                XCTAssertTrue(d.id.rawValue.hasPrefix(m.id + "."), d.id.rawValue)
                XCTAssertEqual(d.id.segments.count, 3, d.id.rawValue)
                XCTAssertEqual(d.group, m.group)
                switch d.kind {
                case .continuous:
                    XCTAssertEqual(d.modulation, .continuousDefault, d.id.rawValue)
                case .color, .integer:
                    XCTAssertEqual(d.modulation, .discreteManual, d.id.rawValue)
                default:
                    XCTFail("unexpected kind \(d.kind.name) for \(d.id)")
                }
            }
        }
    }

    /// SHD-001-R9: speeds |speed| ≤ 1 cycle per second; brightness, contrast and colors ≤ 1.
    func testSafetyBounds() {
        for d in Catalog.descriptors {
            let name = d.id.segments.last ?? ""
            switch d.kind {
            case let .continuous(minimum, maximum, _, _, _):
                if name == "speed" { XCTAssertTrue(minimum >= -1 && maximum <= 1, d.id.rawValue) }
                if ["brightness", "contrast", "audioReactivity"].contains(name) {
                    XCTAssertTrue(minimum >= 0 && maximum <= 1, d.id.rawValue)
                }
            case let .color(c):
                XCTAssertTrue(c.isInRange && c.alpha == 1, d.id.rawValue)
            default:
                break
            }
        }
    }

    func testDocumentedDefaultsMatchTheDataModel() {
        XCTAssertEqual(documentedNumbers.count + documentedColors.count, Catalog.descriptors.count)
        for d in Catalog.descriptors {
            switch d.kind {
            case let .continuous(minimum, maximum, value, _, _):
                let doc = documentedNumbers[d.id.rawValue]
                XCTAssertEqual(doc?.0, minimum, d.id.rawValue)
                XCTAssertEqual(doc?.1, maximum, d.id.rawValue)
                XCTAssertEqual(doc?.2, value, d.id.rawValue)
            case let .integer(minimum, maximum, value, _):
                let doc = documentedNumbers[d.id.rawValue]
                XCTAssertEqual(doc?.0, Double(minimum), d.id.rawValue)
                XCTAssertEqual(doc?.1, Double(maximum), d.id.rawValue)
                XCTAssertEqual(doc?.2, Double(value), d.id.rawValue)
            case let .color(c):
                let doc = documentedColors[d.id.rawValue]
                XCTAssertEqual(doc?.0, c.red, d.id.rawValue)
                XCTAssertEqual(doc?.1, c.green, d.id.rawValue)
                XCTAssertEqual(doc?.2, c.blue, d.id.rawValue)
            default:
                XCTFail(d.id.rawValue)
            }
        }
    }

    func testDefaultValuesAreTheDescriptorDefaults() {
        for kind in MaterialKind.allCases {
            let values = Catalog.defaultValues(for: kind)
            let definition = Catalog.definition(kind)
            XCTAssertEqual(values.count, definition.parameters.count)
            for d in definition.parameters { XCTAssertEqual(values[d.id], d.defaultValue, d.id.rawValue) }
            XCTAssertEqual(MaterialParameterValues(definition).values, definition.parameters.map(\.defaultValue))
        }
    }

    /// SHD-001-R3: only exact catalog IDs resolve; nothing is made from other text.
    func testLookupAcceptsOnlyCatalogIDs() {
        for m in Catalog.materials { XCTAssertEqual(Catalog.material(withID: m.id), m) }
        for text in ["", "plasma", "material.", "material.Plasma", "material.plasma ", "material.plasma.speed",
                     "material.custom", "file:///tmp/x.metal", "#include <metal_stdlib>"] {
            XCTAssertNil(Catalog.material(withID: text), text)
        }
    }
}
