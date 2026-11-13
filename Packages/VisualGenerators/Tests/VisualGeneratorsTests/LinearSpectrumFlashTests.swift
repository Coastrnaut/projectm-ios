// LinearSpectrumFlashTests.swift — VIS-002-T09: the linear spectrum feeds FX-019's strobe safety
// envelope exactly like the circular spectrum (VIS-002-R9, S5; FX-019-R4, R9). CPU: the 17 area
// levels against a direct rectangle-tile integration, and a 60 Hz strobe through the limiter as the
// generator applies it, measured with FlashSafety's independent `FlashAnalysis`. GPU (skips without
// Metal): one strobe through the glow, measured from the composited pixels. Constant frame times;
// no clock. Representative cases only (owner rule 7).
import FlashSafety
import XCTest
@testable import VisualEffects
@testable import VisualGenerators

final class LinearSpectrumFlashTests: XCTestCase {
    private func levels<T: FrameLuminanceTransfer>(_ layout: LinearSpectrumLayout, gain: Float, _ transfer: T) -> [FlashLevels] {
        var out = [FlashLevels](repeating: .zero, count: FlashZones.count)
        out.withUnsafeMutableBufferPointer { layout.meanLevels(gain: gain, transfer: transfer, into: $0) }
        return out
    }

    func testAreaLevelsMatchADirectIntegration() {
        let width = 100, height = 80   // tiles 25 × 20: bars straddle tile edges
        for orientation in LinearSpectrumOrientation.allCases {
            let layout = LinearSpectrumLayout(configuration: LinearSpectrumConfiguration(barCount: .b16, orientation: orientation))
            layout.layout((0..<16).map { Float($0 % 5) / 4 }, frameTime: 0, width: width, height: height)
            let gain: Float = 0.7
            let got = levels(layout, gain: gain, IdentityLuminanceTransfer())
            var expected = [Double](repeating: 0, count: FlashZones.count)
            var redness = [Double](repeating: 0, count: FlashZones.count)
            let tw = Double(width) / 4, th = Double(height) / 4
            for k in 0..<16 {
                let r = layout.rectangles(ofBar: k)
                let c = layout.bar(k).color
                let y = Double(c.relativeLuminance * gain), red = Double(max(c.red - c.green - c.blue, 0) * gain)
                for rect in [r.bar, r.cap].compactMap({ $0 }) {
                    for z in 0..<FlashZones.tileCount {
                        let x0 = Double(z % 4) * tw, y0 = Double(z / 4) * th
                        let ox = max(0, min(rect.maxX, x0 + tw) - max(rect.minX, x0))
                        let oy = max(0, min(rect.maxY, y0 + th) - max(rect.minY, y0))
                        expected[z] += ox * oy * y / (tw * th)
                        redness[z] += ox * oy * red / (tw * th)
                    }
                    expected[FlashZones.wholeFrame] += rect.area * y / Double(width * height)
                    redness[FlashZones.wholeFrame] += rect.area * red / Double(width * height)
                }
            }
            for z in 0..<FlashZones.count {
                // Colors and gain are Float in both paths, combined in a different order: 1e-6.
                XCTAssertEqual(got[z].luminance, expected[z], accuracy: 1e-6, "\(orientation) area \(z) luminance")
                XCTAssertEqual(got[z].redness, redness[z], accuracy: 1e-6, "\(orientation) area \(z) redness")
            }
        }
    }

    /// Bands 0/1 every frame for 2 s at 60 fps through the limiter, as `LinearSpectrumGenerator`
    /// applies it; mono bars with Reduce flashing on and off.
    func testSixtyHertzStrobeObeysTheEnvelope() {
        var report = ["VIS-002 linear spectrum (CPU, 390 × 844, bands 0/1 every frame): worst transitions per window:"]
        for enabled in [true, false] {
            let configuration = FlashEnvelopeConfiguration.forReduceFlashing(enabled)
            let limiter = FlashSafetyLimiter()
            let layout = LinearSpectrumLayout(configuration: LinearSpectrumConfiguration(barCount: .b64, palette: .mono))
            let full = [Float](repeating: 1, count: 64), empty = [Float](repeating: 0, count: 64)
            var shown: [[FlashLevels]] = []
            let dt = 1.0 / 60
            for f in 0..<120 {
                let target = f % 2 == 0 ? full : empty
                let values = target.withUnsafeBufferPointer { Array(limiter.limitValues($0, frameTime: dt, enabled: enabled)) }
                layout.layout(values, frameTime: dt, width: 390, height: 844)
                let gain = limiter.gain(for: layout, transfer: IdentityLuminanceTransfer(), frameTime: dt, enabled: enabled)
                shown.append(levels(layout, gain: gain, IdentityLuminanceTransfer()))
            }
            let times = [Double](repeating: dt, count: shown.count)
            var worst = 0
            for z in 0..<FlashZones.count {
                for s in FlashSignal.allCases {
                    let out = FlashAnalysis.analyze(shown.map { $0[z][s] }, frameTimes: times, threshold: configuration.threshold(for: s))
                    worst = max(worst, out.maxTransitionsPerWindow)
                    if let rate = configuration.riseRatePerSecond {
                        XCTAssertLessThanOrEqual(out.maxRise, rate * dt + 1e-9, "area \(z) \(s)")
                    }
                }
            }
            XCTAssertLessThanOrEqual(worst, configuration.transitionBudget, "Reduce flashing \(enabled)")
            XCTAssertGreaterThan(shown.map { $0[FlashZones.wholeFrame].luminance }.max() ?? 0, 0.01, "frames were not blank")
            report.append("Reduce flashing \(enabled ? "on" : "off"): \(worst) (limit \(configuration.transitionBudget))")
        }
        print(report.joined(separator: "\n"))
    }

    #if canImport(Metal) && !VISUAL_NO_METAL
    /// Measured from pixels: spectrum bars at 60 Hz through the strongest glow, Reduce flashing on.
    func testMeasuredStrobeThroughTheGlowObeysTheEnvelope() throws {
        let rig = try RenderRig()
        let format: MTLPixelFormat = .rgba16Float
        // 128 × 128: at 64 × 64 a 32-bar layout has 1.6 px bars and a 3.8 px halo against 16 px
        // tiles, where the halo's tile placement (an estimate, FX-019-D6) is off enough that the
        // measured top tiles show 5 transitions (recorded in tasks.md, VIS-002-T10).
        let size = 128
        let parameters = BloomParameters(enabled: true, intensity: 1, radius: 0.06, threshold: 0.1, knee: 1)
        let generator = try rig.build {
            try LinearSpectrumGenerator(device: rig.device, pixelFormat: format, configuration: LinearSpectrumConfiguration(barCount: .b32))
        }
        let bloom = try rig.build { try BloomEffect(device: rig.device, pixelFormat: format, parameters: parameters) }
        generator.downstreamLuminance = BloomLuminanceModel(parameters: parameters)
        let chain = try EffectChain(device: rig.device, pixelFormat: format, effects: [bloom])
        try chain.prepare(width: size, height: size)
        let output = try rig.makeTexture(width: size, height: size, format: format)
        let full = [Float](repeating: 1, count: 32), empty = [Float](repeating: 0, count: 32)
        let dt = 1.0 / 60
        var shown: [[FlashLevels]] = []
        for f in 0..<90 {
            let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
            let context = VisualFrameContext(timeNanoseconds: UInt64(f) * 16_666_667, frameDuration: dt, reduceFlashing: true)
            let drawn = (f % 2 == 0 ? full : empty).withUnsafeBufferPointer { b in
                chain.encode(output: output, commandBuffer: commands) { target in
                    generator.encode(into: target, commandBuffer: commands, bands: b, context: context)
                }
            }
            XCTAssertTrue(drawn, "frame \(f)")
            let buffer = try rig.encodeReadBack(output, commands: commands)
            commands.commit()
            commands.waitUntilCompleted()
            let image = rig.decode(RenderRig.bytes(of: buffer), width: size, height: size, format: format)
            var l = [FlashLevels](repeating: .zero, count: FlashZones.count)
            for y in 0..<size {
                for x in 0..<size {
                    let p = image[x, y]
                    let z = (y * 4 / size) * 4 + x * 4 / size
                    let lum = luminance(p), red = Double(max(p.x - p.y - p.z, 0))
                    l[z].luminance += lum / Double(size * size / 16); l[z].redness += red / Double(size * size / 16)
                    l[FlashZones.wholeFrame].luminance += lum / Double(size * size)
                    l[FlashZones.wholeFrame].redness += red / Double(size * size)
                }
            }
            shown.append(l)
        }
        let envelope = FlashEnvelopeConfiguration.reduceFlashing
        let times = [Double](repeating: dt, count: shown.count)
        var worst = 0
        var worstTileExcess = 0.0
        for z in 0..<FlashZones.count {
            for s in FlashSignal.allCases {
                let r = FlashAnalysis.analyze(shown.map { $0[z][s] }, frameTimes: times, threshold: envelope.threshold(for: s))
                worst = max(worst, r.maxTransitionsPerWindow)
                // The whole frame is modeled exactly (bar edges on whole pixels): + 0.002 as FX-019-T14.
                // Tiles are estimates (the halo's placement, FX-019-D6): the bars' ends all sit in
                // the top row, where the measured rise exceeded the modeled one by 0.030 on the M5 Max
                // and up to 0.035 at 256 × 256 (FX-019-T14 allows 0.03 for the circular spectrum);
                // bounded at 0.04 so GPU differences do not flake.
                let excess = r.maxRise - (envelope.riseRatePerSecond ?? 0) * dt
                worstTileExcess = max(worstTileExcess, z == FlashZones.wholeFrame ? 0 : excess)
                XCTAssertLessThanOrEqual(excess, z == FlashZones.wholeFrame ? 0.002 : 0.04, "area \(z) \(s): rise")
            }
        }
        XCTAssertLessThanOrEqual(worst, envelope.transitionBudget)
        XCTAssertGreaterThan(shown.map { $0[FlashZones.wholeFrame].luminance }.max() ?? 0, 0.005, "frames were not blank")
        print("VIS-002 linear spectrum (GPU \(rig.device.name), \(size) × \(size), glow, Reduce flashing on, measured pixels): worst \(worst) transitions per window (limit \(envelope.transitionBudget)); worst tile rise above the modeled bound \(String(format: "%.4f", worstTileExcess))")
    }
    #endif
}
