// ColorSamplerTests.swift — UIX-012-T08, T10: the colour sampler's mode, writes and undo (contract C3). A fake capture
// source delivers frames when the test says so, the timeout runs on a manual scheduler, and a real SCN-010
// `SceneHistoryCoordinator` records the Text visual's spec. No clock, no GPU, no simulator UI.
import Compositor
import Foundation
import FrameCapture
import ParameterGraph
import TextLayer
import XCTest
@testable import projectM_iOS

@MainActor
private final class FakeSource: FrameCaptureSource {
    var handlers: [@MainActor (CapturedPixels?) -> Void] = []
    var cancels = 0
    func captureFrame(_ handler: @escaping @MainActor (CapturedPixels?) -> Void) { handlers.append(handler) }
    func cancelCapture() { cancels += 1 }
    func deliver(_ pixels: CapturedPixels?) { handlers.removeFirst()(pixels) }
}

@MainActor
final class ColorSamplerTests: XCTestCase {
    @MainActor
    private final class Harness {
        var spec: TextOverlaySpec = .default
        let history = SceneHistoryCoordinator()
        let source = FakeSource()
        var context = ColorSamplerCoordinator.Context(source: nil, shownExternally: false, outputLive: true, paused: false, locked: false)
        var announced: [String] = []
        var timers: [@MainActor () -> Void] = []
        var modes: [Bool] = []
        var sampler: ColorSamplerCoordinator!

        init() {
            context.source = source
            history.inputs = { [unowned self] () -> SceneInputs in
                SceneInputs(visual: .text, bars: 64, orientation: .horizontal, spacing: 0.2, glowEnabled: false, glowIntensity: 0.5,
                            glowRadius: 0.5, glowThreshold: 0.5, text: self.spec, photoID: nil, videoID: nil)
            }
            history.carry = { () -> SceneAutosaveCarry in SceneAutosaveFixtures.carry }
            history.apply = { [unowned self] (i: SceneInputs) -> Void in self.spec = i.text }
            history.start(observing: false)
            sampler = ColorSamplerCoordinator(
                context: { [unowned self] () -> ColorSamplerCoordinator.Context in self.context },
                endCoalescing: { [unowned self] () -> Void in self.history.endCoalescing() },
                recordStep: { [unowned self] (label: String) -> Void in self.history.recordStep(label: label) },
                announce: { [unowned self] (text: String) -> Void in self.announced.append(text) },
                schedule: { [unowned self] (_: Double, body: @escaping @MainActor () -> Void) -> Void in self.timers.append(body) })
            sampler.onModeChange = { [unowned self] (started: Bool) -> Void in self.modes.append(started) }
            sampler.placement = SplitOutputPlacement(fullSize: CGSize(width: 100, height: 50), scale: 1, origin: .zero)
        }

        var textColor: ColorSampleTarget {
            ColorSampleTarget.textColor(\.color, key: "textColor", name: "Text color",
                                        get: { [unowned self] () -> TextOverlaySpec in self.spec },
                                        set: { [unowned self] (s: TextOverlaySpec) -> Void in self.spec = s })
        }

        var steps: Int { history.history?.undoSteps.count ?? 0 }
    }

    /// A 2 × 1 sRGB frame: left (51, 102, 153), right (255, 0, 0).
    private static let frame = CapturedPixels(width: 2, height: 1, layout: .sRGBBGRA8TopDown([153, 102, 51, 255, 0, 0, 255, 255]))!

    private func sRGB8(_ c: TextColor) -> [Int] { [c.red, c.green, c.blue].map { (v: Double) -> Int in Int((v * 255).rounded()) } }

    func testTapWritesTheSampledColourAsOneUndoStepAndUndoRestoresIt() {
        let h = Harness()
        h.spec.color = TextColor(red: 1, green: 1, blue: 1, alpha: 0.7)
        h.history.endCoalescing()
        let before: TextColor = h.spec.color
        let stepsBefore: Int = h.steps
        XCTAssertNil(h.sampler.begin(h.textColor))
        XCTAssertTrue(h.sampler.isSampling)
        XCTAssertEqual(h.sampler.message, "Tap the picture to pick Text color.")
        h.sampler.sample(atX: 10, y: 20)   // the left half → pixel (0, 0)
        XCTAssertTrue(h.sampler.isReading)
        h.source.deliver(Self.frame)
        XCTAssertEqual(sRGB8(h.spec.color), [51, 102, 153])
        XCTAssertEqual(h.spec.color.alpha, 0.7, "the control keeps its alpha")
        XCTAssertEqual(h.steps, stepsBefore + 1)
        XCTAssertEqual(h.history.undoLabel, "Sample Text color")
        XCTAssertFalse(h.sampler.isSampling, "one sample ends the mode")
        XCTAssertEqual(h.modes, [true, false])
        XCTAssertEqual(h.announced.last, "Text color set to red 20%, green 40%, blue 60%")
        h.history.undo()
        XCTAssertEqual(h.spec.color, before, "Undo restores the previous colour exactly")
        h.history.redo()
        XCTAssertEqual(sRGB8(h.spec.color), [51, 102, 153])
    }

    func testCancelWritesNothingAndALateFrameIsIgnored() {
        let h = Harness()
        let before: TextOverlaySpec = h.spec
        let stepsBefore: Int = h.steps
        h.sampler.begin(h.textColor)
        h.sampler.sample(atX: 90, y: 10)
        h.sampler.cancel()
        h.source.deliver(Self.frame)   // arrives after Cancel
        XCTAssertEqual(h.spec, before)
        XCTAssertEqual(h.steps, stepsBefore)
        XCTAssertFalse(h.sampler.isSampling)
        XCTAssertEqual(h.modes, [true, false])
    }

    func testTapOutsideThePictureAndFailedReadsKeepTheMode() {
        let h = Harness()
        let before: TextOverlaySpec = h.spec
        h.sampler.begin(h.textColor)
        h.sampler.sample(atX: 120, y: 10)   // beyond the 100-point view
        h.source.deliver(Self.frame)
        XCTAssertEqual(h.sampler.message, ColorSamplerCoordinator.outsidePicture)
        XCTAssertTrue(h.sampler.isSampling)
        h.sampler.sample(atX: 10, y: 10)
        h.source.deliver(nil)   // the GPU work failed
        XCTAssertEqual(h.sampler.message, ColorSamplerCoordinator.readFailed)
        h.sampler.sample(atX: 10, y: 10)
        h.timers.last?()   // no frame within the timeout
        XCTAssertEqual(h.sampler.message, ColorSamplerCoordinator.readFailed)
        XCTAssertEqual(h.source.cancels, 1)
        h.source.deliver(Self.frame)   // the late frame
        XCTAssertEqual(h.spec, before)
        XCTAssertTrue(h.sampler.isSampling)
        XCTAssertFalse(h.sampler.isReading)
    }

    func testRefusalsWhenThereIsNothingToSample() {
        let h = Harness()
        let cases: [(ColorSamplerCoordinator.Context, String)] = [
            (.init(source: nil, shownExternally: false, outputLive: true, paused: false, locked: false), ColorSamplerCoordinator.nothingToSample),
            (.init(source: h.source, shownExternally: true, outputLive: true, paused: false, locked: false), ColorSamplerCoordinator.shownExternally),
            (.init(source: h.source, shownExternally: false, outputLive: false, paused: false, locked: false), ColorSamplerCoordinator.blackedOut),
            (.init(source: h.source, shownExternally: false, outputLive: true, paused: true, locked: false), ColorSamplerCoordinator.paused),
            (.init(source: h.source, shownExternally: false, outputLive: true, paused: false, locked: true), SceneLock.refusalMessage),
        ]
        for (context, reason) in cases {
            h.context = context
            XCTAssertEqual(h.sampler.begin(h.textColor), reason)
            XCTAssertFalse(h.sampler.isSampling)
            XCTAssertEqual(h.announced.last, reason)
        }
        XCTAssertTrue(h.modes.isEmpty)
    }

    /// UIX-007 (US2): the visual drawn at half size from (200, 100); the right pixel is under window (230, 110).
    func testSplitPlacementIsUndoneAndBesideTheOutputIsRejected() {
        let h = Harness()
        h.sampler.placement = SplitOutputPlacement(fullSize: CGSize(width: 100, height: 50), scale: 0.5, origin: CGPoint(x: 200, y: 100))
        h.sampler.begin(h.textColor)
        h.sampler.sample(atX: 190, y: 110)   // left of the scaled output
        h.source.deliver(Self.frame)
        XCTAssertEqual(h.sampler.message, ColorSamplerCoordinator.outsidePicture)
        h.sampler.sample(atX: 230, y: 110)   // view (60, 20) → pixel (1, 0)
        h.source.deliver(Self.frame)
        XCTAssertEqual(sRGB8(h.spec.color), [255, 0, 0])
    }

    func testUnchangedColourRecordsNothingAndLinearTargetsTakeLinearValues() {
        let h = Harness()
        h.spec.color = TextColor(red: 1, green: 0, blue: 0)
        h.history.endCoalescing()
        let steps: Int = h.steps
        h.sampler.begin(h.textColor)
        h.sampler.sample(atX: 90, y: 10)
        h.source.deliver(Self.frame)
        XCTAssertEqual(h.steps, steps, "the same colour adds no step")
        XCTAssertFalse(h.sampler.isSampling)
        // A MOD-001 colour is linear: sRGB 188 is linear 0.5; its alpha is kept.
        var parameter = ParameterColor(red: 0, green: 0, blue: 0, alpha: 0.25)
        let target = ColorSampleTarget.parameterColor(key: "p", name: "Tint", get: { () -> ParameterColor in parameter },
                                                      set: { (c: ParameterColor) -> Void in parameter = c })
        h.sampler.write(SampledColor(red: SampledColor.decode(188.0 / 255), green: 0, blue: 1), to: target)
        XCTAssertEqual(parameter.red, 0.5, accuracy: 0.003)
        XCTAssertEqual(parameter.blue, 1)
        XCTAssertEqual(parameter.alpha, 0.25)
        XCTAssertEqual(target.spokenValue, "red 74%, green 0%, blue 100%")
    }
}
