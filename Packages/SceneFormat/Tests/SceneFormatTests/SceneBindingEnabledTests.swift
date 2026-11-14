// SceneBindingEnabledTests.swift — MOD-012-T03 (MOD-012-R5, S3; contract modulation-matrix M3): a binding's
// enabled flag round-trips through the scene document, is written only when false, and absent means enabled; a
// disabled layer is restored (kept in its place) and skipped by the fold.
import ParameterGraph
@testable import SceneFormat
import VisualParameters
import XCTest

final class SceneBindingEnabledTests: XCTestCase {
    static let intensity: ParameterID = VisualParameterIDs.bloomIntensity

    static func layers() -> [AudioFeatureBinding] {
        [AudioFeatureBinding(source: .kick, target: intensity, outputStart: 0.6, outputEnd: 0.6, mixMode: .replace),
         AudioFeatureBinding(source: .lfo(0), target: intensity, outputStart: 0.5, outputEnd: 0.5, mixMode: .multiply, isEnabled: false)]
    }

    func testEnabledFlagRoundTripsAndIsWrittenOnlyWhenOff() throws {
        let registry = try SceneFixtures.registry()
        let document = SceneDocument(id: SceneFixtures.sceneID, name: "Enabled",
                                     bindings: SceneBinding.list(Self.layers(), expressions: [:]))
        let json = try SceneJSON.parse(document.encoded())
        let stored: [SceneJSON] = try XCTUnwrap(json.objectValue?["bindings"]?.arrayValue)
        XCTAssertNil(stored[0].objectValue?["enabled"], "an enabled binding is stored as before")
        XCTAssertEqual(stored[1].objectValue?["enabled"], .bool(false))
        let decoded = try SceneDocument.decode(document.encoded()).document
        XCTAssertEqual(decoded.bindings.map(\.isEnabled), [true, false])
        XCTAssertEqual(decoded.bindings[1].extra, [:], "the field is known, not carried as extra")
        let loaded = try decoded.liveState(registry: registry)
        XCTAssertEqual(loaded.modulationReport.entries.map(\.outcome), [.restored, .restored], "a disabled layer is restored")
        XCTAssertEqual(loaded.state.bindings, Self.layers())
        let saved = try SceneDocument(capturing: loaded.state, id: SceneFixtures.sceneID, name: "Enabled")
        XCTAssertEqual(saved.encoded(), document.encoded(), "capture writes it back byte for byte")
        let modulator = AudioFeatureModulator(registry: registry)
        for b in loaded.state.bindings { try modulator.addLayer(b) }
        XCTAssertEqual(modulator.value(for: Self.intensity, manual: 0.1), 0.6, accuracy: 1e-15, "the disabled multiply is skipped")
    }

    func testAbsentMeansEnabledAndOtherTypesAreMalformed() throws {
        func scene(_ enabled: String?) -> [UInt8] {
            let field: String = enabled.map { (e: String) -> String in ",\"enabled\":" + e } ?? ""
            let text: String = "{\"format\":\"projectm-ios.scene\",\"version\":1,\"id\":\"\(SceneFixtures.sceneID)\",\"name\":\"N\","
                + "\"layers\":[],\"parameters\":{},\"assets\":{},\"bindings\":[{\"source\":\"audio.kick\","
                + "\"target\":\"effect.bloom.intensity\",\"output\":{\"start\":0,\"end\":1}" + field + "}]}"
            return Array(text.utf8)
        }
        XCTAssertEqual(try SceneDocument.decode(scene(nil)).document.bindings.first?.isEnabled, true, "absent means enabled")
        XCTAssertEqual(try SceneDocument.decode(scene("true")).document.bindings.first?.isEnabled, true)
        XCTAssertEqual(try SceneDocument.decode(scene("false")).document.bindings.first?.isEnabled, false)
        XCTAssertThrowsError(try SceneDocument.decode(scene("\"no\""))) { (error: Error) in
            guard case let .malformed(path, _)? = error as? SceneDecodeError else { return XCTFail("\(error)") }
            XCTAssertEqual(path, "$.bindings[0].enabled")
        }
    }
}
