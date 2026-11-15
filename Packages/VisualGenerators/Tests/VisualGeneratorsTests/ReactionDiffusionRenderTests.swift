// ReactionDiffusionRenderTests.swift — VIS-012-T06 (VIS-012-R1, R3 to R7, R9, R14; S1, S2, S4; contract C2): reaction
// diffusion on the real Metal pipeline with an injected clock. The roadmap acceptance: a reload (generator recreated
// from settings decoded from their stored raw values; a seed change and back; a loop restart) gives a bit-identical
// initial state on the GPU, equal to the CPU seed, and another seed differs; every preset at Speed 16 for 3 000
// iterations at 128² with repeated strong bass leaves every texel finite and within [0, 1] (full readback) with a clean
// health image. The GPU follows the CPU reference; a corrupt texel is detected and re-seeded; textures keep their
// count, identities and allocated size. Without Metal they skip.
#if canImport(Metal) && !VISUAL_NO_METAL
import Metal
import VisualFluidReference
import XCTest
@testable import VisualGenerators

final class ReactionDiffusionRenderTests: XCTestCase {
    private static let format: MTLPixelFormat = .rgba16Float
    private static let start: UInt64 = 1_000_000_000

    private static func context(frame m: UInt64, fps: UInt64) -> VisualFrameContext {
        VisualFrameContext(timeNanoseconds: start + m * 1_000_000_000 / fps, frameDuration: 1.0 / Double(fps), reduceFlashing: false)
    }

    private func encode(_ generator: NoiseFieldGenerator, into target: MTLTexture, _ commands: MTLCommandBuffer,
                        _ context: VisualFrameContext, bass: Float = 0) -> Bool {
        let bands = [Float](repeating: bass, count: 64)
        return bands.withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> Bool in
            generator.encode(into: target, commandBuffer: commands, bands: b, context: context)
        }
    }

    /// Commits `commands` after a state copy and returns the state, rows top first.
    private func state(_ generator: NoiseFieldGenerator, _ commands: MTLCommandBuffer) throws -> [SIMD2<Float>] {
        let pass = try XCTUnwrap(generator.reactionPass)
        let buffer = try XCTUnwrap(pass.copyState(commandBuffer: commands))
        commands.commit()
        commands.waitUntilCompleted()
        XCTAssertEqual(commands.status, .completed)
        let n = pass.gridSize * pass.gridSize
        return Array(UnsafeBufferPointer(start: buffer.contents().bindMemory(to: SIMD2<Float>.self, capacity: n), count: n))
    }

    private func cpuSeed(_ settings: ReactionDiffusionSettings) -> [SIMD2<Float>] {
        let n = ReactionDiffusion.gridSize
        var cells = [SIMD2<Float>](repeating: .zero, count: n * n)
        cells.withUnsafeMutableBufferPointer { (b: inout UnsafeMutableBufferPointer<SIMD2<Float>>) -> Void in
            ReactionDiffusionSeed.fill(pattern: settings.pattern, seed: settings.seed, gridSize: n, into: b.baseAddress!)
        }
        return cells
    }

    /// The roadmap acceptance, first half (VIS-012-S1): reloads reproduce the initial pattern bit for bit.
    func testReloadReproducesTheInitialPatternBitForBit() throws {
        let rig = try RenderRig()
        let target = try rig.makeTexture(width: 16, height: 16, format: Self.format)
        let stored = ReactionDiffusionSettings(storedPreset: "mitosis", pattern: "spots", seed: 4242, speed: 12)
        var initial: [[SIMD2<Float>]] = []
        for _ in 0..<2 {   // two launches: the generator recreated from the decoded settings
            let decoded = ReactionDiffusionSettings(storedPreset: stored.preset.rawValue, pattern: stored.pattern.rawValue,
                                                    seed: stored.seed, speed: stored.speed)
            let generator = try rig.build {
                try NoiseFieldGenerator(device: rig.device, pixelFormat: Self.format, configuration: .reactionDiffusion(decoded))
            }
            let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
            XCTAssertTrue(encode(generator, into: target, commands, Self.context(frame: 0, fps: 60)))
            initial.append(try state(generator, commands))
        }
        XCTAssertEqual(initial[0], initial[1], "two launches")
        XCTAssertEqual(initial[0], cpuSeed(stored), "the GPU starts from the CPU seed exactly")

        let generator = try rig.build {
            try NoiseFieldGenerator(device: rig.device, pixelFormat: Self.format, configuration: .reactionDiffusion(stored))
        }
        var commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
        for m: UInt64 in 0..<30 { _ = encode(generator, into: target, commands, Self.context(frame: m, fps: 60), bass: m % 6 == 0 ? 1 : 0) }
        let grown = try state(generator, commands)
        XCTAssertNotEqual(grown, initial[0], "it evolved")
        var other = stored
        other.seed = 4243
        generator.configuration = .reactionDiffusion(other)
        commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
        _ = encode(generator, into: target, commands, Self.context(frame: 30, fps: 60))
        let otherSeed = try state(generator, commands)
        XCTAssertEqual(otherSeed, cpuSeed(other))
        XCTAssertNotEqual(otherSeed, initial[0], "another seed gives other spots")
        generator.configuration = .reactionDiffusion(stored)   // the preset re-chosen
        commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
        for m: UInt64 in 31..<40 { _ = encode(generator, into: target, commands, Self.context(frame: m, fps: 60)) }
        commands.commit()
        commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
        generator.restartLoop()   // a loop restart reloads too
        _ = encode(generator, into: target, commands, Self.context(frame: 40, fps: 60))
        XCTAssertEqual(try state(generator, commands), initial[0], "restart")
        var faster = stored
        faster.speed = 16
        generator.configuration = .reactionDiffusion(faster)
        commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
        _ = encode(generator, into: target, commands, Self.context(frame: 41, fps: 60))
        XCTAssertNotEqual(try state(generator, commands), initial[0], "a Speed change does not re-seed")
        XCTAssertEqual(generator.reactionPass?.reloads, 4, "first frame, seed change, preset re-chosen, restart")
    }

    /// The roadmap acceptance, second half (VIS-012-S2): never a NaN texture, every preset at maximum speed.
    func testEveryPresetAtMaximumSpeedNeverWritesNaN() throws {
        let rig = try RenderRig()
        let target = try rig.makeTexture(width: 16, height: 16, format: Self.format)
        var report: [String] = []
        for preset in ReactionDiffusionPreset.allCases {
            let settings = ReactionDiffusionSettings(preset: preset, pattern: .spots, seed: 9, speed: 16)
            let generator = try rig.build {
                try NoiseFieldGenerator(device: rig.device, pixelFormat: Self.format, configuration: .reactionDiffusion(settings))
            }
            let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
            var m: UInt64 = 0
            while generator.reactionScheduler.totalIterations < 3_000 {   // 15 fps: 4 steps × 16 = 64 iterations a frame
                XCTAssertTrue(encode(generator, into: target, commands, Self.context(frame: m, fps: 15), bass: m % 2 == 0 ? 1 : 0))
                XCTAssertLessThanOrEqual(generator.reactionScheduler.plannedIterations, 64)
                m += 1
            }
            let cells = try state(generator, commands)
            let pass = try XCTUnwrap(generator.reactionPass)
            pass.pollHealth()
            let health = try XCTUnwrap(pass.lastHealth)
            XCTAssertTrue(health.isHealthy, "\(preset): \(health)")
            XCTAssertTrue(cells.allSatisfy { (c: SIMD2<Float>) -> Bool in
                c.x.isFinite && c.y.isFinite && c.x >= 0 && c.x <= 1 && c.y >= 0 && c.y <= 1
            }, "\(preset)")
            XCTAssertGreaterThan(health.maxV, 0.1, "\(preset) is alive")
            XCTAssertGreaterThan(generator.reactionScheduler.appliedInjections, 5, "\(preset) took strong injections")
            XCTAssertEqual(generator.reactionHealthReloads, 0)
            report.append("\(preset.rawValue): \(generator.reactionScheduler.totalIterations) iterations, "
                          + "\(generator.reactionScheduler.appliedInjections) injections, max V \(health.maxV), min \(health.minValue)")
        }
        print("VIS-012 GPU at Speed 16, 128²: " + report.joined(separator: "; "))
    }

    /// The GPU runs the reference's formula: 60 iterations at 32² with an injection.
    func testGPUFollowsTheReferenceSolver() throws {
        let rig = try RenderRig()
        let probe = try rig.build {
            try NoiseFieldGenerator(device: rig.device, pixelFormat: Self.format, configuration: .reactionDiffusion())
        }
        let pass = try ReactionDiffusionPass(device: rig.device, library: probe.library, targetFormat: Self.format, gridSize: 32)
        let solver = GrayScottSolver(gridSize: 32, parameters: ReactionDiffusionPreset.coral.parameters)
        solver.seed(pattern: .square, seed: 2)
        pass.requestSeed(pattern: .square, seed: 2)
        let scheduler = ReactionDiffusionScheduler()
        scheduler.speed = 10
        scheduler.seed = 2
        let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
        for m: UInt64 in 0...6 {
            let t = Self.start + m * 1_000_000_000 / 60
            if m == 1 { scheduler.enqueue(atNanoseconds: t - 1, strength: 1) }
            scheduler.advance(toNanoseconds: t)
            XCTAssertTrue(pass.encode(scheduler: scheduler, parameters: solver.parameters, commandBuffer: commands, target: nil, scale: 1))
            for s in 0..<scheduler.plannedSteps {
                for k in 0..<scheduler.iterations(step: s) { solver.iterate(injection: k == 0 ? scheduler.injection(step: s) : nil) }
            }
        }
        XCTAssertEqual(scheduler.appliedInjections, 1)
        let buffer = try XCTUnwrap(pass.copyState(commandBuffer: commands))
        commands.commit()
        commands.waitUntilCompleted()
        let gpu = UnsafeBufferPointer(start: buffer.contents().bindMemory(to: SIMD2<Float>.self, capacity: 1024), count: 1024)
        let cpu = solver.cells
        var worst: Float = 0
        for k in 0..<1024 { worst = max(worst, abs(gpu[k].x - cpu[k].x), abs(gpu[k].y - cpu[k].y)) }
        XCTAssertEqual(solver.iterations, 60)
        XCTAssertLessThan(worst, 1e-3, "GPU vs CPU after 60 iterations")
        print("VIS-012 GPU vs CPU reference at 32², 60 iterations: \(worst)")
    }

    /// VIS-012-R9: a non-finite texel is flagged by the health image and the grid re-seeds on the next frame.
    func testHealthCheckReseedsACorruptGrid() throws {
        let rig = try RenderRig()
        let target = try rig.makeTexture(width: 16, height: 16, format: Self.format)
        let settings = ReactionDiffusionSettings(pattern: .ring, seed: 5)
        let generator = try rig.build {
            try NoiseFieldGenerator(device: rig.device, pixelFormat: Self.format, configuration: .reactionDiffusion(settings))
        }
        var commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
        for m: UInt64 in 0...10 { _ = encode(generator, into: target, commands, Self.context(frame: m, fps: 60)) }
        commands.commit()
        commands.waitUntilCompleted()
        commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
        let pass = try XCTUnwrap(generator.reactionPass)
        pass.corrupt(cellX: 5, y: 7, value: SIMD2<Float>(.nan, 0.3), commandBuffer: commands)
        _ = encode(generator, into: target, commands, Self.context(frame: 10, fps: 60))   // no step: the health pass sees it
        commands.commit()
        commands.waitUntilCompleted()
        commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
        _ = encode(generator, into: target, commands, Self.context(frame: 11, fps: 60))
        XCTAssertEqual(generator.reactionHealthReloads, 1)
        XCTAssertEqual(pass.lastHealth?.flagged, true)
        XCTAssertEqual(try state(generator, commands), cpuSeed(settings), "re-seeded")
    }

    /// VIS-012-S4, R14: storage constant over resizes, mode switches, reloads and size 0; others never make it.
    func testAllocationStaysConstant() throws {
        let rig = try RenderRig()
        let plain = try rig.build { try NoiseFieldGenerator(device: rig.device, pixelFormat: Self.format) }
        let generator = try rig.build {
            try NoiseFieldGenerator(device: rig.device, pixelFormat: Self.format, configuration: .reactionDiffusion())
        }
        let targets = [try rig.makeTexture(width: 48, height: 32, format: Self.format),
                       try rig.makeTexture(width: 32, height: 64, format: Self.format)]
        let pass = try XCTUnwrap(generator.reactionPass)
        let identities = pass.textures.map { (t: MTLTexture) -> ObjectIdentifier in ObjectIdentifier(t) }
        let sizes = pass.textures.map { (t: MTLTexture) -> String in "\(t.width)x\(t.height) \(t.pixelFormat.rawValue)" }
        let bytes = pass.allocatedBytes
        var commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
        for m: UInt64 in 0..<200 {
            if m == 50 { generator.configuration = .reactionDiffusion(ReactionDiffusionSettings(preset: .maze, seed: 3), palette: .ice) }
            if m == 75 { generator.configuration = .fluidInk() }
            if m == 100 { generator.configuration = .reactionDiffusion() }
            if m == 150 { generator.restartLoop() }
            _ = encode(generator, into: targets[Int(m / 25) % 2], commands, Self.context(frame: m, fps: 60), bass: m % 10 == 0 ? 1 : 0)
            _ = encode(plain, into: targets[0], commands, Self.context(frame: m, fps: 60))
            XCTAssertTrue(generator.reactionPass === pass)
            if m % 50 == 49 {
                commands.commit()
                commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
            }
        }
        commands.commit()
        commands.waitUntilCompleted()
        XCTAssertEqual(pass.textures.count, 3)
        XCTAssertEqual(pass.textures.map { (t: MTLTexture) -> ObjectIdentifier in ObjectIdentifier(t) }, identities)
        XCTAssertEqual(pass.textures.map { (t: MTLTexture) -> String in "\(t.width)x\(t.height) \(t.pixelFormat.rawValue)" }, sizes)
        XCTAssertEqual(pass.allocatedBytes, bytes)
        XCTAssertEqual(pass.gridSize, ReactionDiffusion.gridSize)
        XCTAssertEqual(pass.reloads, 4, "first frame, preset change, re-entry, restart")
        XCTAssertNil(plain.reactionPass, "a generator that never shows reaction diffusion allocates nothing for it")
    }
}
#endif
