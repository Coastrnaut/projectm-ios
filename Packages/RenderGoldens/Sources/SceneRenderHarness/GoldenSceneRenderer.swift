// GoldenSceneRenderer.swift — renders a golden scene's fixed frames and captures them as shown
// (QA-002-R4, R5; contract G2; research D3, D4).
//
// SCN-001 decode → validate → live state; parameters restored into a store from the visual + material
// registry; layers built by `GoldenLayerFactory` and applied as the scene's stack to a fresh
// `Compositor`. Frame n is composited at `start + n × interval` into an rgba16Float output with the
// run's audio bands and flash setting (`reduceFlashing` on: the composite flash guard is active).
// Frame 0 is the warm-up: after it the photo loads and text rasterizations are awaited and the composite
// flash guard's history is reset (frame 0 may or may not have shown them), so captured frames never
// depend on loading speed. Captured frames use REC-001's `requestFrameCapture` (composite
// × the guard's gain) and `FrameColorConversion.rgba8` (8-bit sRGB, straight alpha). Every layer must
// have rendered its own picture on a captured frame, or the run fails.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import AnalysisFeatures
import ColorGradeParameters
import Compositor
import Foundation
import FrameCapture
import GeneratorGraph
import GoldenImages
import Metal
import ParameterGraph
import ProceduralMaterials
import SceneFormat
import VisualParameters

/// Receives captures on Metal's completion thread.
private final class CaptureBox: @unchecked Sendable {
    private let lock = NSLock()
    private var pixels: [Int: CapturedPixels] = [:]
    private var failed: [Int] = []
    let signal = DispatchSemaphore(value: 0)

    func store(_ frame: Int, _ value: CapturedPixels?) {
        lock.lock()
        if let value { pixels[frame] = value } else { failed.append(frame) }
        lock.unlock()
        signal.signal()
    }

    func result(_ frame: Int) -> CapturedPixels? {
        lock.lock()
        defer { lock.unlock() }
        return pixels[frame]
    }
}

public final class GoldenSceneRenderer {
    public let device: MTLDevice
    private let queue: MTLCommandQueue
    private var sharedGraphPipeline: GeneratorGraphPipeline?

    public init() throws(GoldenRenderError) {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { throw .noMetalDevice }
        self.device = device
        self.queue = queue
    }

    /// The registry the app combines: visual parameters (VIS, FX), the material catalog (SHD-001) and the colour
    /// grade (FX-003).
    public static func registry() throws -> ParameterRegistry {
        try ParameterRegistry(descriptors: VisualParameterCatalog.descriptors + ProceduralMaterialCatalog.descriptors
                              + ColorGradeCatalog.descriptors + MotionFeedbackCatalog.descriptors)   // FX-009
    }

    /// Decodes scene bytes strictly: no decode warnings, and validation warnings are refused too.
    public static func document(from bytes: [UInt8]) throws(GoldenRenderError) -> SceneDocument {
        let decoded: SceneDecodeResult
        do {
            decoded = try SceneDocument.decode(bytes)
        } catch {
            throw .sceneInvalid("\(error)")
        }
        guard decoded.warnings.isEmpty else { throw .sceneInvalid("decode warnings: \(decoded.warnings)") }
        return decoded.document
    }

    private func graphPipeline() throws(LayerSourceError) -> GeneratorGraphPipeline {
        if let sharedGraphPipeline { return sharedGraphPipeline }
        let pipeline = try GeneratorGraphPipeline(device: device)
        sharedGraphPipeline = pipeline
        return pipeline
    }

    /// Renders every frame of `run` for `document` at `resolution` and returns the captured frames.
    public func render(run: GoldenSceneRun, document: SceneDocument,
                       resolution: GoldenResolution) throws(GoldenRenderError) -> [Int: GoldenImage] {
        let registry: ParameterRegistry
        do {
            registry = try Self.registry()
        } catch {
            throw .sceneInvalid("registry: \(error)")
        }
        let load: SceneLoadResult
        do {
            load = try document.liveState(registry: registry)
        } catch {
            throw .sceneInvalid("\(error)")
        }
        guard load.warnings.isEmpty else { throw .sceneInvalid("warnings: \(load.warnings)") }
        let store = ParameterStore(registry: registry)
        _ = store.restore(load.state.parameters)

        let layers = try GoldenLayerFactory.build(state: load.state, run: run, store: store, device: device,
                                                  graphPipeline: graphPipeline)
        defer { layers.cleanUp() }
        let compositor: Compositor
        do {
            compositor = try Compositor(device: device)
            let built = layers.byID
            try compositor.apply(load.state.stack) { (entry: LayerStackEntry) throws(LayerSourceError) -> any LayerSource in
                guard let layer = built[entry.id] else { throw .resourceUnavailable("no golden layer for \(entry.id.rawValue)") }
                return layer
            }
        } catch {
            throw .renderFailed("compositor: \(error)")
        }

        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: resolution.width,
                                                         height: resolution.height, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .private
        guard let output = device.makeTexture(descriptor: d) else { throw .renderFailed("output texture") }
        let audio = LayerAudioBuffer()
        let box = CaptureBox()
        let captured = Set(run.capturedFrames)
        for frame in 0..<run.frameCount {
            audio.set(frame: nil, bands: run.audio.bands(frame: frame, seed: run.seed), events: [AnalysisEvent]())
            guard let commands = queue.makeCommandBuffer() else { throw .renderFailed("command buffer") }
            if captured.contains(frame) {
                compositor.requestFrameCapture { (pixels: CapturedPixels?) in box.store(frame, pixels) }
            }
            let encoded = compositor.composite(into: output, commandBuffer: commands,
                                               presentationTimeNanoseconds: run.presentationNanoseconds(frame: frame),
                                               contentScale: 2, reduceFlashing: run.reduceFlashing, audio: audio.context)
            guard encoded else { throw .renderFailed("frame \(frame) was not encoded") }
            commands.commit()
            commands.waitUntilCompleted()
            if let error = commands.error { throw .renderFailed("frame \(frame): \(error)") }
            if frame == 0 {
                // Whether frame 0 already showed a photo or text depends on loading speed; settle them and
                // forget frame 0 in the composite flash guard, so later frames never depend on it.
                layers.settle()
                compositor.resetFlashHistory()
            }
            guard captured.contains(frame) else { continue }
            for i in 0..<compositor.layerCount where compositor.outcome(ofLayer: i) != .rendered {
                throw .renderFailed("frame \(frame): layer \(i) \(compositor.outcome(ofLayer: i))")
            }
            if box.signal.wait(timeout: .now() + 5) == .timedOut { throw .captureFailed("frame \(frame): no capture") }
        }
        var images: [Int: GoldenImage] = [:]
        for frame in run.capturedFrames {
            guard let pixels = box.result(frame) else { throw .captureFailed("frame \(frame)") }
            let rgba8 = FrameColorConversion.rgba8(pixels, policy: .preserveCoverage)
            guard let image = GoldenImage(width: rgba8.width, height: rgba8.height, rgba: rgba8.rgba) else {
                throw .captureFailed("frame \(frame): size")
            }
            images[frame] = image
        }
        return images
    }
}
#endif
