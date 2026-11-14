// CMP-008-T11 (US3; CMP-008-S4, R7-R9): the scene format stores a layer's gradient mask as the optional
// `composite.gradientMask`, written only when set; known kinds reach the live stack (beside a shape mask), an
// unknown kind is kept verbatim (decode → encode and load → capture), reported and not drawn; out-of-range values
// are clamped, stops re-sorted with a warning; a bad stop count or a zero-length linear gradient drops it.
// CPU only, runs on Linux.
import Compositor
import Foundation
import ParameterGraph
@testable import SceneFormat
import XCTest

final class SceneGradientMaskTests: XCTestCase {
    private let photoIndex = 2   // SceneFixtures.allKinds(): instance 9
    private let videoIndex = 3   // instance 10
    private let photoID = LayerInstanceID(rawValue: 9)

    private static func gradients() throws -> [LayerGradientMask] {
        [
            try LayerGradientMask(kind: .linear(start: LayerPoint(x: 0.1, y: 0.2), end: LayerPoint(x: 0.9, y: 0.75)),
                                  stops: [LayerGradientStop(position: 0, alpha: 1), LayerGradientStop(position: 0.4, alpha: 0.25),
                                          LayerGradientStop(position: 0.4, alpha: 0.75), LayerGradientStop(position: 1, alpha: 0)]),
            try LayerGradientMask(kind: .radial(center: LayerPoint(x: 0.123456789, y: 0.6), radius: 0.85),
                                  stops: [LayerGradientStop(position: 0.1, alpha: 0), LayerGradientStop(position: 0.5, alpha: 1),
                                          LayerGradientStop(position: 0.9, alpha: 0.3)]),
        ]
    }

    private func scene(photo: SceneGradientMask?, photoMask: SceneMask? = nil, video: SceneGradientMask? = nil) throws -> SceneDocument {
        var document = try SceneFixtures.allKinds()
        document.layers[photoIndex].composite.gradientMask = photo
        document.layers[photoIndex].composite.mask = photoMask
        document.layers[videoIndex].composite.gradientMask = video
        return document
    }

    private func text(_ document: SceneDocument) -> String { String(decoding: document.encoded(), as: UTF8.self) }

    private func gradientText(_ g: SceneGradientMask) -> String {
        String(decoding: SceneJSONWriter.write(SceneEncoder.gradientMask(g)), as: UTF8.self)
    }

    func testEachKindWithAndWithoutAShapeSurvivesDecodeLoadCaptureAndEncodeByteForByte() throws {
        let registry = try SceneFixtures.registry()
        let circle = try LayerMask(shape: .ellipse, transform: LayerMaskTransform(scale: LayerPoint(x: 0.5, y: 0.5)))
        for gradient in try Self.gradients() {
            for shape in [nil, SceneMask.known(circle)] {
                let name = gradient.kind.kindName + (shape == nil ? "" : " × circle")
                let document = try scene(photo: .known(gradient), photoMask: shape, video: .known(try Self.gradients()[0]))
                let bytes = document.encoded()
                let decoded = try SceneDocument.decode(bytes)
                XCTAssertEqual(decoded.warnings, [], "\(name): no warnings")
                XCTAssertEqual(decoded.document.layers[photoIndex].composite.gradientMask?.layerGradientMask, gradient, name)
                XCTAssertEqual(decoded.document.encoded(), bytes, "\(name): decode → encode byte for byte")
                XCTAssertFalse(document.validate(registry: registry).contains { $0.code == .unsupportedMaskShape }, "\(name) is drawn")
                let loaded = try document.liveState(registry: registry)
                let photo = try XCTUnwrap(loaded.state.stack.entry(photoID))
                XCTAssertEqual(photo.settings.gradientMask, gradient, "\(name) reaches the live stack")
                XCTAssertEqual(photo.settings.mask, shape?.layerMask, "\(name): the shape beside it")
                XCTAssertEqual(loaded.state.preservedGradientMasks, [:])
                let captured = try SceneDocument(capturing: loaded.state, id: document.id, name: document.name)
                // The fixture holds kinds capture does not rebuild, so compare the layer's composite bytes.
                let before = SceneJSONWriter.write(SceneEncoder.composite(document.layers[photoIndex].composite))
                let after = SceneJSONWriter.write(SceneEncoder.composite(captured.layers[photoIndex].composite))
                XCTAssertEqual(after, before, "\(name): load → capture keeps the composite byte for byte")
                XCTAssertTrue(text(captured).contains("\"gradientMask\":" + gradientText(.known(gradient))), name)
            }
        }
        let saved = gradientText(.known(.linearDefault))
        XCTAssertEqual(saved, "{\"end\":{\"x\":1.0,\"y\":0.5},\"kind\":\"linear\",\"start\":{\"x\":0.0,\"y\":0.5},"
                           + "\"stops\":[{\"alpha\":1.0,\"position\":0.0},{\"alpha\":0.0,\"position\":1.0}]}", "the saved form")
        XCTAssertEqual(gradientText(.known(.radialDefault)),
                       "{\"center\":{\"x\":0.5,\"y\":0.5},\"kind\":\"radial\",\"radius\":0.5,"
                           + "\"stops\":[{\"alpha\":1.0,\"position\":0.0},{\"alpha\":0.0,\"position\":1.0}]}")
    }

    func testASceneWithoutAGradientIsUnchangedAndHasNoField() throws {
        let document = try SceneFixtures.allKinds()
        XCTAssertFalse(text(document).contains("\"gradientMask\""))
        let loaded = try document.liveState(registry: try SceneFixtures.registry())
        XCTAssertTrue(loaded.state.stack.entries.allSatisfy { $0.settings.gradientMask == nil })
        let captured = try SceneDocument(capturing: loaded.state, id: document.id, name: document.name)
        XCTAssertFalse(text(captured).contains("\"gradientMask\""))
        XCTAssertEqual(try SceneDocument.decode(document.encoded()).document.encoded(), document.encoded())
        XCTAssertEqual(SceneDocument.currentVersion, 1, "no format version change")
    }

    func testUnknownKindsAreKeptReportedAndNotDrawn() throws {
        let registry = try SceneFixtures.registry()
        let object: [String: SceneJSON] = ["kind": .string("conic"), "angle": .double(0.5), "stops": .array([.integer(1)])]
        let unknown = SceneGradientMask.unknown(kind: "conic", object: object)
        let circle = try LayerMask(shape: .ellipse)
        let document = try scene(photo: unknown, photoMask: .known(circle))
        let decoded = try SceneDocument.decode(document.encoded())
        XCTAssertEqual(decoded.warnings, [], "kept, not dropped")
        XCTAssertEqual(decoded.document.layers[photoIndex].composite.gradientMask, unknown)
        XCTAssertEqual(decoded.document.encoded(), document.encoded())

        let issues = document.validate(registry: registry).filter { $0.code == .unsupportedMaskShape }
        XCTAssertEqual(issues.map(\.path), ["$.layers[\(photoIndex)].composite.gradientMask.kind"])
        XCTAssertFalse(issues.first?.isError ?? true)
        let report = SceneRepairReport(document: document, registry: registry)
        let entry = try XCTUnwrap(report.entries.first { $0.code == "unsupportedMaskShape" })
        XCTAssertEqual(entry.severity, .note)

        let loaded = try document.liveState(registry: registry)
        let settings = try XCTUnwrap(loaded.state.stack.entry(photoID)).settings
        XCTAssertNil(settings.gradientMask, "not drawn")
        XCTAssertEqual(settings.mask, circle, "its shape still applies")
        XCTAssertEqual(loaded.state.preservedGradientMasks, [photoID: unknown])
        let captured = try SceneDocument(capturing: loaded.state, id: document.id, name: document.name)
        XCTAssertEqual(captured.layers[photoIndex].composite.gradientMask, unknown, "load → capture writes it back")

        // A gradient set live wins over the preserved one.
        var live = loaded.state
        var edited = settings
        edited.gradientMask = .radialDefault
        try live.stack.setSettings(edited, of: photoID)
        let recaptured = try SceneDocument(capturing: live, id: document.id, name: document.name)
        XCTAssertEqual(recaptured.layers[photoIndex].composite.gradientMask, .known(.radialDefault))
    }

    /// Decodes the fixture scene with the photo's gradient replaced by `json`.
    private func decode(_ json: String) throws(SceneDecodeError) -> SceneDecodeResult {
        let marker = SceneGradientMask.known(.linearDefault)
        let base = text(try! scene(photo: marker))
        let edited = base.replacingOccurrences(of: "\"gradientMask\":" + gradientText(marker), with: "\"gradientMask\":" + json)
        precondition(edited != base, "the fixture text changed")
        return try SceneDocument.decode(Array(edited.utf8))
    }

    private let p = "$.layers[2].composite.gradientMask"

    func testOutOfRangeValuesAreClampedStopsSortedAndUnknownKeysDropped() throws {
        let result = try decode("{\"kind\":\"radial\",\"center\":{\"x\":12,\"y\":0.5},\"radius\":40,\"extra\":1,"
                                + "\"stops\":[{\"position\":0.8,\"alpha\":2},{\"position\":-1,\"alpha\":0.5,\"z\":0}]}")
        let gradient = try XCTUnwrap(result.document.layers[photoIndex].composite.gradientMask?.layerGradientMask)
        XCTAssertEqual(gradient.kind, .radial(center: LayerPoint(x: 10, y: 0.5), radius: 20))
        XCTAssertEqual(gradient.stops, [LayerGradientStop(position: 0, alpha: 0.5), LayerGradientStop(position: 0.8, alpha: 1)])
        XCTAssertEqual(Set(result.warnings.filter { $0.code == .valueClamped }.map(\.path)),
                       [p + ".center.x", p + ".radius", p + ".stops[0].alpha", p + ".stops[1].position", p + ".stops"])
        XCTAssertEqual(Set(result.warnings.filter { $0.code == .droppedField }.map(\.path)), [p, p + ".stops[1]"], "extra and z")
        // Defaults: a bare linear gradient reads left → right; a stop without alpha reads 1.
        let bare = try decode("{\"kind\":\"linear\",\"stops\":[{\"position\":0},{\"position\":1,\"alpha\":0}]}")
        XCTAssertEqual(bare.warnings, [])
        XCTAssertEqual(bare.document.layers[photoIndex].composite.gradientMask, .known(.linearDefault))
        // A radial key on a linear gradient is not part of its form.
        let mixed = try decode("{\"kind\":\"linear\",\"radius\":1,\"stops\":[{\"position\":0},{\"position\":1,\"alpha\":0}]}")
        XCTAssertEqual(mixed.warnings.map(\.code), [.droppedField])
        for bad in ["{\"stops\":[]}", "{\"kind\":3}", "\"linear\"", "{\"kind\":\"linear\",\"stops\":{}}",
                    "{\"kind\":\"linear\",\"stops\":[1,2]}", "{\"kind\":\"radial\",\"radius\":\"big\",\"stops\":[{},{}]}"] {
            XCTAssertThrowsError(try decode(bad), "refused: \(bad)") { error in
                guard case .malformed = error as? SceneDecodeError else { return XCTFail("malformed expected, got \(error)") }
            }
        }
    }

    func testUnusableStopListsAndZeroLengthDropTheGradientWithAWarning() throws {
        let nine = (0..<9).map { (k: Int) -> String in "{\"position\":\(Double(k) / 8)}" }.joined(separator: ",")
        let cases: [(String, String)] = [
            ("no stops", "{\"kind\":\"linear\"}"),
            ("one stop", "{\"kind\":\"linear\",\"stops\":[{\"position\":0}]}"),
            ("nine stops", "{\"kind\":\"radial\",\"stops\":[\(nine)]}"),
            ("zero length", "{\"kind\":\"linear\",\"start\":{\"x\":0.3,\"y\":0.3},\"end\":{\"x\":0.3,\"y\":0.3},"
                + "\"stops\":[{\"position\":0},{\"position\":1}]}"),
        ]
        let registry = try SceneFixtures.registry()
        for (name, json) in cases {
            let result = try decode(json)
            XCTAssertNil(result.document.layers[photoIndex].composite.gradientMask, "\(name): dropped")
            let dropped = result.warnings.filter { $0.code == .droppedField }
            XCTAssertEqual(dropped.map(\.path), [p], name)
            XCTAssertTrue(dropped.first?.message.contains("gradient was dropped") ?? false, name)
            let loaded = try result.document.liveState(registry: registry)
            XCTAssertNil(loaded.state.stack.entry(photoID)?.settings.gradientMask, name)
        }
    }
}
