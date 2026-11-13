// ScenePropertyTests.swift — 500 seeded random scenes round-trip (SCN-001-T10; SCN-001-S1).
//
// Fixed seed (SplitMix64), so every run checks the same scenes on every host. Scenes are
// structurally valid documents (any layer kind including unknown ones, extreme doubles, unicode
// strings, preserved unknown fields at every extensible level); semantic validity against a
// registry is not needed for the codec's round trip.
import Compositor
import ParameterGraph
@testable import SceneFormat
import XCTest

struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

struct SceneGenerator {
    var rng: SplitMix64

    mutating func int(_ range: ClosedRange<Int>) -> Int { Int.random(in: range, using: &rng) }
    mutating func bool() -> Bool { Bool.random(using: &rng) }
    mutating func unit() -> Double { Double.random(in: 0...1, using: &rng) }

    /// Any finite double: random bit patterns (subnormals, huge values, −0) or plain fractions.
    mutating func double() -> Double {
        switch int(0...5) {
        case 0: return -0.0
        case 1: return Double(int(-1_000...1_000))
        case 2: return unit()
        default:
            while true {
                let d = Double(bitPattern: rng.next())
                if d.isFinite { return d }
            }
        }
    }

    mutating func string(maxLength: Int = 12) -> String {
        var scalars = String.UnicodeScalarView()
        for _ in 0..<int(0...maxLength) {
            let pick = int(0...9)
            let value: UInt32 = switch pick {
            case 0: UInt32(int(0...0x1F))                       // control characters
            case 1: [0x22, 0x5C, 0x2F].randomElement(using: &rng) ?? 0x22 // quote, backslash, slash
            case 2: UInt32(int(0x80...0x7FF))
            case 3: UInt32(int(0xE000...0xFFFD))
            case 4: UInt32(int(0x10000...0x10FFFF))
            default: UInt32(int(0x20...0x7E))
            }
            if let s = Unicode.Scalar(value) { scalars.append(s) }
        }
        return String(scalars)
    }

    mutating func key() -> String { "future" + String(int(0...999)) + string(maxLength: 4) }

    mutating func json(depth: Int = 0) -> SceneJSON {
        let leafOnly = depth >= 3
        switch int(0...(leafOnly ? 4 : 6)) {
        case 0: return .null
        case 1: return .bool(bool())
        case 2: return .double(double())
        case 3: return .integer(Int64.random(in: Int64.min...Int64.max, using: &rng))
        case 4: return .string(string())
        case 5: return .array((0..<int(0...3)).map { (_: Int) -> SceneJSON in json(depth: depth + 1) })
        default:
            var o: [String: SceneJSON] = [:]
            for _ in 0..<int(0...3) { o[string(maxLength: 6)] = json(depth: depth + 1) }
            return .object(o)
        }
    }

    mutating func extra() -> [String: SceneJSON] {
        var o: [String: SceneJSON] = [:]
        for _ in 0..<int(0...2) { o[key()] = json() }
        return o
    }

    mutating func transform() -> LayerTransform {
        let p = LayerTransform.positionRange, s = LayerTransform.scaleRange
        func inRange(_ r: ClosedRange<Double>, _ g: inout SceneGenerator) -> Double { Double.random(in: r, using: &g.rng) }
        // Valid by construction (finite).
        return (try? LayerTransform(translation: LayerPoint(x: inRange(p, &self), y: inRange(p, &self)),
                                    scale: LayerPoint(x: inRange(s, &self), y: inRange(s, &self)),
                                    rotation: double(), anchor: LayerPoint(x: inRange(p, &self), y: inRange(p, &self)))) ?? .identity
    }

    mutating func content() -> SceneLayerContent {
        switch int(0...8) {
        case 0: return .camera
        case 1: return .circularSpectrum
        case 2: return .linearSpectrum
        case 3: return .photo(asset: string())
        case 4: return .video(asset: string())
        case 5: return .text(asset: string())
        case 6: return .material(id: string())
        case 7: return .generatorGraph(asset: string())
        default: return .unknown(kind: "x" + string())
        }
    }

    mutating func parameterValue() -> ParameterValue {
        switch int(0...4) {
        case 0: return .continuous(double())
        case 1: return .integer(Int.random(in: Int.min...Int.max, using: &rng))
        case 2: return .boolean(bool())
        case 3: return .enumeration(string())
        default: return .color(ParameterColor(red: double(), green: double(), blue: double(), alpha: double()))
        }
    }

    mutating func source() -> AudioFeatureSource {
        switch int(0...3) {
        case 0: return .band(int(0...127))
        case 1: return .bandMean
        case 2: return .onset
        default: return .beatConfidence
        }
    }

    mutating func node() -> ModulationNode {
        switch int(0...2) {
        case 0: return .audio(source())
        case 1: return .parameter(ParameterID(string()))
        default: return .generator(string())
        }
    }

    mutating func document() -> SceneDocument {
        var layers: [SceneLayer] = []
        var instances: Set<UInt64> = []
        for _ in 0..<int(0...SceneLimits.maximumLayers) {
            var id = UInt64.random(in: 0...UInt64.max, using: &rng)
            while !instances.insert(id).inserted { id &+= 1 }
            var values: [String: Double] = [:]
            for _ in 0..<int(0...4) { values[string()] = double() }
            var extra = extra()
            let c = content()
            if case .unknown = c, bool() { extra["content"] = json() }
            layers.append(SceneLayer(instance: id, content: c, values: values,
                                     composite: SceneComposite(opacity: unit(), blendMode: bool() ? "normal" : string(), transform: transform()),
                                     extra: extra))
        }
        var parameters: [ParameterID: ParameterValue] = [:]
        for _ in 0..<int(0...10) { parameters[ParameterID(string())] = parameterValue() }
        var bindings: [SceneBinding] = []
        for _ in 0..<int(0...6) {
            bindings.append(SceneBinding(source: source(), target: ParameterID(string()),
                                         mapping: LinearMapping(inputMinimum: double(), inputMaximum: double(), outputStart: double(), outputEnd: double()),
                                         mix: ModulationMixMode.allCases.randomElement(using: &rng) ?? .replace,
                                         envelope: AudioFeatureEnvelope(attackSeconds: double(), releaseSeconds: double()),
                                         expression: bool() ? string() : nil, extra: extra()))
        }
        var modulation = SceneModulation()
        for _ in 0..<int(0...3) {
            modulation.generators.append(ModulationGenerator(id: string(), displayName: string(),
                                                             inputs: (0..<int(0...2)).map { (_: Int) -> String in string() }))
        }
        for _ in 0..<int(0...3) { modulation.connections.append(SceneConnection(ModulationEdge(source: node(), target: node(), input: string()))) }
        var assets: [String: SceneAsset] = [:]
        for _ in 0..<int(0...5) {
            let kind: SceneAssetKind = switch int(0...4) {
            case 0: .photo(storeID: string())
            case 1: .video(storeID: string())
            case 2: .text(spec: json())
            case 3: .generatorGraph(document: json())
            default: .unknown(type: "x" + string())
            }
            assets[string()] = SceneAsset(kind, extra: extra())
        }
        return SceneDocument(id: string(), name: string(), layers: layers, parameters: parameters, bindings: bindings,
                             modulation: modulation, assets: assets, extra: extra())
    }
}

final class ScenePropertyTests: XCTestCase {
    func testFiveHundredSeededRandomScenesRoundTrip() throws {
        var generator = SceneGenerator(rng: SplitMix64(state: 0x5C4E_0001))
        for n in 0..<500 {
            let original = generator.document()
            let bytes = original.encoded()
            let decoded: SceneDecodeResult
            do {
                decoded = try SceneDocument.decode(bytes)
            } catch {
                return XCTFail("scene \(n): \(error) — \(bytes.text.prefix(300))")
            }
            XCTAssertEqual(decoded.warnings, [], "scene \(n)")
            XCTAssertEqual(decoded.document, original, "scene \(n)")
            XCTAssertEqual(decoded.document.encoded(), bytes, "scene \(n)")
        }
    }
}
