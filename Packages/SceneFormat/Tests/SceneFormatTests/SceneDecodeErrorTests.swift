// SceneDecodeErrorTests.swift — every decode refusal with its exact message (SCN-001-T15, T17;
// SCN-001-S3; contract C4), version handling and count limits.
import Foundation
@testable import SceneFormat
import XCTest

final class SceneDecodeErrorTests: XCTestCase {
    private func refusal(_ bytes: [UInt8]) -> SceneDecodeError? {
        do {
            _ = try SceneDocument.decode(bytes)
            return nil
        } catch {
            return error
        }
    }

    private func refusal(_ text: String) -> SceneDecodeError? { refusal(text.bytes) }

    /// The minimal document with `field` replaced by raw JSON text.
    private func minimal(_ field: String, _ json: String) -> String {
        var o = (try? SceneFixtures.json(SceneFixtures.minimalText).objectValue) ?? [:]
        o[field] = .string("@@")
        return o.isEmpty ? "" : SceneJSON.object(o).canonicalBytes.text.replacingOccurrences(of: "\"@@\"", with: json)
    }

    func testRefusalsHaveExactMessages() {
        let cases: [(String, [UInt8], String)] = [
            ("empty", [], "The file is empty."),
            ("too large (white space only, so size is checked before parsing)", [UInt8](repeating: 0x20, count: 1_048_577),
             "The scene is 1048577 bytes; scenes are at most 1048576 bytes."),
            ("not JSON", "{".bytes, "The scene is not valid JSON at byte 1: expected a key."),
            ("binary", [0x7F, 0x45, 0x4C, 0x46], "The scene is not valid JSON at byte 0: unexpected character."),
            ("too deep", minimal("futureDeep", String(repeating: "[", count: 32) + String(repeating: "]", count: 32)).bytes,
             "The scene nests deeper than 32 levels."),
            ("duplicate key", "{\"name\":\"a\",\"name\":\"b\"}".bytes, "$ has the key \"name\" twice."),
            ("array", "[]".bytes, "The file is not a projectM-iOS scene."),
            ("other format", minimal("format", "\"projectm-ios.generator-graph\"").bytes, "The file is not a projectM-iOS scene."),
            ("newer", minimal("version", "2").bytes,
             "This scene was saved by a newer version of the app (format version 2); this version reads format version 1."),
            ("version 0", minimal("version", "0").bytes, "The scene's format version must be a whole number from 1; found 0."),
            ("version 1.5", minimal("version", "1.5").bytes, "The scene's format version must be a whole number from 1; found 1.5."),
            ("version 1.0", minimal("version", "1.0").bytes, "The scene's format version must be a whole number from 1; found 1.0."),
            ("version text", minimal("version", "\"1\"").bytes, "The scene's format version must be a whole number from 1; found a string."),
            ("layers type", minimal("layers", "{}").bytes, "$.layers: expected an array, found an object."),
            ("name missing", "{\"format\":\"projectm-ios.scene\",\"version\":1,\"id\":\"x\"}".bytes, "$: \"name\" is required."),
            ("kind missing", minimal("layers", "[{\"instance\":1}]").bytes, "$.layers[0]: \"kind\" is required."),
            ("instance negative", minimal("layers", "[{\"instance\":-1,\"kind\":\"camera\"}]").bytes,
             "$.layers[0].instance: the instance ID must be a non-negative whole number."),
            ("content missing", minimal("layers", "[{\"instance\":1,\"kind\":\"photo\"}]").bytes, "$.layers[0].content: the layer's content is required."),
            ("opacity overflow", minimal("layers", "[{\"composite\":{\"opacity\":1e999},\"instance\":1,\"kind\":\"camera\"}]").bytes,
             "$.layers[0].composite.opacity: 1e999 is too large."),
            ("transform version", minimal("layers", "[{\"composite\":{\"transform\":{\"version\":2}},\"instance\":1,\"kind\":\"camera\"}]").bytes,
             "$.layers[0].composite.transform.version: unsupported transform version 2."),
            ("integer as 3.0", minimal("parameters", "{\"visual.circularSpectrum.gap\":{\"kind\":\"integer\",\"value\":3.0}}").bytes,
             "$.parameters[\"visual.circularSpectrum.gap\"].value: 3.0 is not a whole number."),
            ("value kind", minimal("parameters", "{\"a.b\":{\"kind\":\"vector\",\"value\":[1]}}").bytes,
             "$.parameters[\"a.b\"].kind: unknown parameter value kind \"vector\"."),
            ("mix", minimal("bindings", "[{\"mix\":\"blend\",\"output\":{\"end\":1,\"start\":0},\"source\":\"audio.onset\",\"target\":\"a.b\"}]").bytes,
             "$.bindings[0].mix: unknown mix mode \"blend\"."),
            // An unknown audio source (`audio.band.128`) is kept and flagged orphaned since MOD-013
            // (SceneModulationRestoreTests); a missing one is still refused.
            ("source", minimal("bindings", "[{\"output\":{\"end\":1,\"start\":0},\"target\":\"a.b\"}]").bytes,
             "$.bindings[0]: \"source\" is required."),
            ("node", minimal("modulation", "{\"connections\":[{\"source\":{\"id\":\"x\",\"kind\":\"lfo\"},\"target\":{\"id\":\"a.b\",\"kind\":\"parameter\"}}]}").bytes,
             "$.modulation.connections[0].source.kind: unknown node kind \"lfo\"."),
            ("asset type missing", minimal("assets", "{\"a\":{\"storeID\":\"x\"}}").bytes, "$.assets.a: \"type\" is required."),
        ]
        for (name, bytes, message) in cases {
            guard let error = refusal(bytes) else {
                XCTFail("\(name): accepted")
                continue
            }
            XCTAssertEqual(error.message, message, name)
        }
    }

    func testCountLimitsAreCheckedBeforeTypedDecoding() {
        func items(_ n: Int, _ item: (Int) -> String) -> String { "[" + (0..<n).map(item).joined(separator: ",") + "]" }
        func map(_ n: Int, _ item: (Int) -> String) -> String { "{" + (0..<n).map(item).joined(separator: ",") + "}" }
        // Each over-limit list holds items that would not even decode: the count is refused first.
        let cases: [(String, String, String, String)] = [
            ("layers", items(9) { _ in "0" }, items(8) { "{\"instance\":\($0 + 1),\"kind\":\"spectrum.linear\"}" },
             "The scene has 9 layers; at most 8 are allowed."),
            ("bindings", items(33) { _ in "0" }, "[]", "The scene has 33 bindings; at most 32 are allowed."),
            ("parameters", map(1_025) { "\"p.v\($0)\":0" }, map(1_024) { "\"p.v\($0)\":{\"kind\":\"boolean\",\"value\":true}" },
             "The scene has 1025 parameter values; at most 1024 are allowed."),
            ("assets", map(17) { "\"a\($0)\":0" }, map(16) { "\"a\($0)\":{\"type\":\"future\"}" },
             "The scene has 17 assets; at most 16 are allowed."),
            ("modulation", "{\"generators\":" + items(65) { _ in "0" } + "}", "{\"generators\":[]}",
             "The scene has 65 modulation generators; at most 64 are allowed."),
            ("modulation", "{\"connections\":" + items(257) { _ in "0" } + "}", "{\"connections\":[]}",
             "The scene has 257 modulation connections; at most 256 are allowed."),
        ]
        for (field, over, atLimit, message) in cases {
            XCTAssertEqual(refusal(minimal(field, over))?.message, message, field)
            XCTAssertNil(refusal(minimal(field, atLimit)), "\(field) at its limit")
        }
        let values = map(65) { "\"v\($0)\":\"x\"" }
        XCTAssertEqual(refusal(minimal("layers", "[{\"instance\":1,\"kind\":\"camera\",\"values\":\(values)}]"))?.message,
                       "The scene has 65 values in layer 0; at most 64 are allowed.")
    }

    func testOneMebibyteIsAcceptedAndNothingIsParsedBeyondIt() throws {
        // A valid document padded with white space to exactly the limit.
        let base = SceneFixtures.minimalText.bytes
        let padded = base + [UInt8](repeating: 0x20, count: SceneLimits.maximumBytes - base.count)
        XCTAssertEqual(try SceneDocument.decode(padded).document.name, "Empty")
        XCTAssertEqual(refusal(padded + [0x20])?.message, "The scene is 1048577 bytes; scenes are at most 1048576 bytes.")
    }

    func testDecodeWarningsForClampedAndDroppedFields() throws {
        let layer = "[{\"composite\":{\"opacity\":1.5,\"glow\":1,\"transform\":{\"scale\":{\"x\":30,\"y\":1,\"z\":2},\"version\":1}},"
            + "\"content\":{\"note\":1},\"instance\":1,\"kind\":\"camera\"}]"
        let result = try SceneDocument.decode(minimal("layers", layer).bytes)
        XCTAssertEqual(result.warnings.map(\.message), [
            "$.layers[0].composite has the unknown field \"glow\"; it was dropped.",
            "$.layers[0].composite.opacity: 1.5 is outside 0.0…1.0; read as 1.0.",
            "$.layers[0].composite.transform.scale has the unknown field \"z\"; it was dropped.",
            "$.layers[0].composite.transform.scale.x: 30.0 is outside 0.05…20.0; read as 20.0.",
            "$.layers[0] has the unknown field \"content\"; it was dropped.",
        ])
        XCTAssertEqual(result.warnings.map(\.code), [.droppedField, .valueClamped, .droppedField, .valueClamped, .droppedField])
        XCTAssertTrue(result.warnings.allSatisfy { $0.severity == .warning })
        let layer0 = try XCTUnwrap(result.document.layers.first)
        XCTAssertEqual(layer0.composite.opacity, 1)
        XCTAssertEqual(layer0.composite.transform.scale.x, 20)
        // The repaired document is canonical from then on.
        let repaired = result.document.encoded()
        XCTAssertEqual(try SceneDocument.decode(repaired).warnings, [])
    }
}
