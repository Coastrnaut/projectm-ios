// FluidInkRenderTests.swift — VIS-011-T06 (VIS-011-R1, R3 to R5, R7, R8; S1 to S3; contract C2): fluid ink on the real
// Metal pipeline with an injected clock. A maximum-strength impulse every frame for 60 simulated seconds at 128²: the
// health readback stays finite and within the caps, kinetic energy bounded and not growing, no forced reset. The GPU
// follows the CPU reference solver at 32²; 30 and 120 fps frame clocks give identical fields at shared times; textures
// keep their count, identities and allocated size over resizes, mode switches and restarts. Without Metal they skip.
#if canImport(Metal) && !VISUAL_NO_METAL
import Metal
import VisualFluidReference
import XCTest
@testable import VisualGenerators

final class FluidInkRenderTests: XCTestCase {
    private static let format: MTLPixelFormat = .rgba16Float
    private static let start: UInt64 = 1_000_000_000

    private static func context(frame m: UInt64, fps: UInt64) -> VisualFrameContext {
        VisualFrameContext(timeNanoseconds: start + m * 1_000_000_000 / fps, frameDuration: 1.0 / Double(fps), reduceFlashing: false)
    }

    private func encode(_ generator: NoiseFieldGenerator, into target: MTLTexture, _ commands: MTLCommandBuffer,
                        _ context: VisualFrameContext) -> Bool {
        let bands = [Float](repeating: 0, count: 64)
        return bands.withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> Bool in
            generator.encode(into: target, commandBuffer: commands, bands: b, context: context)
        }
    }

    /// The acceptance on the GPU (VIS-011-S1).
    func testRepeatedStrongImpulsesStayStableOnTheGPU() throws {
        let rig = try RenderRig()
        let generator = try rig.build {
            try NoiseFieldGenerator(device: rig.device, pixelFormat: Self.format, configuration: .fluidInk(palette: .spectrum))
        }
        let target = try rig.makeTexture(width: 32, height: 32, format: Self.format)
        let cap = FluidInk.speedCap
        var energies: [Float] = []
        var worst = FluidInkHealth()
        var commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
        let fps: UInt64 = 60
        for m: UInt64 in 0...(60 * fps) {
            let context = Self.context(frame: m, fps: fps)
            generator.enqueueImpulse(atNanoseconds: context.timeNanoseconds, strength: 1, threshold: 0)
            XCTAssertTrue(encode(generator, into: target, commands, context))
            if m % 30 == 29 {   // two health samples per second
                commands.commit()
                commands.waitUntilCompleted()
                XCTAssertEqual(commands.status, .completed)
                let pass = try XCTUnwrap(generator.fluidPass)
                pass.pollHealth(speedCap: cap)
                let h = try XCTUnwrap(pass.lastHealth)
                energies.append(h.kineticEnergy)
                worst.maxSpeed = max(worst.maxSpeed, h.maxSpeed)
                worst.maxInk = max(worst.maxInk, h.maxInk)
                worst.kineticEnergy = max(worst.kineticEnergy, h.kineticEnergy)
                worst.nonFinite = worst.nonFinite || h.nonFinite
                commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
            }
        }
        commands.commit()
        commands.waitUntilCompleted()
        XCTAssertEqual(generator.fluidScheduler.totalSteps, 3600)
        XCTAssertEqual(generator.fluidHealthResets, 0, "the health check never had to act")
        XCTAssertFalse(worst.nonFinite)
        XCTAssertLessThanOrEqual(worst.maxSpeed, cap * 1.001)
        XCTAssertLessThanOrEqual(worst.maxInk, FluidInk.inkCap)
        XCTAssertGreaterThan(worst.maxInk, 0.3)
        XCTAssertLessThanOrEqual(worst.kineticEnergy, FluidInkHealth.energyBound(speedCap: cap))
        XCTAssertEqual(energies.count, 120)
        let last = energies.suffix(20).reduce(0, +) / 20
        let before = energies.dropLast(20).suffix(20).reduce(0, +) / 20
        XCTAssertLessThanOrEqual(last, 1.25 * before, "energy \(before) → \(last)")
        print("VIS-011 GPU 60 s of max impulses: max speed \(worst.maxSpeed), max ink \(worst.maxInk), energy max \(worst.kineticEnergy), "
              + "mean \(before) → \(last)")
    }

    /// Runs `frames` frames of a pass at `gridSize` with impulses from `impulse(m)`; returns the fields after completion.
    private func runPass(_ rig: RenderRig, gridSize: Int, fps: UInt64, frames: UInt64, impulse: (UInt64) -> Bool,
                         solver: FluidInkSolver? = nil) throws -> (velocity: [SIMD2<Float>], ink: [SIMD4<Float>]) {
        let probe = try rig.build {
            try NoiseFieldGenerator(device: rig.device, pixelFormat: Self.format, configuration: .fluidInk())
        }
        let pass = try FluidInkPass(device: rig.device, library: probe.library, targetFormat: Self.format, gridSize: gridSize)
        let scheduler = FluidStepScheduler()
        for k in 0..<FluidStepScheduler.paletteCount { scheduler.palette[k] = SIMD3<Float>(Float(k) / 15, 0.6, 1 - Float(k) / 15) }
        let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
        for m: UInt64 in 0...frames {
            let t = Self.start + m * 1_000_000_000 / fps
            if impulse(m) { scheduler.enqueue(atNanoseconds: t, strength: 1, threshold: 0) }
            let steps = scheduler.advance(toNanoseconds: t)
            XCTAssertTrue(pass.encode(scheduler: scheduler, speedCap: FluidInk.speedCap, commandBuffer: commands, target: nil, gain: 1))
            if let solver {
                for s in 0..<steps {
                    let splats = (0..<scheduler.splatCount(step: s)).map { (k: Int) -> FluidSplat in scheduler.splat(step: s, k) }
                    solver.step(splats: splats, speedCap: FluidInk.speedCap)
                }
            }
        }
        let fields = try XCTUnwrap(pass.copyFields(commandBuffer: commands))
        commands.commit()
        commands.waitUntilCompleted()
        XCTAssertEqual(commands.status, .completed)
        let n = gridSize * gridSize
        let v = Array(UnsafeBufferPointer(start: fields.velocity.contents().bindMemory(to: SIMD2<Float>.self, capacity: n), count: n))
        let k = Array(UnsafeBufferPointer(start: fields.ink.contents().bindMemory(to: SIMD4<Float>.self, capacity: n), count: n))
        return (v, k)
    }

    /// The GPU runs the reference solver's algorithm (VIS-011-R4): 1 s at 32², impulses every 5 frames.
    func testGPUFollowsTheReferenceSolver() throws {
        let rig = try RenderRig()
        let solver = FluidInkSolver(gridSize: 32)
        let gpu = try runPass(rig, gridSize: 32, fps: 60, frames: 60, impulse: { (m: UInt64) -> Bool in m % 5 == 0 }, solver: solver)
        var worstVelocity: Float = 0, worstInk: Float = 0, peakInk: Float = 0
        for j in 0..<32 {
            for i in 0..<32 {
                let k = j * 32 + i
                let v = solver.velocity(i, j), c = solver.inkColor(i, j)
                worstVelocity = max(worstVelocity, abs(gpu.velocity[k].x - v.x), abs(gpu.velocity[k].y - v.y))
                worstInk = max(worstInk, abs(gpu.ink[k].x - c.x), abs(gpu.ink[k].y - c.y), abs(gpu.ink[k].z - c.z))
                peakInk = max(peakInk, c.max())
            }
        }
        XCTAssertGreaterThan(peakInk, 0.2)
        XCTAssertLessThan(worstVelocity, 0.01, "velocity GPU vs CPU")
        XCTAssertLessThan(worstInk, 0.01, "ink GPU vs CPU")
        print("VIS-011 GPU vs CPU reference at 32²: velocity \(worstVelocity), ink \(worstInk)")
    }

    /// VIS-011-S2: 30 and 120 fps frame clocks, impulses at shared times → identical fields after 1 s.
    func testThirtyAndOneHundredTwentyFramesPerSecondMatchOnTheGPU() throws {
        let rig = try RenderRig()
        let slow = try runPass(rig, gridSize: 32, fps: 30, frames: 30, impulse: { (m: UInt64) -> Bool in m % 3 == 0 })
        let fast = try runPass(rig, gridSize: 32, fps: 120, frames: 120, impulse: { (q: UInt64) -> Bool in q % 12 == 0 })
        XCTAssertEqual(slow.velocity, fast.velocity)
        XCTAssertEqual(slow.ink, fast.ink)
        XCTAssertGreaterThan(slow.ink.map { (c: SIMD4<Float>) -> Float in c.max() }.max() ?? 0, 0.1)
    }

    /// VIS-011-S3, R8: storage constant over resizes, mode switches, restarts and size 0; a field generator never makes it.
    func testAllocationStaysConstant() throws {
        let rig = try RenderRig()
        let plain = try rig.build { try NoiseFieldGenerator(device: rig.device, pixelFormat: Self.format) }
        let generator = try rig.build {
            try NoiseFieldGenerator(device: rig.device, pixelFormat: Self.format, configuration: .fluidInk())
        }
        let targets = [try rig.makeTexture(width: 48, height: 32, format: Self.format),
                       try rig.makeTexture(width: 32, height: 64, format: Self.format)]
        let pass = try XCTUnwrap(generator.fluidPass)
        let identities = pass.textures.map { (t: MTLTexture) -> ObjectIdentifier in ObjectIdentifier(t) }
        let sizes = pass.textures.map { (t: MTLTexture) -> String in "\(t.width)x\(t.height) \(t.pixelFormat.rawValue)" }
        let bytes = pass.allocatedBytes
        var commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
        for m: UInt64 in 0..<300 {
            let context = Self.context(frame: m, fps: 60)
            if m % 4 == 0 { generator.enqueueImpulse(atNanoseconds: context.timeNanoseconds, strength: 0.9, threshold: 0.3) }
            if m == 100 { generator.configuration = .fluidInk(palette: .ice) }
            if m == 125 { generator.configuration = NoiseFieldConfiguration() }
            if m == 150 { generator.configuration = .fluidInk() }
            if m == 200 { generator.restartLoop() }
            _ = encode(generator, into: targets[Int(m / 25) % 2], commands, context)
            _ = encode(plain, into: targets[0], commands, context)
            XCTAssertTrue(generator.fluidPass === pass)
            XCTAssertEqual(pass.textures.map { (t: MTLTexture) -> ObjectIdentifier in ObjectIdentifier(t) }, identities)
            if m % 50 == 49 {
                commands.commit()
                commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
            }
        }
        commands.commit()
        commands.waitUntilCompleted()
        XCTAssertEqual(pass.textures.count, 8)
        XCTAssertEqual(pass.textures.map { (t: MTLTexture) -> String in "\(t.width)x\(t.height) \(t.pixelFormat.rawValue)" }, sizes)
        XCTAssertEqual(pass.allocatedBytes, bytes)
        XCTAssertEqual(pass.gridSize, FluidInk.gridSize)
        XCTAssertEqual(pass.resets, 2, "re-entry and restart start at rest")
        XCTAssertNil(plain.fluidPass, "a generator that never shows fluid ink allocates nothing for it")
        if bytes == 0 { print("VIS-011: allocatedSize reads 0 here (simulator); sizes and identities asserted") }
    }

    /// Re-entry and restart start at rest: the picture is black on the first frame after them.
    func testRestartStartsAtRest() throws {
        let rig = try RenderRig()
        let generator = try rig.build {
            try NoiseFieldGenerator(device: rig.device, pixelFormat: Self.format, configuration: .fluidInk())
        }
        let target = try rig.makeTexture(width: 16, height: 16, format: Self.format)
        let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
        for m: UInt64 in 0...30 {
            let context = Self.context(frame: m, fps: 60)
            generator.enqueueImpulse(atNanoseconds: context.timeNanoseconds, strength: 1, threshold: 0)
            _ = encode(generator, into: target, commands, context)
        }
        let lit = try rig.encodeReadBack(target, commands: commands)
        generator.restartLoop()
        _ = encode(generator, into: target, commands, Self.context(frame: 31, fps: 60))
        _ = encode(generator, into: target, commands, Self.context(frame: 32, fps: 60))
        let dark = try rig.encodeReadBack(target, commands: commands)
        commands.commit()
        commands.waitUntilCompleted()
        let litImage = rig.decode(RenderRig.bytes(of: lit), width: 16, height: 16, format: Self.format)
        let darkImage = rig.decode(RenderRig.bytes(of: dark), width: 16, height: 16, format: Self.format)
        XCTAssertGreaterThan(litImage.pixels.map { (p: Pixel) -> Double in luminance(p) }.max() ?? 0, 0.05)
        XCTAssertEqual(darkImage.pixels.map { (p: Pixel) -> Double in luminance(p) }.max() ?? 1, 0)
        XCTAssertTrue(litImage.pixels.allSatisfy { (p: Pixel) -> Bool in p.x <= 0.8 && p.y <= 0.8 && p.z <= 0.8 && p.w == 1 })
    }
}
#endif
