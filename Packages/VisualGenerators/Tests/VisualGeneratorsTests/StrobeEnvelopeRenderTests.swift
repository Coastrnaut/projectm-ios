// StrobeEnvelopeRenderTests.swift — FX-019-T14 (GPU): generator → bloom → read back at 64 × 64;
// every frame's 17 area levels are measured from the composited pixels and analyzed with FlashSafety's
// `FlashAnalysis` (FX-019-R4, R9, S1). Two representative cases (owner rule 7). Skips where no Metal
// device exists.
#if canImport(Metal) && !VISUAL_NO_METAL
import FlashSafety
import Metal
import XCTest
@testable import VisualEffects
@testable import VisualGenerators

final class StrobeEnvelopeRenderTests: XCTestCase {
    /// Area levels of a linear, top-row-first image.
    private func levels(_ image: PixelImage) -> [FlashLevels] {
        var out = [FlashLevels](repeating: .zero, count: FlashZones.count)
        var counts = [Int](repeating: 0, count: FlashZones.tileCount)
        for y in 0..<image.height {
            for x in 0..<image.width {
                let p = image[x, y]
                let z = (y * 4 / image.height) * 4 + x * 4 / image.width
                let l = luminance(p), r = Double(max(p.x - p.y - p.z, 0))
                out[z].luminance += l; out[z].redness += r; counts[z] += 1
                out[FlashZones.wholeFrame].luminance += l; out[FlashZones.wholeFrame].redness += r
            }
        }
        for z in 0..<FlashZones.tileCount { out[z].luminance /= Double(counts[z]); out[z].redness /= Double(counts[z]) }
        let n = Double(image.width * image.height)
        out[FlashZones.wholeFrame].luminance /= n
        out[FlashZones.wholeFrame].redness /= n
        return out
    }

    func testMeasuredStrobesObeyTheEnvelope() throws {
        let rig = try RenderRig()
        let format: MTLPixelFormat = .rgba16Float
        let size = 64
        let parameters = BloomParameters(enabled: true, intensity: 1, radius: 0.06, threshold: 0.1, knee: 1)
        struct Case { let palette: VisualPalette; let halfPeriod: Int; let enabled: Bool; let name: String }
        let cases = [Case(palette: .mono, halfPeriod: 1, enabled: false, name: "mono bars 60 Hz, glow, Reduce flashing off"),
                     Case(palette: .spectrum, halfPeriod: 6, enabled: true, name: "spectrum bars 10 Hz, glow, Reduce flashing on")]
        var report = ["FX-019 native visual (GPU \(rig.device.name), \(size) × \(size), measured pixels): worst transitions per window of the output:"]
        for c in cases {
            let configuration = CircularSpectrumConfiguration(barCount: .b64, innerRadius: 0.3, lengthScale: 0.4, palette: c.palette)
            let generator = try rig.build { try CircularSpectrumGenerator(device: rig.device, pixelFormat: format, configuration: configuration) }
            let bloom = try rig.build { try BloomEffect(device: rig.device, pixelFormat: format, parameters: parameters) }
            generator.downstreamLuminance = BloomLuminanceModel(parameters: parameters)
            let chain = try EffectChain(device: rig.device, pixelFormat: format, effects: [bloom])
            try chain.prepare(width: size, height: size)
            let output = try rig.makeTexture(width: size, height: size, format: format)
            let full = [Float](repeating: 1, count: 64), empty = [Float](repeating: 0, count: 64)
            let dt = 1.0 / 60
            var shown: [[FlashLevels]] = []
            for f in 0..<120 {
                let bands = (f / c.halfPeriod) % 2 == 0 ? full : empty
                let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
                let context = VisualFrameContext(timeNanoseconds: UInt64(f) * 16_666_667, frameDuration: dt, reduceFlashing: c.enabled)
                let drawn = bands.withUnsafeBufferPointer { b in
                    chain.encode(output: output, commandBuffer: commands) { target in
                        generator.encode(into: target, commandBuffer: commands, bands: b, context: context)
                    }
                }
                XCTAssertTrue(drawn, "frame \(f)")
                let buffer = try rig.encodeReadBack(output, commands: commands)
                commands.commit()
                commands.waitUntilCompleted()
                shown.append(levels(rig.decode(RenderRig.bytes(of: buffer), width: size, height: size, format: format)))
            }
            let envelope = FlashEnvelopeConfiguration.forReduceFlashing(c.enabled)
            let times = [Double](repeating: dt, count: shown.count)
            var worst = 0
            var worstTileExcess = 0.0
            for z in 0..<FlashZones.count {
                for s in FlashSignal.allCases {
                    let r = FlashAnalysis.analyze(shown.map { $0[z][s] }, frameTimes: times, threshold: envelope.threshold(for: s))
                    worst = max(worst, r.maxTransitionsPerWindow)
                    if let rate = envelope.riseRatePerSecond {
                        // The whole frame is modeled exactly (FX-001-D4): its measured rise stays within
                        // the bound + 0.002 (rasterization, half floats). Tile levels are estimates
                        // (bars rasterized at this small size, the halo's placement), so a tile's
                        // measured rise may exceed the modeled one; reported, bounded loosely.
                        let excess = r.maxRise - rate * dt
                        if z == FlashZones.wholeFrame {
                            XCTAssertLessThanOrEqual(excess, 0.002, "\(c.name) whole frame \(s): rise")
                        } else {
                            worstTileExcess = max(worstTileExcess, excess)
                            XCTAssertLessThanOrEqual(excess, 0.03, "\(c.name) area \(z) \(s): rise estimate")
                        }
                    }
                }
            }
            XCTAssertLessThanOrEqual(worst, envelope.transitionBudget, c.name)
            XCTAssertGreaterThan(shown.map { $0[FlashZones.wholeFrame].luminance }.max() ?? 0, 0.005, "\(c.name): frames were not blank")
            report.append("\(c.name): \(worst) (limit \(envelope.transitionBudget); the unlimited input has \(c.halfPeriod == 1 ? 60 : 10) changes per second); worst tile rise above the modeled bound \(String(format: "%.4f", worstTileExcess))")
        }
        print(report.joined(separator: "\n"))
    }
}
#endif
