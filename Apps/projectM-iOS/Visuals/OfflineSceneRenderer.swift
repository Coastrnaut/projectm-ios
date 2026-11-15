// OfflineSceneRenderer.swift — REC-013 the deterministic offline export (specs/240-rec-013-deterministic-offline-export;
// R3 to R7; contract C1, C2; research REC-013-D1, D2, D4, D5, D7, D8).
//
// Frame n (no real clock is read, nothing is paced):
//   1. `OfflineFrameClock`: time n × 1e9 / fps (+ 1 s, as REC-002's stills) and sample round(n × 44,100 / fps);
//   2. `OfflineAnalysisDriver` analyses the audio up to that sample (ANL-016, synchronous, fixed clock) and returns the
//      bands, the waveform histories, the kick and this frame's events;
//   3. ANL-003 smoothing (interval 1 / fps), the event-driven visuals fed as the live host feeds them, then the
//      generator draws (through the FX-001 glow when it is on) into a private `bgra8Unorm_srgb` texture;
//   4. the same command buffer blits the texture into a shared read-back buffer; after it completes the BGRA bytes are
//      hashed (SHA-256) and handed to `OfflineVideoFileWriter` at slot n, then the frame's audio slice
//      [s(n), s(n + 1)); the writer retries a busy encoder, so no frame is dropped.
// Cancel is read before each frame: the writer is cancelled (no MP4 remains) and `.cancelled` thrown. The sidecar is
// written after the MP4 finished. Never touches the screen, the live host or any setting.
import AnalysisFeatures
import CryptoKit
import FlashSafety
import Foundation
import FrameRecording
import Metal
import VisualBandFeed
import VisualEffects
import VisualGenerators
import VisualParameters

enum OfflineExportError: Error, Equatable, CustomStringConvertible {
    case noDevice
    case audioTooShort
    case render(String)
    case writer(String)
    case cancelled

    static let tooShortMessage = "The audio is too short."

    var description: String {
        switch self {
        case .noDevice: "no Metal device"
        case .audioTooShort: Self.tooShortMessage
        case let .render(s): "a frame failed: \(s)"
        case let .writer(s): "the video could not be written: \(s)"
        case .cancelled: "cancelled"
        }
    }
}

/// A finished export.
struct OfflineExportResult: Sendable, Equatable {
    let video: URL
    let sidecar: URL
    let manifest: OfflineExportManifest
}

/// Renders offline exports. `@unchecked Sendable`: one export at a time uses it (the coordinator refuses a second one)
/// and it holds only Metal objects that are safe to use from that task.
final class OfflineSceneRenderer: @unchecked Sendable {
    static let startNanoseconds: UInt64 = 1_000_000_000

    private let device: MTLDevice
    private let queue: MTLCommandQueue

    init() throws(OfflineExportError) {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { throw .noDevice }
        self.device = device
        self.queue = queue
        queue.label = "REC-013 offline export"
    }

    var gpuName: String { device.name }

    /// Renders `job` with `audio` (interleaved stereo, 44.1 kHz) into `folder`. `progress(done, total)` after each frame.
    func export(job: OfflineExportJob, audio: [Float], folder: URL, isCancelled: @Sendable () -> Bool,
                progress: @Sendable (Int, Int) -> Void) async throws -> OfflineExportResult {
        let clock = OfflineFrameClock(fps: job.fps)
        let audioFrames: Int = audio.count / 2
        let total: Int = clock.frameCount(samples: audioFrames)
        guard total >= 2 else { throw OfflineExportError.audioTooShort }
        let videoURL: URL = folder.appendingPathComponent(job.baseName + ".mp4")
        let frame = try OfflineFrameRenderer(device: device, job: job, audio: audio)
        let writer: OfflineVideoFileWriter
        do {
            writer = try OfflineVideoFileWriter(url: videoURL, width: job.width, height: job.height, fps: job.fps, audio: true)
        } catch {
            throw OfflineExportError.writer("\(error)")
        }
        var checksums: [String] = []
        checksums.reserveCapacity(total)
        for n in 0..<total {
            if isCancelled() {
                await writer.cancel()
                throw OfflineExportError.cancelled
            }
            do {
                checksums.append(try render(frame: n, clock: clock, renderer: frame))
            } catch {
                await writer.cancel()
                throw error
            }
            guard await writer.appendFrame(bgra: frame.pixels, bytesPerRow: job.width * 4),
                  await appendAudio(audio, frame: n, clock: clock, writer: writer) else {
                await writer.cancel()
                throw OfflineExportError.writer("frame \(n) was not written")
            }
            progress(n + 1, total)
        }
        if case let .failure(failure) = await writer.finish() { throw OfflineExportError.writer("\(failure)") }
        let manifest = makeManifest(job: job, audio: audio, checksums: checksums)
        let sidecar: URL = folder.appendingPathComponent(job.baseName + ".checksums.json")
        do {
            try manifest.encoded().write(to: sidecar, options: .atomic)
        } catch {
            throw OfflineExportError.writer("\(error)")
        }
        return OfflineExportResult(video: videoURL, sidecar: sidecar, manifest: manifest)
    }

    /// Draws frame `n`, waits for the GPU and returns its checksum (the pixels stay in the read-back buffer).
    private func render(frame n: Int, clock: OfflineFrameClock, renderer: OfflineFrameRenderer) throws -> String {
        guard let commands = queue.makeCommandBuffer() else { throw OfflineExportError.render("no command buffer") }
        let time: UInt64 = Self.startNanoseconds + clock.timeNanoseconds(frame: n)
        try renderer.encode(frame: n, sample: clock.samplePosition(frame: n), timeNanoseconds: time, commands: commands)
        commands.commit()
        commands.waitUntilCompleted()
        if let error = commands.error { throw OfflineExportError.render("\(error)") }
        return renderer.checksum()
    }

    /// Frame `n`'s audio, [s(n), s(n + 1)), after the frame (both inputs advance together; D5).
    private func appendAudio(_ audio: [Float], frame n: Int, clock: OfflineFrameClock, writer: OfflineVideoFileWriter) async -> Bool {
        let frames: Int = audio.count / 2
        let start: Int = min(clock.samplePosition(frame: n), frames)
        let end: Int = min(clock.samplePosition(frame: n + 1), frames)
        guard end > start else { return true }
        return await writer.appendAudio(Array(audio[(start * 2)..<(end * 2)]), startSample: Int64(start))
    }

    private func makeManifest(job: OfflineExportJob, audio: [Float], checksums: [String]) -> OfflineExportManifest {
        let glow: BloomParameters = job.values.glow.limited(by: job.clamp)
        let audioHash: String = audio.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> String in
            OfflineExportManifest.hex(SHA256.hash(data: raw))
        }
        let version: String = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "?"
        return OfflineExportManifest(visual: job.visual.rawValue, options: String(describing: job.drawnStyle),
                                     glow: .init(enabled: glow.enabled, intensity: Double(glow.intensity), radius: Double(glow.radius),
                                                 threshold: Double(glow.threshold)),
                                     reduceFlashing: job.reduceFlashing, safetyProfile: job.safetyProfile, width: job.width,
                                     height: job.height, fps: job.fps, seed: job.seed, audioSource: job.audio.name,
                                     audioSHA256: audioHash, audioFrames: audio.count / 2, gpu: device.name,
                                     osVersion: ProcessInfo.processInfo.operatingSystemVersionString, appVersion: version,
                                     frameChecksums: checksums)
    }
}

/// One export's generator, glow, analysis and read-back (used by one task).
private final class OfflineFrameRenderer {
    let target: MTLTexture
    private let job: OfflineExportJob
    private let generator: any SpectrumTextureGenerator
    private let chain: EffectChain?
    private let driver: OfflineAnalysisDriver
    private let smoother: BandSmoother
    private let readBack: MTLBuffer
    private var trigger = BeatRingTrigger()
    private let flashLimits: FlashEnvelopeConfiguration?

    init(device: MTLDevice, job: OfflineExportJob, audio: [Float]) throws {
        self.job = job
        let barCount: SpectrumBarCount = job.values.barCount
        generator = try NativeSpectrumHost.makeGenerator(device: device, style: job.drawnStyle, barCount: barCount)
        let glow: BloomParameters = job.values.glow.limited(by: job.clamp)
        if glow.isPassThrough {
            chain = nil
        } else {
            let bloom = try BloomEffect(device: device, pixelFormat: .bgra8Unorm_srgb, parameters: glow)
            let made = try EffectChain(device: device, pixelFormat: .bgra8Unorm_srgb, effects: [bloom])
            try made.prepare(width: job.width, height: job.height)
            chain = made
            generator.downstreamLuminance = BloomLuminanceModel(parameters: glow)
        }
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: job.width, height: job.height, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead, .shaderWrite]
        d.storageMode = .private
        guard let texture = device.makeTexture(descriptor: d),
              let buffer = device.makeBuffer(length: job.width * 4 * job.height, options: .storageModeShared) else {
            throw OfflineExportError.render("no \(job.width)×\(job.height) target")
        }
        texture.label = "REC-013 export frame"
        target = texture
        readBack = buffer
        driver = try OfflineAnalysisDriver(interleaved: audio, barCount: barCount)
        smoother = BandSmoother(times: job.smoothing)
        flashLimits = job.clamp.flashLimitsOverride
        configureGenerator()
    }

    /// D7, D8: the seed for the particle visuals, Reduce Motion, the clamped Lissajous persistence.
    private func configureGenerator() {
        let seed = UInt64(job.seed)
        if let fountain = generator as? ParticleFountainGenerator {
            var c = fountain.configuration
            c.seed = seed
            c.reduceMotion = job.reduceMotion
            fountain.configuration = c
            fountain.restartLoop()   // the simulation takes the seed at a restart
        } else if let orbit = generator as? ParticleOrbitGenerator {
            var c = orbit.configuration
            c.seed = seed
            c.reduceMotion = job.reduceMotion
            orbit.configuration = c
            orbit.restartLoop()
        } else if let field = generator as? NoiseFieldGenerator {   // VIS-013: its own seed setting; drift from 0
            var c = field.configuration
            c.reduceMotion = job.reduceMotion
            field.configuration = c
            field.restartLoop()
        } else if let mandala = generator as? MandalaGenerator {
            var c = mandala.configuration
            c.reduceMotion = job.reduceMotion
            mandala.configuration = c
        } else if let lissajous = generator as? LissajousGenerator, case let .lissajous(_, persistence) = job.drawnStyle {
            var c = lissajous.configuration
            c.persistenceHalfLife = LissajousConfiguration.persistenceHalfLife(enabled: persistence, clamp: job.clamp)
            lissajous.configuration = c
        }
    }

    /// Analyses up to `sample` and encodes the frame into `target`, then its read-back.
    func encode(frame n: Int, sample: Int, timeNanoseconds: UInt64, commands: MTLCommandBuffer) throws {
        let analysis: OfflineAnalysisFrame = driver.advance(toSample: sample)
        let context = VisualFrameContext(timeNanoseconds: timeNanoseconds, frameDuration: 1.0 / Double(job.fps),
                                         reduceFlashing: job.reduceFlashing, flashLimits: flashLimits)
        feedEvents(analysis, context: context)
        let interval: Double = n == 0 ? 0 : 1.0 / Double(job.fps)
        let input: [Float] = inputSamples(analysis, interval: interval)
        let drawn: Bool = input.withUnsafeBufferPointer { (values: UnsafeBufferPointer<Float>) -> Bool in
            guard let chain else {
                return generator.encode(into: target, commandBuffer: commands, bands: values, context: context)
            }
            return chain.encode(output: target, commandBuffer: commands) { (image: MTLTexture) -> Bool in
                generator.encode(into: image, commandBuffer: commands, bands: values, context: context)
            }
        }
        guard drawn else { throw OfflineExportError.render("frame \(n) was not drawn") }
        guard let blit = commands.makeBlitCommandEncoder() else { throw OfflineExportError.render("no blit encoder") }
        let rowBytes: Int = target.width * 4
        blit.label = "REC-013 read-back"
        blit.copy(from: target, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: target.width, height: target.height, depth: 1), to: readBack,
                  destinationOffset: 0, destinationBytesPerRow: rowBytes, destinationBytesPerImage: rowBytes * target.height)
        blit.endEncoding()
    }

    /// The oscilloscope and radial waveform draw the mono history, the Lissajous the stereo one, the rest the smoothed bands.
    private func inputSamples(_ analysis: OfflineAnalysisFrame, interval: Double) -> [Float] {
        if job.drawnStyle.drawsMonoHistory { return analysis.mono }
        if case .lissajous = job.drawnStyle { return analysis.stereo }
        let bands: [Float] = analysis.bands
        return bands.withUnsafeBufferPointer { (raw: UnsafeBufferPointer<Float>) -> [Float] in
            Array(smoother.update(target: raw.baseAddress!, count: raw.count, frameInterval: interval, generation: analysis.session))
        }
    }

    /// VIS-006/008/009, as `NativeSpectrumHost.drainBeatEvents` and `driveParticleOrbit` (no modulation; D8).
    private func feedEvents(_ analysis: OfflineAnalysisFrame, context: VisualFrameContext) {
        if let fountain = generator as? ParticleFountainGenerator {
            for event in analysis.events {
                guard let onset = ParticleFountainTrigger.onset(event) else { continue }
                fountain.enqueueOnset(atNanoseconds: context.timeNanoseconds, strength: onset.strength, threshold: onset.threshold)
            }
        } else if let orbit = generator as? ParticleOrbitGenerator {
            for event in analysis.events where trigger.shouldEmit(event) {
                orbit.enqueueBeat(atNanoseconds: context.timeNanoseconds)
            }
            let resolved = ParticleOrbitRadiusDrive.resolve(manual: orbit.configuration.radius, kick: Double(analysis.kickEnvelope),
                                                            modulator: nil)
            orbit.drive(base: resolved.base, bass: resolved.bass)
        } else if let rings = generator as? BeatRingGenerator {
            for event in analysis.events where trigger.shouldEmit(event) {
                rings.emitRing(atNanoseconds: context.timeNanoseconds, flashConfiguration: context.flashConfiguration)
            }
        }
    }

    /// The last frame's BGRA bytes (after the GPU finished).
    var pixels: UnsafeRawPointer { UnsafeRawPointer(readBack.contents()) }

    /// SHA-256 (lowercase hex) of the last frame's BGRA bytes, top-down, tightly packed (D4). After the GPU finished.
    func checksum() -> String {
        let raw = UnsafeRawBufferPointer(start: readBack.contents(), count: target.width * 4 * target.height)
        return OfflineExportManifest.hex(SHA256.hash(data: raw))
    }
}
