// ParticleTrailRenderTests.swift — VIS-010-T07: the trail pass on the real Metal pipeline (VIS-010-R2 to R5, S1 to S3).
// * The acceptance: a 10-minute fixture (36 000 frames at 60 Hz on an injected clock) of the fountain with trails, with
//   output resizes and setting changes, keeps the texture count, identities and total allocated size constant after
//   the first trails-on frame; Off from the start allocates nothing. The clock advances through all 36 000 frames; to
//   stay within the unit-test budget (owner rule 7) the GPU encodes a representative subset: every frame of the first
//   20 s and the last 10 s, every frame within 0.5 s of each resize, setting change and restart, and every 30th frame
//   otherwise (about 3 900 frames; all 36 000 took 64 s). `VIS010_FULL_FIXTURE=1` encodes every frame. The CPU model
//   runs all 36 000 frames in ParticleTrailModelTests.
// * A controlled square stamped once fades on the GPU as the CPU model says, the same at 30 and 120 fps.
// * Continuous over-bright emission never takes the accumulation or the shown trail above 0.8.
// Without a Metal device the tests skip (RenderRig).
#if canImport(Metal) && !VISUAL_NO_METAL
import Metal
import XCTest
@testable import VisualGenerators

final class ParticleTrailRenderTests: XCTestCase {
    private func encode(_ generator: ParticleFountainGenerator, _ target: MTLTexture, _ commands: MTLCommandBuffer, frame: Int) -> Bool {
        let context = VisualFrameContext(timeNanoseconds: UInt64(frame) * 1_000_000_000 / 60, frameDuration: 1.0 / 60, reduceFlashing: false)
        return [Float]().withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> Bool in
            generator.encode(into: target, commandBuffer: commands, bands: b, context: context)
        }
    }

    func testOffFromTheStartAllocatesNoTrailTexture() throws {
        let rig = try RenderRig()
        let generator = try rig.build { try ParticleFountainGenerator(device: rig.device, pixelFormat: .bgra8Unorm_srgb) }
        generator.enqueueOnset(atNanoseconds: 0, strength: 0.6, threshold: 0.1)
        let target = try rig.makeTexture(width: 16, height: 16, format: .bgra8Unorm_srgb)
        for f in 0..<10 {
            let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
            XCTAssertTrue(encode(generator, target, commands, frame: f))
            commands.commit()
            commands.waitUntilCompleted()
        }
        XCTAssertNil(generator.trailPass, "Trails Off: no trail texture exists")
    }

    /// VIS-010-S1: the roadmap row's acceptance.
    func testTenMinuteFixtureKeepsConstantTextureAllocation() throws {
        let rig = try RenderRig()
        let generator = try rig.build { try ParticleFountainGenerator(device: rig.device, pixelFormat: .bgra8Unorm_srgb) }
        generator.trails = .long
        let targets: [MTLTexture] = try [(8, 8), (12, 6), (6, 12)].map { (size: (Int, Int)) -> MTLTexture in
            try rig.makeTexture(width: size.0, height: size.1, format: .bgra8Unorm_srgb)
        }
        let lengths: [ParticleTrailLength] = [.long, .short, .off, .long, .short, .long]
        var identities: [ObjectIdentifier] = []
        var bytes = 0
        var last: MTLCommandBuffer?
        var drawnFrames = 0, checks = 0
        let full = ProcessInfo.processInfo.environment["VIS010_FULL_FIXTURE"] == "1"
        for f in 0..<36_000 {   // 600 s at 60 Hz
            if f % 30 == 0 { generator.enqueueOnset(atNanoseconds: UInt64(f) * 1_000_000_000 / 60, strength: 0.6, threshold: 0.1) }
            if f % 6_000 == 0 { generator.trails = lengths[f / 6_000] }   // a setting change every 100 s
            if f == 18_000 { generator.restartLoop() }
            let target = targets[(f / 3_600) % targets.count]   // a resize every minute
            let nearEvent = f % 3_600 < 30 || f % 3_600 >= 3_570 || f % 6_000 < 30 || f % 6_000 >= 5_970 || abs(f - 18_000) < 30
            guard full || f < 1_200 || f >= 35_400 || nearEvent || f % 30 == 0 else { continue }
            let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
            var drawn = encode(generator, target, commands, frame: f)
            if !drawn, let pending = last {   // no free vertex buffer yet: wait for the GPU and draw the frame
                pending.waitUntilCompleted()
                drawn = encode(generator, target, commands, frame: f)
            }
            XCTAssertTrue(drawn, "frame \(f)")
            commands.commit()
            last = commands
            drawnFrames += 1
            guard let pass = generator.trailPass else {
                XCTAssertEqual(generator.trails, .off, "a pass exists from the first trails-on frame")
                continue
            }
            if identities.isEmpty {
                identities = pass.textures.map { (t: MTLTexture) -> ObjectIdentifier in ObjectIdentifier(t) }
                bytes = pass.allocatedBytes
            }
            XCTAssertEqual(pass.textures.count, 2)
            XCTAssertEqual(pass.textures.map { (t: MTLTexture) -> ObjectIdentifier in ObjectIdentifier(t) }, identities, "frame \(f)")
            XCTAssertEqual(pass.allocatedBytes, bytes, "frame \(f)")
            checks += 1
        }
        last?.waitUntilCompleted()
        XCTAssertEqual(last?.status, .completed)
        XCTAssertEqual(checks, drawnFrames, "checked after every encoded frame (trails were on from frame 0)")
        XCTAssertGreaterThan(drawnFrames, full ? 35_999 : 3_000)
        for texture in generator.trailPass?.textures ?? [] {   // the fixed size and format, on every platform
            XCTAssertEqual([texture.width, texture.height], [ParticleTrails.textureSide, ParticleTrails.textureSide])
            XCTAssertEqual(texture.pixelFormat, .rgba16Float)
        }
        if bytes > 0 {   // the iOS Simulator reports allocatedSize 0; the macOS host reports the real size
            XCTAssertGreaterThanOrEqual(bytes, 2 * ParticleTrails.textureSide * ParticleTrails.textureSide * 8, "two 512² rgba16Float textures")
        }
        XCTAssertGreaterThan(generator.trailPass?.framesWithTrail ?? 0, drawnFrames * 3 / 4, "the trail was drawn, not just reset")
        print("VIS-010 fixture: 600 s clock (36 000 frames), \(drawnFrames) encoded on the GPU, 2 trail textures, \(bytes) bytes, identities constant")
    }

    // MARK: - Controlled stamps through the pass

    private struct Stamp {
        let shapes: FlatShapePass
        let pass: ParticleTrailPass
        let target: MTLTexture
    }

    private func makeStamp(_ rig: RenderRig) throws -> Stamp {
        let shapes = try rig.build { try FlatShapePass(device: rig.device, pixelFormat: .rgba16Float, maximumVertexCount: 6, label: "VIS-010 test") }
        let pass = try rig.build { try ParticleTrailPass(device: rig.device, library: shapes.library, targetFormat: .rgba16Float, label: "VIS-010 test") }
        return Stamp(shapes: shapes, pass: pass, target: try rig.makeTexture(width: 32, height: 32, format: .rgba16Float))
    }

    /// One frame: `color` over the left half of the output when given (else no particles).
    private func frame(_ rig: RenderRig, _ s: Stamp, color: LinearColor?, decay: Double) throws {
        let slot = try XCTUnwrap(s.shapes.freeSlot())
        var count = 0
        if let color {
            let v = s.shapes.vertices(slot)
            let a = SpectrumVertex(x: -1, y: 1, color: color, gain: 1), b = SpectrumVertex(x: 0, y: 1, color: color, gain: 1)
            let c = SpectrumVertex(x: 0, y: -1, color: color, gain: 1), d = SpectrumVertex(x: -1, y: -1, color: color, gain: 1)
            v[0] = a; v[1] = b; v[2] = c; v[3] = a; v[4] = c; v[5] = d
            count = 6
        }
        let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
        XCTAssertTrue(s.pass.encode(shapes: s.shapes, slot: slot, count: count, into: s.target, background: .opaqueBlack,
                                    commandBuffer: commands, decay: decay, gain: 1))
        commands.commit()
        commands.waitUntilCompleted()
        XCTAssertEqual(commands.status, .completed)
    }

    private func accumulation(_ rig: RenderRig, _ s: Stamp, x: Int, y: Int) throws -> Pixel {
        let side = ParticleTrails.textureSide
        let image = rig.decode(try rig.readBack(s.pass.textures[s.pass.newest]), width: side, height: side, format: .rgba16Float)
        return image[x, y]
    }

    private func shown(_ rig: RenderRig, _ s: Stamp, x: Int, y: Int) throws -> Pixel {
        rig.decode(try rig.readBack(s.target), width: 32, height: 32, format: .rgba16Float)[x, y]
    }

    func testAStampFadesAsTheCPUModelSaysAtAnyFrameRate() throws {
        let rig = try RenderRig()
        var values: [Float] = []
        for fps in [30.0, 120.0] {
            let s = try makeStamp(rig)
            let d = ParticleTrails.decay(frameDuration: 1 / fps, halfLife: ParticleTrails.longHalfLife)
            let color = LinearColor(red: 0.8, green: 0.4, blue: 0.2, alpha: 0.8)
            try frame(rig, s, color: color, decay: d)
            let frames = Int((0.5 * fps).rounded())
            for _ in 0..<frames { try frame(rig, s, color: nil, decay: d) }
            let model = ParticleTrailModel(width: 1, height: 1)
            model.beginFrame(decay: d)
            model.stamp(x0: 0, y0: 0, x1: 1, y1: 1, color: SIMD4<Float>(0.8 * 0.8, 0.4 * 0.8, 0.2 * 0.8, 0.8))
            for _ in 0..<frames { model.beginFrame(decay: d) }
            let gpu = try accumulation(rig, s, x: 128, y: 256)
            // Half floats round once per frame (60 roundings at 120 fps): within 3 % of the Float model.
            XCTAssertEqual(gpu.x, model.value(x: 0, y: 0).x, accuracy: 0.03 * model.value(x: 0, y: 0).x, "\(fps) fps: GPU matches the CPU model")
            XCTAssertEqual(gpu.w, model.value(x: 0, y: 0).w, accuracy: 0.03 * model.value(x: 0, y: 0).w)
            XCTAssertEqual(try accumulation(rig, s, x: 384, y: 256), .zero, "the right half was never stamped")
            values.append(gpu.x)
            // The target shows the history before this frame decayed once (= the new accumulation, no particles now).
            XCTAssertEqual(try shown(rig, s, x: 8, y: 16).x, gpu.x, accuracy: 0.002)
        }
        XCTAssertEqual(values[0], values[1], accuracy: 0.01, "VIS-010-S2 on the GPU: 30 vs 120 fps at 0.5 s")
    }

    func testCapHoldsOnTheGPUUnderContinuousEmission() throws {
        let rig = try RenderRig()
        let s = try makeStamp(rig)
        let bright = LinearColor(red: 4, green: 2, blue: 1, alpha: 1)   // over-bright, premultiplied
        for _ in 0..<40 { try frame(rig, s, color: bright, decay: ParticleTrails.maximumDecay) }
        let accumulated = try accumulation(rig, s, x: 100, y: 100)
        XCTAssertLessThanOrEqual(accumulated.max(), ParticleTrails.cap + 0.001, "VIS-010-S3: accumulation ≤ 0.8")
        XCTAssertGreaterThan(accumulated.x, 0.79)
        try frame(rig, s, color: nil, decay: ParticleTrails.maximumDecay)
        XCTAssertLessThanOrEqual(try shown(rig, s, x: 4, y: 4).x, ParticleTrails.cap + 0.001, "shown trail ≤ 0.8")
    }

    func testResizeRestartAndOffClearTheTrailButKeepTheTextures() throws {
        let rig = try RenderRig()
        let orbit = try rig.build { try ParticleOrbitGenerator(device: rig.device, pixelFormat: .bgra8Unorm_srgb) }
        orbit.trails = .short
        let small = try rig.makeTexture(width: 16, height: 16, format: .bgra8Unorm_srgb)
        let wide = try rig.makeTexture(width: 24, height: 12, format: .bgra8Unorm_srgb)
        var ids: [ObjectIdentifier] = []
        for f in 0..<12 {
            let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
            let context = VisualFrameContext(timeNanoseconds: UInt64(f) * 16_666_667, frameDuration: 1.0 / 60, reduceFlashing: false)
            if f == 4 { XCTAssertFalse(try XCTUnwrap(orbit.trailPass).needsReset) }
            if f == 8 { orbit.trails = .off }
            if f == 9 { XCTAssertTrue(try XCTUnwrap(orbit.trailPass).needsReset, "an Off frame forgets the trail"); orbit.trails = .long }
            let target = f < 6 ? small : wide
            let drawn = [Float]().withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> Bool in
                orbit.encode(into: target, commandBuffer: commands, bands: b, context: context)
            }
            XCTAssertTrue(drawn)
            commands.commit()
            commands.waitUntilCompleted()
            let pass = try XCTUnwrap(orbit.trailPass)
            if ids.isEmpty { ids = pass.textures.map { (t: MTLTexture) -> ObjectIdentifier in ObjectIdentifier(t) } }
            XCTAssertEqual(pass.textures.map { (t: MTLTexture) -> ObjectIdentifier in ObjectIdentifier(t) }, ids)
        }
        XCTAssertGreaterThan(orbit.lastVertexCount, 0)
        let before = try XCTUnwrap(orbit.trailPass).framesWithTrail
        orbit.restartLoop()
        XCTAssertTrue(try XCTUnwrap(orbit.trailPass).needsReset, "a loop restart clears the trail")
        // 12 frames: frame 0 (first use), 6 (resize) and 9 (back on after Off) are resets, frame 8 is Off: 8 with a trail.
        XCTAssertEqual(before, 8)
    }
}
#endif
