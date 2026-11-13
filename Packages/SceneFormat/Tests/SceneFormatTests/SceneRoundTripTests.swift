// SceneRoundTripTests.swift — the row's acceptance: decode and re-encode preserve semantic scene
// content (SCN-001-T09; SCN-001-S1; contract C2, C3).
import Compositor
import ParameterGraph
@testable import SceneFormat
import VisualParameters
import XCTest

final class SceneRoundTripTests: XCTestCase {
    func testAllKindsFixtureRoundTripsSemanticallyAndByteForByte() throws {
        let original = try SceneFixtures.allKinds()
        let bytes = original.encoded()
        let decoded = try SceneDocument.decode(bytes)
        XCTAssertEqual(decoded.warnings, [])
        XCTAssertEqual(decoded.document, original)
        let reencoded = decoded.document.encoded()
        XCTAssertEqual(reencoded, bytes, "canonical bytes must be identical")
        let again = try SceneDocument.decode(reencoded).document
        XCTAssertEqual(again, decoded.document)

        // Spot checks: order, identity, exact numbers, content and preserved unknown content.
        let d = decoded.document
        XCTAssertEqual(d.layers.map(\.instance), [1, 2, 9, 10, 11, 12, 13, 40])
        XCTAssertEqual(d.layers.map(\.kind), ["camera", "spectrum.circular", "photo", "video", "text", "material",
                                              "generator.graph", "particles.v9"])
        XCTAssertEqual(d.layers[2].composite.transform.rotation.bitPattern, (-0.7853981633974483).bitPattern)
        XCTAssertEqual(d.layers[3].composite.opacity.bitPattern, (1.0 / 3.0).bitPattern)
        XCTAssertEqual(d.layers[5].values["mix"]?.bitPattern, (1e-7).bitPattern)
        XCTAssertEqual(d.layers[7].content, .unknown(kind: "particles.v9"))
        XCTAssertEqual(d.layers[7].extra["content"]?.objectValue?["weights"]?.arrayValue?[2], .number(SceneNumber(validatedText: "123456789012345678901")))
        XCTAssertEqual(d.parameters["material.noiseFlow.octaves"], .integer(4))
        XCTAssertEqual(d.bindings.map(\.target.rawValue), ["visual.circularSpectrum.gap", "effect.bloom.intensity"])
        XCTAssertEqual(d.bindings[0].expression, "audio.onset * 2")
        XCTAssertEqual(d.bindings[1].extra["futureCurve"], .string("easeIn"))
        XCTAssertEqual(d.modulation.connections.first?.source, .generator("lfo.one"))
        XCTAssertEqual(d.assets["clip"]?.extra["futureNote"], .string("kept"))
        XCTAssertEqual(d.extra["futureTopLevel"]?.objectValue?["a"], .array([.integer(1), .integer(2)]))
    }

    func testTheFixtureIsValidApartFromItsUnknownKind() throws {
        let issues = try SceneFixtures.allKinds().validate(registry: try SceneFixtures.registry(), assets: FakeAvailability())
        XCTAssertEqual(issues.map(\.code), [.unknownLayerKind])
    }

    func testMinimalCanonicalTextIsReproducedExactly() throws {
        let decoded = try SceneDocument.decode(SceneFixtures.minimalText.bytes).document
        XCTAssertEqual(decoded.encoded().text, SceneFixtures.minimalText)
    }

    func testKeyOrderAndWhiteSpaceDoNotChangeTheScene() throws {
        let original = try SceneFixtures.allKinds()
        // Pretty, reversed-key form of the same content.
        let pretty = Self.prettyReversed(original.json)
        XCTAssertNotEqual(pretty.bytes, original.encoded())
        let decoded = try SceneDocument.decode(pretty.bytes).document
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.encoded(), original.encoded())
    }

    func testSemanticEqualityIsBitExactAndOrderSensitiveWhereItMatters() throws {
        let original = try SceneFixtures.allKinds()
        var negativeZero = original
        negativeZero.layers[1].values["glowBoost"] = -0.0
        var zero = original
        zero.layers[1].values["glowBoost"] = 0
        XCTAssertNotEqual(negativeZero, zero)
        var nextUp = original
        nextUp.parameters[VisualParameterIDs.circularSpectrumGap] = .continuous(0.1.nextUp)
        XCTAssertNotEqual(nextUp, original)
        var swappedLayers = original
        swappedLayers.layers.swapAt(1, 2)
        XCTAssertNotEqual(swappedLayers, original)
        var swappedBindings = original
        swappedBindings.bindings.swapAt(0, 1)
        XCTAssertNotEqual(swappedBindings, original)
        var integerVsContinuous = original
        integerVsContinuous.parameters["material.noiseFlow.octaves"] = .continuous(4)
        XCTAssertNotEqual(integerVsContinuous, original)
        // Rebuilding the maps in another insertion order changes nothing.
        var rebuilt = original
        rebuilt.parameters = Dictionary(uniqueKeysWithValues: original.parameters.sorted { $0.key > $1.key })
        XCTAssertEqual(rebuilt, original)
    }

    /// Writes `value` with white space and keys in reverse byte order (a valid, non-canonical form).
    static func prettyReversed(_ value: SceneJSON, indent: String = "") -> String {
        switch value {
        case let .array(items):
            if items.isEmpty { return "[ ]" }
            return "[\n" + items.map { (v: SceneJSON) -> String in indent + "  " + prettyReversed(v, indent: indent + "  ") }
                .joined(separator: ",\n") + "\n" + indent + "]"
        case let .object(members):
            if members.isEmpty { return "{ }" }
            let keys = members.keys.sorted { SceneJSONWriter.utf8Precedes($1, $0) }
            return "{\n" + keys.map { (k: String) -> String in
                indent + "  " + SceneJSON.string(k).canonicalBytes.text + " : " + prettyReversed(members[k] ?? .null, indent: indent + "  ")
            }.joined(separator: ",\n") + "\n" + indent + "}"
        default:
            return value.canonicalBytes.text
        }
    }
}
