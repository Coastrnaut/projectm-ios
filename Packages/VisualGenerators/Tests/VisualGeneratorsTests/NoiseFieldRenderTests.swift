// NoiseFieldRenderTests.swift — VIS-013-T09 (VIS-013-R1, R3, R7; S1, S4; research VIS-013-D5): the roadmap acceptance
// "Same seed and settings produce matching frames on same GPU class". The real Metal pipeline renders 64 × 64 frames
// after a fixed 30-frame fixture band timeline on an injected 60 Hz clock: two fresh generators give byte-identical
// frames, which match the FNV-1a 64 digest recorded for this GPU class (`MTLDevice.name`, as SHD-006's
// MaterialNoiseTests; an unrecorded class prints its digest and skips only that comparison); a different seed differs;
// the GPU agrees with the CPU mirror; more octaves add fine detail. Without a Metal device the tests skip (RenderRig).
#if canImport(Metal) && !VISUAL_NO_METAL
import Metal
import XCTest
@testable import VisualGenerators

final class NoiseFieldRenderTests: XCTestCase {
    private static let side = 64
    private static let frames = 30

    /// FNV-1a 64 of the BGRA8 sRGB frame for `NoiseFieldConfiguration(seed: 1301)` and seed 4242 (in that order), per GPU
    /// class. Recorded 2026-11-14 on the build Mac's host GPU and on the iOS 27.2 simulator of the same Mac.
    private static let digests: [String: [UInt64]] = [
        "Apple M5 Max": [0x5ACA_F96E_ABA2_29D6, 0x2753_B914_F0B6_6DF5],
        // The simulator draws on the same Mac GPU and gives the same bytes.
        "Apple iOS simulator GPU": [0x5ACA_F96E_ABA2_29D6, 0x2753_B914_F0B6_6DF5],
    ]

    /// The fixture's 64 bands at frame f: a moving bass-heavy slope, 0…1.
    private static func bands(frame f: Int) -> [Float] {
        (0..<64).map { (k: Int) -> Float in
            let slope: Float = 1 - Float(k) / 64
            let pulse: Float = (f / 5) % 2 == 0 ? 1 : 0.3
            return min(max(slope * pulse, 0), 1)
        }
    }

    private func render(_ rig: RenderRig, _ configuration: NoiseFieldConfiguration,
                        format: MTLPixelFormat = .bgra8Unorm_srgb) throws -> (bytes: [UInt8], generator: NoiseFieldGenerator) {
        let generator = try rig.build { try NoiseFieldGenerator(device: rig.device, pixelFormat: format, configuration: configuration) }
        let texture = try rig.makeTexture(width: Self.side, height: Self.side, format: format)
        let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
        for f in 0..<Self.frames {
            let context = VisualFrameContext(timeNanoseconds: UInt64(f) * 1_000_000_000 / 60, frameDuration: 1.0 / 60, reduceFlashing: false)
            let drawn: Bool = Self.bands(frame: f).withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> Bool in
                generator.encode(into: texture, commandBuffer: commands, bands: b, context: context)
            }
            XCTAssertTrue(drawn)
        }
        let buffer = try rig.encodeReadBack(texture, commands: commands)
        commands.commit()
        commands.waitUntilCompleted()
        XCTAssertEqual(commands.status, .completed, "\(String(describing: commands.error))")
        return (RenderRig.bytes(of: buffer), generator)
    }

    static func fnv1a(_ bytes: [UInt8]) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for b in bytes {
            hash ^= UInt64(b)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }

    func testSameSeedAndSettingsGiveMatchingFramesAndADifferentSeedDiffers() throws {
        let rig = try RenderRig()
        let seeds: [Int] = [1301, 4242]
        var digests: [UInt64] = []
        var frames: [[UInt8]] = []
        for seed in seeds {
            let configuration = NoiseFieldConfiguration(seed: seed)
            let first = try render(rig, configuration).bytes
            let second = try render(rig, configuration).bytes
            XCTAssertEqual(first, second, "seed \(seed): two renders are byte-identical")
            digests.append(Self.fnv1a(first))
            frames.append(first)
        }
        let pixels: Int = Self.side * Self.side
        var differing = 0
        for p in 0..<pixels where frames[0][p * 4..<p * 4 + 3] != frames[1][p * 4..<p * 4 + 3] { differing += 1 }
        XCTAssertGreaterThan(differing, pixels / 10, "a different seed changes more than 10 % of pixels")
        let hex: String = digests.map { (d: UInt64) -> String in "0x" + String(d, radix: 16, uppercase: true) }.joined(separator: ", ")
        let name: String = rig.device.name
        guard let recorded = Self.digests[name] else {
            print("VIS-013 noise field digests for unrecorded GPU class \"\(name)\": [\(hex)] (comparison skipped)")
            return
        }
        XCTAssertEqual(digests, recorded, "GPU class \(name): [\(hex)]")
    }

    func testTheGPUFieldAgreesWithTheCPUMirror() throws {
        let rig = try RenderRig()
        let configuration = NoiseFieldConfiguration(frequency: 4, octaves: 4, seed: 77, palette: .ice)
        let result = try render(rig, configuration, format: .rgba16Float)
        let g = result.generator
        let stops: [LinearColor] = (0..<16).map { (k: Int) -> LinearColor in configuration.palette.color(bar: k, of: 16).clamped }
        let lit: Float = Float(g.drive.brightness) * g.lastGain
        var worst: Float = 0
        for (x, y) in [(3, 5), (20, 40), (32, 32), (50, 10), (60, 60), (8, 57)] {
            let q: SIMD2<Float> = SeededNoise.domainPoint(x: Float(x) + 0.5, y: Float(y) + 0.5, width: Self.side, height: Self.side,
                                                          scale: 4, phase: Float(g.drive.phase))
            let n: Float = SeededNoise.warped(q, octaves: 4, lacunarity: NoiseFieldConfiguration.lacunarity, gain: NoiseFieldConfiguration.gain,
                                              seed: 77, warpAmount: Float(g.drive.warp), warpFrequency: 1)
            let base: LinearColor = stops.withUnsafeBufferPointer { (p: UnsafeBufferPointer<LinearColor>) -> LinearColor in
                NoiseFieldFlashAreas.paletteColor(n, stops: p.baseAddress!)
            }
            let i: Int = (y * Self.side + x) * 8
            let half: (Int) -> Float = { (o: Int) -> Float in
                Half.toFloat(UInt16(result.bytes[i + o]) | UInt16(result.bytes[i + o + 1]) << 8)
            }
            let s: Float = (0.25 + 0.75 * n) * lit
            worst = max(worst, abs(half(0) - base.red * s), abs(half(2) - base.green * s), abs(half(4) - base.blue * s))
        }
        XCTAssertLessThan(worst, 0.02, "GPU vs CPU mirror")
    }

    func testMoreOctavesAndHigherFrequencyAddDetail() throws {
        let rig = try RenderRig()
        func energy(_ c: NoiseFieldConfiguration) throws -> Double {
            let bytes: [UInt8] = try render(rig, c).bytes
            var sum = 0.0
            for y in 1..<(Self.side - 1) {
                for x in 1..<(Self.side - 1) {
                    let v: (Int, Int) -> Double = { (px: Int, py: Int) -> Double in Double(bytes[(py * Self.side + px) * 4 + 1]) }
                    sum += abs(4 * v(x, y) - v(x - 1, y) - v(x + 1, y) - v(x, y - 1) - v(x, y + 1))
                }
            }
            return sum
        }
        let base: Double = try energy(NoiseFieldConfiguration(frequency: 2, octaves: 1, palette: .mono))
        XCTAssertGreaterThan(try energy(NoiseFieldConfiguration(frequency: 2, octaves: 6, palette: .mono)), base, "octaves")
        XCTAssertGreaterThan(try energy(NoiseFieldConfiguration(frequency: 8, octaves: 1, palette: .mono)), base, "frequency")
    }
}
#endif
