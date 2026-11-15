// FX-020-T07, T14: the roadmap acceptance "Reorder effects and reload; rendered order and values persist", through the
// golden scene renderer (SCN-001 decode → live state → layers → Compositor with the flash guard on → REC-001 capture).
//
// The animated SHD-001 plasma scene runs with Trails and a strong grade (gamma 2, saturation 0.4) at 10 fps, so the
// decayed trail wins over the darkening plasma in many pixels and the grade's curve treats `grade(d × previous)` (Trails
// first) and `d × grade(previous)` (Color first) differently. A chain Trails → Color is reordered to Color → Trails,
// saved to a file, read back and rendered: the order and values persist, the frame equals Color → Trails rendered
// directly (QA-003 `ImageDiff` with `.exact`) and differs from Trails → Color. A scene that lists the flash guard and the
// tone map first renders exactly as the same chain without them (safety stays last). Skipped without Metal.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Compositor
import Foundation
import GoldenImages
import SceneFormat
import SceneRenderHarness
import XCTest

final class EffectChainSceneTests: XCTestCase {
    private let run = GoldenSceneRun(name: "material-plasma", seed: 1_002, intervalNanoseconds: 100_000_000,
                                     audio: .seededBands(count: 32))
    private let resolution = GoldenResolution(width: 128, height: 96)

    private let grade = SceneEffectEntry(kind: "fx.grade", parameters: [
        "temperature": .double(0.3), "lift": .double(0.02), "gamma": .double(2.0), "gain": .double(1.1),
        "saturation": .double(0.4), "hue": .double(25),
    ])
    private let trails = SceneEffectEntry(kind: "fx.trails", parameters: ["halfLife": .double(0.5)])

    private func renderer() throws -> GoldenSceneRenderer {
        do { return try GoldenSceneRenderer() } catch { throw XCTSkip("No Metal device: \(error)") }
    }

    private func plasma(effects: [SceneEffectEntry]?) throws -> SceneDocument {
        var document = try GoldenSceneRenderer.document(from: GoldenPaths.sceneBytes(run))
        document.effects = effects
        return document
    }

    private func frame(_ r: GoldenSceneRenderer, _ document: SceneDocument, allowEffectWarnings: Bool = false) throws -> GoldenImage {
        let images = try r.render(run: run, document: document, resolution: resolution, allowEffectWarnings: allowEffectWarnings)
        return try XCTUnwrap(images[7])
    }

    func testReorderSaveReloadPersistsOrderValuesAndPicture() throws {
        let r = try renderer()
        // A → B: Trails, then Color.
        let original = try plasma(effects: [trails, grade])
        let trailsFirst = try frame(r, original)

        // Reorder to B → A the way the app does (live order → `entries(over:)`), then save to disk and read back.
        var live = try XCTUnwrap(original.effectSettings)
        XCTAssertEqual(live.order, .standard)
        live.order = live.order.moving(from: [1], to: 0)
        var edited = original
        edited.effects = live.entries(over: original.effects)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("fx020-\(UUID().uuidString).scene.json")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data(edited.encoded()).write(to: file)
        let reloaded = try GoldenSceneRenderer.document(from: [UInt8](try Data(contentsOf: file)))

        // Order and values persist.
        let restored = try XCTUnwrap(reloaded.effectSettings)
        XCTAssertEqual(restored.order.effects, [.grade, .trails, .chromatic, .directionalBlur, .radialBlur, .echo, .mosaic])
        XCTAssertEqual(restored.grade, ColorGrade(temperature: 0.3, lift: 0.02, gamma: 2.0, gain: 1.1, saturation: 0.4, hue: 25))
        XCTAssertEqual(restored.gradeEnabled, true)
        XCTAssertEqual(restored.trails, MotionFeedback(isEnabled: true, halfLifeSeconds: 0.5))
        XCTAssertEqual(reloaded.effects?.map(\.kind), ["fx.grade", "fx.trails"])

        // The rendered order persists: equal to B → A rendered directly, different from A → B.
        let reloadedFrame = try frame(r, reloaded)
        let direct = try frame(r, try plasma(effects: [grade, trails]))
        let same = ImageDiff.compare(expected: direct, actual: reloadedFrame, tolerance: .exact)
        XCTAssertTrue(same.identical, same.summary)
        let other = ImageDiff.compare(expected: trailsFirst, actual: reloadedFrame, tolerance: .exact)
        XCTAssertFalse(other.passed, "Color → Trails must differ from Trails → Color: " + other.summary)
        XCTAssertGreaterThan(other.changedPixels, 100, other.summary)
    }

    func testSafetyEntriesCannotMoveSafety() throws {
        let r = try renderer()
        let hostile = try plasma(effects: [SceneEffectEntry(kind: "fx.flashGuard"), SceneEffectEntry(kind: "fx.toneMap"), grade, trails])
        let read = SceneEffectSettings.read(try XCTUnwrap(hostile.effects))
        XCTAssertEqual(read.settings.order.effects, [.grade, .trails, .chromatic, .directionalBlur, .radialBlur, .echo, .mosaic])
        XCTAssertEqual(read.issues.map(\.code), [.fixedEffectStage, .fixedEffectStage])
        let a = try frame(r, hostile, allowEffectWarnings: true)
        let b = try frame(r, try plasma(effects: [grade, trails]))
        let diff = ImageDiff.compare(expected: b, actual: a, tolerance: .exact)
        XCTAssertTrue(diff.identical, diff.summary)
    }

    func testAbsentChainRendersAsBefore() throws {
        let r = try renderer()
        let plain = try plasma(effects: nil)
        let defaults = try plasma(effects: [SceneEffectEntry(kind: "fx.trails", enabled: false), SceneEffectEntry(kind: "fx.grade")])
        let diff = ImageDiff.compare(expected: try frame(r, plain), actual: try frame(r, defaults), tolerance: .exact)
        XCTAssertTrue(diff.identical, "the default chain draws exactly as no chain: " + diff.summary)
    }

    // MARK: FX-006 chromatic split through the golden renderer (FX-006-S1, S5)

    private func chromatic(_ split: ChromaticSplit) -> SceneEffectEntry {
        SceneEffectSettings(chromatic: split).entries(over: nil)[0]
    }

    func testZeroSplitRendersExactlyAsNoChain() throws {
        let r = try renderer()
        let plain = try frame(r, try plasma(effects: nil))
        let zero = try frame(r, try plasma(effects: [chromatic(ChromaticSplit(isEnabled: true, amount: 0, angleDegrees: 30))]))
        let off = try frame(r, try plasma(effects: [chromatic(ChromaticSplit(isEnabled: false, amount: 0.02))]))
        for image in [zero, off] {
            let diff = ImageDiff.compare(expected: plain, actual: image, tolerance: .exact)
            XCTAssertTrue(diff.identical, "a zero or disabled split is exact pass-through: " + diff.summary)
        }
    }

    func testSplitSaveReloadPersistsValuesAndPicture() throws {
        let r = try renderer()
        let split = ChromaticSplit(isEnabled: true, amount: 0.02, angleDegrees: 45, isRadial: true)
        let document = try plasma(effects: [chromatic(split)])
        let shown = try frame(r, document)
        let reloaded = try GoldenSceneRenderer.document(from: document.encoded())
        XCTAssertEqual(reloaded.effectSettings?.chromatic, split)
        let again = ImageDiff.compare(expected: shown, actual: try frame(r, reloaded), tolerance: .exact)
        XCTAssertTrue(again.identical, again.summary)
        let plain = ImageDiff.compare(expected: try frame(r, try plasma(effects: nil)), actual: shown, tolerance: .exact)
        XCTAssertGreaterThan(plain.changedPixels, 100, "the split changes the picture: " + plain.summary)
    }

    // MARK: FX-007 directional blur through the golden renderer (FX-007-S1, S6)

    private func blurEntry(_ blur: DirectionalBlur) -> SceneEffectEntry {
        SceneEffectSettings(directionalBlur: blur).entries(over: nil)[0]
    }

    func testZeroBlurRendersExactlyAsNoChain() throws {
        let r = try renderer()
        let plain = try frame(r, try plasma(effects: nil))
        let zero = try frame(r, try plasma(effects: [blurEntry(DirectionalBlur(isEnabled: true, radius: 0, angleDegrees: 30))]))
        let off = try frame(r, try plasma(effects: [blurEntry(DirectionalBlur(isEnabled: false, radius: 0.02))]))
        for image in [zero, off] {
            let diff = ImageDiff.compare(expected: plain, actual: image, tolerance: .exact)
            XCTAssertTrue(diff.identical, "a zero or disabled blur is identity: " + diff.summary)
        }
    }

    func testBlurSaveReloadPersistsValuesAndPicture() throws {
        let r = try renderer()
        let blur = DirectionalBlur(isEnabled: true, radius: 0.02, angleDegrees: 45)
        let document = try plasma(effects: [blurEntry(blur)])
        let shown = try frame(r, document)
        let reloaded = try GoldenSceneRenderer.document(from: document.encoded())
        XCTAssertEqual(reloaded.effectSettings?.directionalBlur, blur)
        let again = ImageDiff.compare(expected: shown, actual: try frame(r, reloaded), tolerance: .exact)
        XCTAssertTrue(again.identical, again.summary)
        let plain = ImageDiff.compare(expected: try frame(r, try plasma(effects: nil)), actual: shown, tolerance: .exact)
        XCTAssertGreaterThan(plain.changedPixels, 100, "the blur changes the picture: " + plain.summary)
    }

    // MARK: FX-008 radial blur through the golden renderer (FX-008-S1, S5)

    private func radial(_ blur: RadialBlur) -> SceneEffectEntry {
        SceneEffectSettings(radialBlur: blur).entries(over: nil)[0]
    }

    func testZeroRadialBlurRendersExactlyAsNoChain() throws {
        let r = try renderer()
        let plain = try frame(r, try plasma(effects: nil))
        let zero = try frame(r, try plasma(effects: [radial(RadialBlur(isEnabled: true, strength: 0, focusX: 0.2))]))
        let off = try frame(r, try plasma(effects: [radial(RadialBlur(isEnabled: false, strength: 0.25))]))
        for image in [zero, off] {
            let diff = ImageDiff.compare(expected: plain, actual: image, tolerance: .exact)
            XCTAssertTrue(diff.identical, "a zero or disabled blur is exact pass-through: " + diff.summary)
        }
    }

    func testRadialBlurSaveReloadPersistsValuesAndPicture() throws {
        let r = try renderer()
        let blur = RadialBlur(isEnabled: true, strength: 0.25, focusX: 0.3, focusY: 0.6)
        let document = try plasma(effects: [radial(blur)])
        let shown = try frame(r, document)
        let reloaded = try GoldenSceneRenderer.document(from: document.encoded())
        XCTAssertEqual(reloaded.effectSettings?.radialBlur, blur)
        let again = ImageDiff.compare(expected: shown, actual: try frame(r, reloaded), tolerance: .exact)
        XCTAssertTrue(again.identical, again.summary)
        let plain = ImageDiff.compare(expected: try frame(r, try plasma(effects: nil)), actual: shown, tolerance: .exact)
        XCTAssertGreaterThan(plain.changedPixels, 100, "the blur changes the picture: " + plain.summary)
    }

    // MARK: FX-010 echo through the golden renderer (FX-010-S4, S5)

    private func echoEntry(_ echo: EchoFeedback) -> SceneEffectEntry {
        SceneEffectSettings(echo: echo).entries(over: nil)[0]
    }

    func testInactiveEchoRendersExactlyAsNoChainAndReloads() throws {
        let r = try renderer()
        let plain = try frame(r, try plasma(effects: nil))
        let zero = try frame(r, try plasma(effects: [echoEntry(EchoFeedback(isEnabled: true, count: 0))]))
        let off = try frame(r, try plasma(effects: [echoEntry(EchoFeedback(isEnabled: false, count: 4))]))
        for image in [zero, off] {
            let diff = ImageDiff.compare(expected: plain, actual: image, tolerance: .exact)
            XCTAssertTrue(diff.identical, "0 echoes or a disabled echo is exact pass-through: " + diff.summary)
        }
        let echo = EchoFeedback(isEnabled: true, count: 4, delaySeconds: 0.2, decay: 0.75)
        let document = try plasma(effects: [echoEntry(echo)])
        let shown = try frame(r, document)
        let reloaded = try GoldenSceneRenderer.document(from: document.encoded())
        XCTAssertEqual(reloaded.effectSettings?.echo, echo)
        let again = ImageDiff.compare(expected: shown, actual: try frame(r, reloaded), tolerance: .exact)
        XCTAssertTrue(again.identical, again.summary)
    }
}
#endif
