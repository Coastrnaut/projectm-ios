// CueTransitionStageTests.swift — XFADE-T05 (specs/167-cue-transitions-on-screen, XFADE-S5): applying a cue with a
// stored 1 s crossfade through `ShowCoordinator` and the app's driver (`CueTransitionStage`) freezes the shown
// compositor's frame and blends it out on the compositor shown after the apply, as AppCoordinator wires it (the
// `applyScene` closure swaps the shown host, then calls `sceneApplied()`). Frames on an injected 60 Hz clock: exactly 59
// blended frames, then the incoming scene alone with the textures back in the pool. Also: Reduce Motion is a cut, and
// an incoming visual that is not compositor-backed is a cut (unsupported). Skipped without Metal; no wall clock.
import Compositor
import Foundation
import Metal
import ParameterGraph
import SceneFormat
import ShowControl
import ShowStorage
import TextLayer
import XCTest
@testable import projectM_iOS

/// Clears its picture to one premultiplied color.
private final class StageSolidLayer: LayerSource {
    let layerName = "solid"
    let fallback = LayerFallback.transparent
    let color: MTLClearColor

    init(_ color: MTLClearColor) { self.color = color }

    func prepare(picture: LayerPictureDescriptor, device: MTLDevice) throws(LayerSourceError) {}

    func render(into picture: MTLTexture, commandBuffer: MTLCommandBuffer, frame: LayerFrameContext,
                audio: LayerAudioContext) throws(LayerSourceError) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = picture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = color
        pass.colorAttachments[0].storeAction = .store
        commandBuffer.makeRenderCommandEncoder(descriptor: pass)?.endEncoding()
    }
}

/// A compositor visual as the app's hosts expose it (the compositor and its queue).
@MainActor
private final class StageTestHost: CompositorVisualHost {
    let compositor: Compositor
    let queue: MTLCommandQueue

    init(device: MTLDevice, pool: TexturePool, color: MTLClearColor) throws {
        compositor = try Compositor(device: device, layers: [StageSolidLayer(color)], texturePool: pool)
        queue = try XCTUnwrap(device.makeCommandQueue())
    }

    func frame(_ k: Int, into output: MTLTexture) throws {
        let commands = try XCTUnwrap(queue.makeCommandBuffer())
        XCTAssertTrue(compositor.composite(into: output, commandBuffer: commands,
                                           presentationTimeNanoseconds: 1_000_000_000 + UInt64(k) * 16_666_667,
                                           contentScale: 2, reduceFlashing: false, audio: .empty))
        commands.commit()
        commands.waitUntilCompleted()
        XCTAssertNil(commands.error)
    }
}

@MainActor
final class CueTransitionStageTests: XCTestCase {
    private var device: MTLDevice!
    private var pool: TexturePool!
    private var output: MTLTexture!

    private func setUpGPU() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal device") }
        self.device = device
        pool = TexturePool(device: device)
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: 64, height: 64, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .private
        output = try XCTUnwrap(device.makeTexture(descriptor: d))
    }

    private func folder() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("CueTransitionStageTests-\(UUID().uuidString)",
                                                                                isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    /// A show with one cue (a Text scene) carrying `transition`, driving `stage`; its apply makes `incoming` the shown
    /// host (nil: a visual that is not compositor-backed) and then calls `sceneApplied()`, as AppCoordinator does.
    private func show(stage: CueTransitionStage, transition: ShowCueTransition, reduceMotion: Bool,
                      onApply: @escaping () -> Void) throws -> ShowCoordinator {
        let show = ShowCoordinator(store: ShowStore(directory: folder()), registry: try SceneArchiveService.appRegistry())
        show.applyScene = { (_: SceneDocument, _: [SceneIssue]) -> [String] in
            onApply()
            stage.sceneApplied()
            return []
        }
        show.announce = { (_: String) in }
        show.transitionDriver = stage
        show.transitionSafety = { () -> (reduceMotion: Bool, reduceFlashing: Bool) in (reduceMotion: reduceMotion, reduceFlashing: false) }
        let look = ShowLook(visual: .text, bars: 64, orientation: .horizontal, spacing: 0.5, glowEnabled: false, glowIntensity: 0.7,
                            glowRadius: 0.03, glowThreshold: 0.4, text: TextOverlaySpec(message: "Two"), photoID: nil, videoID: nil)
        XCTAssertTrue(show.addScene(ShowSceneSnapshot.document(look, id: UUID().uuidString, name: "Two"), label: "Two"))
        XCTAssertTrue(show.setTransition(show.list.cues[0].id, to: transition))
        return show
    }

    func testACueWithAStoredCrossfadeBlendsOnTheRealCompositor() throws {
        try setUpGPU()
        let red = try StageTestHost(device: device, pool: pool, color: MTLClearColor(red: 1, green: 0, blue: 0, alpha: 1))
        let blue = try StageTestHost(device: device, pool: pool, color: MTLClearColor(red: 0, green: 0, blue: 1, alpha: 1))
        var shown: StageTestHost? = red
        let stage = CueTransitionStage()
        stage.shownHost = { () -> (any CompositorVisualHost)? in shown }
        let fade = try ShowCueTransition(type: .crossfade, durationSeconds: 1, easing: .linear)
        let show = try show(stage: stage, transition: fade, reduceMotion: false) { shown = blue }
        try red.frame(0, into: output)

        show.next()
        XCTAssertEqual(stage.outcome, .blended)
        XCTAssertEqual(stage.last?.style, .crossfade)
        XCTAssertTrue(stage.target === blue.compositor, "the transition runs on the compositor shown after the apply")
        XCTAssertTrue(blue.compositor.isOutputTransitioning)
        var transitionFrames = 0
        for k in 1...61 {
            try blue.frame(k, into: output)
            if blue.compositor.isOutputTransitioning || blue.compositor.outputTransitionProgress < 1 { transitionFrames += 1 }
        }
        XCTAssertEqual(blue.compositor.outputTransitionBlendedFrames, 59, "1 s at 60 Hz: frames 1/60 … 59/60 are blends")
        XCTAssertEqual(transitionFrames, 60, "the frozen start frame plus 59 blends")
        XCTAssertFalse(blue.compositor.holdsOutputTransitionTextures, "the frozen frame and blend target are released")
        XCTAssertEqual(stage.probe, "outcome=blended frames=59 progress=1.00 holds=no")
    }

    func testReduceMotionAndAnUnsupportedVisualAreCuts() throws {
        try setUpGPU()
        let red = try StageTestHost(device: device, pool: pool, color: MTLClearColor(red: 1, green: 0, blue: 0, alpha: 1))
        let blue = try StageTestHost(device: device, pool: pool, color: MTLClearColor(red: 0, green: 0, blue: 1, alpha: 1))
        let fade = try ShowCueTransition(type: .crossfade, durationSeconds: 1, easing: .linear)

        var shown: StageTestHost? = red
        let calm = CueTransitionStage()
        calm.shownHost = { () -> (any CompositorVisualHost)? in shown }
        try red.frame(0, into: output)
        let checkedOut = pool.counters.checkedOutTextures
        try show(stage: calm, transition: fade, reduceMotion: true) { shown = blue }.next()
        XCTAssertEqual(calm.outcome, .cut, "Reduce Motion: nothing is frozen")
        XCTAssertFalse(blue.compositor.isOutputTransitioning)
        XCTAssertEqual(pool.counters.checkedOutTextures, checkedOut, "no texture taken for a cut")

        shown = red
        let native = CueTransitionStage()
        native.shownHost = { () -> (any CompositorVisualHost)? in shown }
        try show(stage: native, transition: fade, reduceMotion: false) { shown = nil }.next()   // e.g. to projectM
        XCTAssertEqual(native.outcome, .unsupported, "an incoming visual without a compositor: a cut")
        XCTAssertEqual(pool.counters.checkedOutTextures, checkedOut, "the frozen frame went back to the pool")
    }
}
