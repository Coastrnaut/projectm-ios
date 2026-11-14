// RenderSoakDriver.swift — the scene render soak (QA-006-R1 to R5, R7, R10; research QA-006-D1 to D6;
// specs/155-qa-006-render-soak/contracts/render-soak.md S1-S6).
//
// QA-002's fixture scenes are built anew from their documents (`GoldenSceneRenderer.buildScene`) and
// switched through CMP-014's `SceneTransitionBus` every `dwellFrames` frames (crossfades, every
// `cutEvery`-th switch a cut); every scene compositor and the bus share one PERF-004 `TexturePool`.
// Frame n is presented at start + n × interval (an injected clock) with QA-002's seeded fixture bands,
// encoded into an `rgba16Float` target, committed and awaited, so the soak runs as fast as the GPU
// allows. Per frame it reads `MTLDevice.currentAllocatedSize`; per dwell end the pool's checked-out
// textures and the live scene compositors (weak references); per cycle (every scene shown once) the
// memory high-water mark. Errors (build, encode, command buffer, PERF-014 faults) are counted, never
// thrown. At the end the bus and every scene are dropped and what is still checked out or alive is
// recorded. `RenderSoakRecorder` (Compositor) decides. An injected leak proves the detector.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import AnalysisFeatures
import Compositor
import Foundation
import GoldenImages
import Metal
import SceneFormat

/// One fixture scene of a soak: its run settings and document.
public struct RenderSoakScene {
    public let run: GoldenSceneRun
    public let document: SceneDocument

    public init(run: GoldenSceneRun, document: SceneDocument) {
        self.run = run
        self.document = document
    }

    public var name: String { run.name }
}

/// A deliberate leak for the negative controls (research QA-006-D6), injected at every cycle start.
public enum RenderSoakLeak: String, Sendable, Equatable {
    case none
    /// One output-sized texture checked out of the shared pool and never returned.
    case pooledTexturePerCycle
    /// One output-sized texture made by the device (not pooled) and kept.
    case deviceTexturePerCycle
}

/// A soak's settings (data-model "RenderSoakConfiguration").
public struct RenderSoakConfiguration {
    public var name: String
    public var scenes: [RenderSoakScene]
    public var resolution: GoldenResolution
    public var frames: Int
    public var dwellFrames: Int
    public var transitionSeconds: Double
    /// Every `cutEvery`-th switch is a cut (0: never).
    public var cutEvery: Int
    public var seed: UInt64
    public var startNanoseconds: UInt64
    public var frameIntervalNanoseconds: UInt64
    public var bandCount: Int
    public var tolerance: RenderSoakTolerance
    public var leak: RenderSoakLeak

    public init(name: String, scenes: [RenderSoakScene], resolution: GoldenResolution = GoldenResolution(width: 128, height: 96),
                frames: Int = 1_800, dwellFrames: Int = 30, transitionSeconds: Double = 0.25, cutEvery: Int = 3,
                seed: UInt64 = 6_006, startNanoseconds: UInt64 = 1_000_000_000, frameIntervalNanoseconds: UInt64 = 16_666_667,
                bandCount: Int = 32, tolerance: RenderSoakTolerance = .standard, leak: RenderSoakLeak = .none) {
        self.name = name
        self.scenes = scenes
        self.resolution = resolution
        self.frames = frames
        self.dwellFrames = max(1, dwellFrames)
        self.transitionSeconds = transitionSeconds
        self.cutEvery = cutEvery
        self.seed = seed
        self.startNanoseconds = startNanoseconds
        self.frameIntervalNanoseconds = max(1, frameIntervalNanoseconds)
        self.bandCount = bandCount
        self.tolerance = tolerance
        self.leak = leak
    }

    /// Frames for `seconds` of simulated time at this configuration's interval.
    public static func frames(seconds: Double, intervalNanoseconds: UInt64 = 16_666_667) -> Int {
        Int((seconds * 1e9 / Double(intervalNanoseconds)).rounded())
    }

    public var simulatedSeconds: Double { Double(frames) * Double(frameIntervalNanoseconds) / 1e9 }

    /// Frames per cycle (every scene shown once).
    public var cycleFrames: Int { dwellFrames * max(1, scenes.count) }
}

/// A weak reference, for counting objects still alive.
private final class WeakBox {
    weak var object: AnyObject?

    init(_ object: AnyObject) { self.object = object }
}

/// A scene the bus may still hold.
private final class SoakHolder {
    let name: String
    let scene: GoldenBuiltScene

    init(name: String, scene: GoldenBuiltScene) {
        self.name = name
        self.scene = scene
    }
}

/// The running state of one soak (one thread drives it).
private final class SoakState {
    let configuration: RenderSoakConfiguration
    var recorder: RenderSoakRecorder
    var holders: [SoakHolder] = []
    var compositors: [WeakBox] = []
    var layers: [WeakBox] = []
    var leaked: [MTLTexture] = []
    var leakedBytes = 0
    var currentScene = ""
    var switches = 0
    var cycleHighWater = 0
    var memory = 0

    init(configuration: RenderSoakConfiguration) {
        self.configuration = configuration
        recorder = RenderSoakRecorder(tolerance: configuration.tolerance)
    }

    func error(_ frame: Int, _ message: String, scene: String? = nil) {
        recorder.record(error: RenderSoakError(frame: frame, scene: scene ?? currentScene, message: message))
    }

    var liveCompositors: Int {
        compositors.reduce(0) { (n: Int, b: WeakBox) -> Int in b.object == nil ? n : n + 1 }
    }

    var liveLayers: Int {
        layers.reduce(0) { (n: Int, b: WeakBox) -> Int in b.object == nil ? n : n + 1 }
    }

    /// PERF-014 faults of a scene leaving the soak (QA-006-D5).
    func collectFaults(_ holder: SoakHolder, frame: Int) {
        let health = holder.scene.compositor.health
        for _ in 0..<health.faultCount {
            error(frame, "render health fault: \(health.lastReason.map { (r: RenderFaultReason) -> String in "\(r)" } ?? "unknown")",
                  scene: holder.name)
        }
    }
}

public final class RenderSoakDriver {
    public let renderer: GoldenSceneRenderer
    private let queue: MTLCommandQueue

    public init(renderer: GoldenSceneRenderer) throws(GoldenRenderError) {
        guard let queue = renderer.device.makeCommandQueue() else { throw .noMetalDevice }
        self.renderer = renderer
        self.queue = queue
    }

    public var device: MTLDevice { renderer.device }

    /// The platform's name in reports.
    public static var platform: String {
        #if targetEnvironment(simulator)
        return "iOS Simulator"
        #elseif os(iOS)
        return "iOS"
        #else
        return "macOS"
        #endif
    }

    /// Runs one soak (contract S1-S6). Render errors are counted in the report, never thrown.
    public func run(_ configuration: RenderSoakConfiguration) -> RenderSoakReport {
        let started = Date()
        let state = SoakState(configuration: configuration)
        let usesDevice = device.currentAllocatedSize > 0
        loop(state, usesDevice: usesDevice)
        let cycles = configuration.scenes.isEmpty ? 0 : configuration.frames / configuration.cycleFrames
        let settings: [String: String] = [
            "scenes": configuration.scenes.map { (s: RenderSoakScene) -> String in s.name }.joined(separator: ","),
            "dwellFrames": "\(configuration.dwellFrames)",
            "transitionSeconds": "\(configuration.transitionSeconds)",
            "cutEvery": "\(configuration.cutEvery)",
            "seed": "\(configuration.seed)",
            "frameIntervalNanoseconds": "\(configuration.frameIntervalNanoseconds)",
            "leak": configuration.leak.rawValue,
            "renderCaching": "on",
            "reduceFlashing": "on",
        ]
        return RenderSoakReport(name: configuration.name, platform: Self.platform,
                                memorySource: usesDevice ? "deviceAllocatedSize" : "poolEstimate",
                                width: configuration.resolution.width, height: configuration.resolution.height,
                                frames: configuration.frames, simulatedSeconds: configuration.simulatedSeconds,
                                wallSeconds: Date().timeIntervalSince(started), switches: state.switches, cycles: cycles,
                                settings: settings, recorder: state.recorder)
    }

    private func outputDescriptor(_ r: GoldenResolution) -> MTLTextureDescriptor {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: r.width, height: r.height, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .private
        return d
    }

    private func loop(_ state: SoakState, usesDevice: Bool) {
        let c = state.configuration
        let pool = TexturePool(device: device)
        var bus: SceneTransitionBus?
        do {
            bus = try SceneTransitionBus(device: device, texturePool: pool)
        } catch {
            state.error(0, "transition bus: \(error)")
        }
        guard let output = device.makeTexture(descriptor: outputDescriptor(c.resolution)) else {
            state.error(0, "output texture")
            return
        }
        let audio = LayerAudioBuffer()
        let bands = GoldenAudio.seededBands(count: c.bandCount)
        let crossfade = (try? SceneTransitionSpec(style: .crossfade, durationSeconds: c.transitionSeconds)) ?? .defaultCrossfade
        if let live = bus, !c.scenes.isEmpty {
            for frame in 0..<c.frames {
                autoreleasepool {
                    if frame % c.dwellFrames == 0 { switchScene(state, frame: frame, bus: live, pool: pool, crossfade: crossfade) }
                    audio.set(frame: nil, bands: bands.bands(frame: frame, seed: c.seed), events: [AnalysisEvent]())
                    renderFrame(state, frame: frame, bus: live, output: output, audio: audio, pool: pool, usesDevice: usesDevice)
                }
            }
            finishCycle(state, frame: c.frames, pool: pool)
        }
        // S6: drop everything, then see what is left.
        for holder in state.holders { state.collectFaults(holder, frame: c.frames) }
        state.holders.removeAll()
        bus = nil
        let leftover = pool.counters.checkedOutTextures
        state.recorder.record(release: RenderSoakRelease(checkedOutTextures: leftover, liveObjects: state.liveCompositors + state.liveLayers))
    }

    /// S1, S3, S4: dwell end, cycle end, leak, then the next scene (a cut or a crossfade).
    private func switchScene(_ state: SoakState, frame: Int, bus: SceneTransitionBus, pool: TexturePool,
                             crossfade: SceneTransitionSpec) {
        let c = state.configuration
        let switchIndex = frame / c.dwellFrames
        let sceneCount = c.scenes.count
        if switchIndex > 0 {
            recordDwell(state, switchIndex: switchIndex - 1, pool: pool)
            if switchIndex % sceneCount == 0 { finishCycle(state, frame: frame, pool: pool) }
        }
        if switchIndex % sceneCount == 0 { injectLeak(state, pool: pool) }
        let scene = c.scenes[switchIndex % sceneCount]
        let built: GoldenBuiltScene
        do {
            built = try renderer.buildScene(run: scene.run, document: scene.document, texturePool: pool)
        } catch {
            state.error(frame, "build: \(error)", scene: scene.name)
            return
        }
        state.holders.append(SoakHolder(name: scene.name, scene: built))
        state.compositors.append(WeakBox(built.compositor))
        for layer in built.layers.byID.values { state.layers.append(WeakBox(layer)) }
        state.currentScene = scene.name
        if switchIndex == 0 || (c.cutEvery > 0 && switchIndex % c.cutEvery == 0) {
            bus.show(built.compositor)
        } else {
            bus.transition(to: built.compositor, spec: crossfade, reduceMotion: false)
        }
        if switchIndex > 0 { state.switches += 1 }
    }

    private func renderFrame(_ state: SoakState, frame: Int, bus: SceneTransitionBus, output: MTLTexture, audio: LayerAudioBuffer,
                             pool: TexturePool, usesDevice: Bool) {
        let c = state.configuration
        let time = c.startNanoseconds + UInt64(frame) * c.frameIntervalNanoseconds
        guard let commands = queue.makeCommandBuffer() else {
            state.error(frame, "command buffer")
            return
        }
        let encoded = bus.encodeFrame(into: output, commandBuffer: commands, presentationTimeNanoseconds: time, contentScale: 2,
                                      reduceFlashing: true, audio: audio.context)
        if !encoded { state.error(frame, "frame not encoded") }
        commands.commit()
        commands.waitUntilCompleted()
        if let error = commands.error { state.error(frame, "command buffer: \(error.localizedDescription)") }
        // S2: release scenes the bus no longer holds.
        let kept = state.holders.filter { (h: SoakHolder) -> Bool in
            h.scene.compositor === bus.liveScene || h.scene.compositor === bus.outgoingScene
        }
        if kept.count != state.holders.count {
            for h in state.holders where !kept.contains(where: { (k: SoakHolder) -> Bool in k === h }) {
                state.collectFaults(h, frame: frame)
                h.scene.layers.cleanUp()
            }
            state.holders = kept
        }
        let memory = usesDevice ? device.currentAllocatedSize : pool.counters.liveBytes + state.leakedBytes
        state.memory = memory
        state.cycleHighWater = max(state.cycleHighWater, memory)
    }

    private func recordDwell(_ state: SoakState, switchIndex: Int, pool: TexturePool) {
        let counters = pool.counters
        state.recorder.record(dwell: RenderSoakDwellSample(cycle: switchIndex / state.configuration.scenes.count,
                                                           scene: state.currentScene,
                                                           checkedOutTextures: counters.checkedOutTextures,
                                                           checkedOutBytes: counters.checkedOutBytes,
                                                           liveScenes: state.liveCompositors))
    }

    /// Records the cycle that ends at `frame` (only complete cycles).
    private func finishCycle(_ state: SoakState, frame: Int, pool: TexturePool) {
        let c = state.configuration
        let cycleFrames = c.cycleFrames
        guard frame > 0, frame % cycleFrames == 0 else { return }
        let cycle = frame / cycleFrames - 1
        guard state.recorder.samples.last.map({ (s: RenderSoakCycleSample) -> Bool in s.cycle < cycle }) ?? true else { return }
        if frame == c.frames, frame % c.dwellFrames == 0 {
            recordDwell(state, switchIndex: frame / c.dwellFrames - 1, pool: pool)   // the last dwell
        }
        let counters = pool.counters
        state.recorder.record(cycle: RenderSoakCycleSample(cycle: cycle, memoryHighWaterBytes: state.cycleHighWater,
                                                           memoryEndBytes: state.memory, poolLiveBytes: counters.liveBytes,
                                                           poolMisses: counters.misses, frames: cycleFrames))
        state.cycleHighWater = 0
    }

    private func injectLeak(_ state: SoakState, pool: TexturePool) {
        let d = outputDescriptor(state.configuration.resolution)
        switch state.configuration.leak {
        case .none:
            return
        case .pooledTexturePerCycle:
            if let t = pool.makeTexture(descriptor: d) { state.leaked.append(t) }
        case .deviceTexturePerCycle:
            if let t = device.makeTexture(descriptor: d) {
                state.leaked.append(t)
                state.leakedBytes += t.allocatedSize > 0 ? t.allocatedSize : TexturePool.estimatedBytes(d)
            }
        }
    }

    // MARK: - Reports

    /// `QA006_REPORT_DIR` when set, else `<tmp>/qa006-render-soak`.
    public static func reportDirectory(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let custom = environment["QA006_REPORT_DIR"], !custom.isEmpty { return URL(fileURLWithPath: custom, isDirectory: true) }
        return FileManager.default.temporaryDirectory.appendingPathComponent("qa006-render-soak", isDirectory: true)
    }

    /// Encodes `report` (sorted keys, pretty) as `<name>.json` in `directory`; returns the file.
    @discardableResult
    public static func write(_ report: RenderSoakReport, to directory: URL = reportDirectory()) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let url = directory.appendingPathComponent("\(report.name).json")
        try encoder.encode(report).write(to: url)
        return url
    }

    /// Simulated seconds from `QA006_SOAK_SECONDS`: nil when unset, empty, not a number or ≤ 0.
    public static func requestedSeconds(environment: [String: String] = ProcessInfo.processInfo.environment) -> Double? {
        guard let text = environment["QA006_SOAK_SECONDS"], let value = Double(text), value.isFinite, value > 0 else { return nil }
        return value
    }
}
#endif
