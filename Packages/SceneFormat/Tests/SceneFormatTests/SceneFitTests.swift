// CMP-006-T14 (US3; CMP-006-S4, R9, R10): the scene format stores a layer's fit as the optional
// `composite.fit` ({"mode", "anchor"}), written only when set; the four names reach the live stack,
// any other name is kept (decode → encode and load → capture), reported and drawn as the default.
// CPU only, runs on Linux.
import Compositor
import Foundation
import ParameterGraph
@testable import SceneFormat
import XCTest

final class SceneFitTests: XCTestCase {
    private let photoIndex = 2   // SceneFixtures.allKinds(): instance 9
    private let videoIndex = 3   // instance 10

    private func scene(photo: SceneFit?, video: SceneFit? = nil) throws -> SceneDocument {
        var document = try SceneFixtures.allKinds()
        document.layers[photoIndex].composite.fit = photo
        document.layers[videoIndex].composite.fit = video
        return document
    }

    private func text(_ document: SceneDocument) -> String { String(decoding: document.encoded(), as: UTF8.self) }

    /// Every captured layer's saved composite equals the original's (the unknown kind is not in the
    /// live stack, so whole-document identity is not what load → capture promises).
    private func assertCompositesKept(_ captured: SceneDocument, _ original: SceneDocument, _ message: String,
                                      file: StaticString = #filePath, line: UInt = #line) {
        var originals: [UInt64: SceneComposite] = [:]
        for l in original.layers { originals[l.instance] = l.composite }
        XCTAssertFalse(captured.layers.isEmpty, message, file: file, line: line)
        for l in captured.layers {
            XCTAssertEqual(l.composite, originals[l.instance], "\(message): layer \(l.instance)", file: file, line: line)
        }
    }

    func testEveryModeAndAnchorSurvivesDecodeLoadCaptureAndEncode() throws {
        let registry = try SceneFixtures.registry()
        for mode in LayerFitMode.allCases {
            let photoFit = SceneFit(mode: mode.rawValue, anchor: LayerPoint(x: 0.5, y: 0))
            let document = try scene(photo: photoFit, video: SceneFit(mode: mode.rawValue))
            let decoded = try SceneDocument.decode(document.encoded())
            XCTAssertEqual(decoded.document.layers[photoIndex].composite.fit, photoFit, "\(mode) decodes")
            XCTAssertEqual(decoded.document.encoded(), document.encoded(), "\(mode): canonical bytes")
            XCTAssertFalse(document.validate(registry: registry).contains { $0.code == .unsupportedFitMode }, "\(mode) is drawn")
            let loaded = try document.liveState(registry: registry)
            let photo = try XCTUnwrap(loaded.state.stack.entry(LayerInstanceID(rawValue: 9)))
            XCTAssertEqual(photo.settings.fit, LayerFit(mode: mode, anchor: LayerPoint(x: 0.5, y: 0)), "\(mode) reaches the live stack")
            XCTAssertEqual(loaded.state.preservedFits, [:])
            let captured = try SceneDocument(capturing: loaded.state, id: document.id, name: document.name)
            XCTAssertEqual(captured.layers[photoIndex].composite.fit, photoFit, "capture writes \(mode)")
            assertCompositesKept(captured, document, "load → capture keeps every composite for \(mode)")
        }
        let saved = text(try scene(photo: SceneFit(mode: "pixelAccurate", anchor: LayerPoint(x: 0.5, y: 0))))
        XCTAssertTrue(saved.contains("\"fit\":{\"anchor\":{\"x\":0.5,\"y\":0.0},\"mode\":\"pixelAccurate\"}")
                      || saved.contains("\"fit\":{\"anchor\":{\"x\":0.5,\"y\":0},\"mode\":\"pixelAccurate\"}"),
                      "the saved form: \(saved)")
    }

    func testASceneWithoutAFitIsUnchangedAndHasNoFitField() throws {
        let document = try SceneFixtures.allKinds()
        XCTAssertFalse(text(document).contains("\"fit\""), "no fit set, no field written")
        let registry = try SceneFixtures.registry()
        let loaded = try document.liveState(registry: registry)
        XCTAssertTrue(loaded.state.stack.entries.allSatisfy { $0.settings.fit == nil }, "layers keep their default")
        let captured = try SceneDocument(capturing: loaded.state, id: document.id, name: document.name)
        assertCompositesKept(captured, document, "load → capture adds no fit")
        XCTAssertFalse(text(captured).contains("\"fit\""))
        XCTAssertEqual(try SceneDocument.decode(document.encoded()).document.encoded(), document.encoded(), "decode → encode byte-identical")
    }

    func testUnknownModesAreKeptReportedAndDrawnAsTheDefault() throws {
        let registry = try SceneFixtures.registry()
        let unknown = SceneFit(mode: "tile", anchor: LayerPoint(x: 0.25, y: 1))
        let document = try scene(photo: unknown)
        let decoded = try SceneDocument.decode(document.encoded())
        XCTAssertEqual(decoded.document.layers[photoIndex].composite.fit, unknown)
        XCTAssertEqual(decoded.document.encoded(), document.encoded(), "decode → encode keeps it")

        let issues = document.validate(registry: registry).filter { $0.code == .unsupportedFitMode }
        XCTAssertEqual(issues.count, 1)
        XCTAssertEqual(issues.first?.path, "$.layers[\(photoIndex)].composite.fit.mode")
        XCTAssertFalse(issues.first?.isError ?? true, "a warning")

        let report = SceneRepairReport(document: document, registry: registry)
        let entry = try XCTUnwrap(report.entries.first { $0.code == "unsupportedFitMode" })
        XCTAssertEqual(entry.group, .valuesAdjusted)
        XCTAssertEqual(entry.severity, .note)

        let loaded = try document.liveState(registry: registry)
        XCTAssertNil(loaded.state.stack.entry(LayerInstanceID(rawValue: 9))?.settings.fit, "drawn as the layer's default")
        XCTAssertEqual(loaded.state.preservedFits, [LayerInstanceID(rawValue: 9): unknown])
        let captured = try SceneDocument(capturing: loaded.state, id: document.id, name: document.name)
        XCTAssertEqual(captured.layers[photoIndex].composite.fit, unknown, "load → capture writes it back")

        // A fit set live wins over the preserved one.
        var live = loaded.state
        var settings = try XCTUnwrap(live.stack.entry(LayerInstanceID(rawValue: 9))).settings
        settings.fit = LayerFit(mode: .fit)
        try live.stack.setSettings(settings, of: LayerInstanceID(rawValue: 9))
        let edited = try SceneDocument(capturing: live, id: document.id, name: document.name)
        XCTAssertEqual(edited.layers[photoIndex].composite.fit, SceneFit(mode: "fit"))
    }

    func testAnchorIsClampedAndMalformedFitsAreRefused() throws {
        func decode(_ fitJSON: String) throws(SceneDecodeError) -> SceneDecodeResult {
            let base = String(decoding: try! scene(photo: SceneFit(mode: "fill")).encoded(), as: UTF8.self)
            let edited = base.replacingOccurrences(of: "\"fit\":{\"anchor\":{\"x\":0.5,\"y\":0.5},\"mode\":\"fill\"}",
                                                   with: "\"fit\":" + fitJSON)
            precondition(edited != base, "the fixture text changed")
            return try SceneDocument.decode(Array(edited.utf8))
        }
        let clamped = try decode("{\"mode\":\"fit\",\"anchor\":{\"x\":-2,\"y\":1.5},\"extra\":true}")
        XCTAssertEqual(clamped.document.layers[photoIndex].composite.fit, SceneFit(mode: "fit", anchor: LayerPoint(x: 0, y: 1)))
        XCTAssertEqual(clamped.warnings.filter { $0.code == .valueClamped }.map(\.path),
                       ["$.layers[\(photoIndex)].composite.fit.anchor.x", "$.layers[\(photoIndex)].composite.fit.anchor.y"])
        XCTAssertEqual(clamped.warnings.filter { $0.code == .droppedField }.count, 1, "the unknown key is dropped")
        let centred = try decode("{\"mode\":\"stretch\"}")
        XCTAssertEqual(centred.document.layers[photoIndex].composite.fit, SceneFit(mode: "stretch"), "anchor defaults to the centre")
        for bad in ["{\"anchor\":{\"x\":0,\"y\":0}}", "{\"mode\":3}", "\"fill\"", "{\"mode\":\"fill\",\"anchor\":[0,0]}"] {
            XCTAssertThrowsError(try decode(bad), "refused: \(bad)") { error in
                guard case .malformed = error as? SceneDecodeError else { return XCTFail("malformed expected, got \(error)") }
            }
        }
    }
}
