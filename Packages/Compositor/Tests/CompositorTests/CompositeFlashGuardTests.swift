// CMP-001-T12 (US5: flashing bounded on the composite; CMP-001-S5). A 60 Hz white/black strobe
// layer composited for 2 s at 64 × 64; each output frame is read back, its 17 areas measured
// (16 tiles of 16 × 16 pixels, row 0 at the top, and the whole frame as their mean) and the series
// analysed with FlashSafety's independent `FlashAnalysis`. The GPU gain is compared with the Swift
// `FlashEnvelope` fed the same input levels. Skipped without a Metal device.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Compositor
import FlashSafety
import Metal
import XCTest

/// White on even frames, black on odd ones (opaque).
final class StrobeLayer: LayerSource {
    let layerName = "strobe"
    let fallback = LayerFallback.transparent
    var color: (Int) -> Pixel = { $0 % 2 == 0 ? Pixel(1, 1, 1, 1) : Pixel(0, 0, 0, 1) }

    func prepare(picture: LayerPictureDescriptor, device: MTLDevice) throws(LayerSourceError) {}

    func render(into picture: MTLTexture, commandBuffer: MTLCommandBuffer, frame: LayerFrameContext,
                audio: LayerAudioContext) throws(LayerSourceError) {
        SolidLayer.clear(picture, to: color(Int(frame.frameIndex)), commandBuffer: commandBuffer)
    }
}

final class CompositeFlashGuardTests: XCTestCase {
    private static let frameNanoseconds: UInt64 = 16_666_667

    /// The 17 area levels (luminance, redness) of a 64 × 64 linear picture.
    private func areas(_ pixels: [Pixel], side: Int = 64) -> [FlashLevels] {
        var out: [FlashLevels] = []
        let tile = side / 4
        for ty in 0..<4 {
            for tx in 0..<4 {
                var y = 0.0, r = 0.0
                for py in (ty * tile)..<((ty + 1) * tile) {
                    for px in (tx * tile)..<((tx + 1) * tile) {
                        let p = pixels[py * side + px]
                        y += FlashColor.relativeLuminance(red: Double(p.x), green: Double(p.y), blue: Double(p.z))
                        r += FlashColor.redness(red: Double(p.x), green: Double(p.y), blue: Double(p.z))
                    }
                }
                out.append(FlashLevels(luminance: y / Double(tile * tile), redness: r / Double(tile * tile)))
            }
        }
        out.append(FlashLevels(luminance: out.map(\.luminance).reduce(0, +) / 16, redness: out.map(\.redness).reduce(0, +) / 16))
        return out
    }

    private func strobe(reduceFlashing: Bool) throws {
        let rig = try GPURig()
        let layer = StrobeLayer()
        let compositor = try Compositor(device: rig.device, layers: [layer])
        let output = try rig.output()
        let reference = FlashEnvelope()
        let configuration = FlashEnvelopeConfiguration.forReduceFlashing(reduceFlashing)
        var series = [[Double]](repeating: [], count: FlashZones.count)
        var frameTimes: [Double] = []
        var worstGainError: Float = 0
        for i in 0..<120 {
            try rig.frame(compositor, into: output, time: 1_000_000_000 + UInt64(i) * Self.frameNanoseconds, reduceFlashing: reduceFlashing)
            let shown = areas(try rig.read(output))
            let dt = i == 0 ? 0 : Double(Self.frameNanoseconds) / 1e9
            frameTimes.append(dt)
            for z in 0..<FlashZones.count { series[z].append(shown[z].luminance) }
            // The reference: the same input levels (white = 1, black = 0 in every area).
            let level = i % 2 == 0 ? 1.0 : 0.0
            let inputs = [FlashLevels](repeating: FlashLevels(luminance: level, redness: 0), count: FlashZones.count)
            let expected = inputs.withUnsafeBufferPointer { reference.gain(inputs: $0, frameTime: dt, configuration: configuration) }
            if level > 0 { worstGainError = max(worstGainError, abs(compositor.lastFlashGain - expected)) }
        }
        let limit = reduceFlashing ? 4 : 6
        let worstWindow = (0..<FlashZones.count).map {
            FlashAnalysis.analyze(series[$0], frameTimes: frameTimes, threshold: configuration.luminanceThreshold).maxTransitionsPerWindow
        }.max() ?? 0
        print("CMP-001 strobe (Reduce flashing \(reduceFlashing)): worst transitions per window \(worstWindow), worst GPU-CPU gain difference \(worstGainError)")
        for z in 0..<FlashZones.count {
            let report = FlashAnalysis.analyze(series[z], frameTimes: frameTimes, threshold: configuration.luminanceThreshold)
            XCTAssertLessThanOrEqual(report.maxTransitionsPerWindow, limit, "area \(z): transitions per 1 s window")
            if reduceFlashing {
                XCTAssertLessThanOrEqual(report.maxRise, 0.25 / 60 + 1e-3, "area \(z): rise per frame")
            }
        }
        XCTAssertLessThanOrEqual(worstGainError, 1e-4, "GPU gain matches FlashEnvelope")
        XCTAssertGreaterThan(FlashAnalysis.analyze(series[16], frameTimes: frameTimes, threshold: 0.1).transitions, 0,
                             "the strobe is not simply blacked out")
    }

    func testStrobeIsBoundedWithReduceFlashing() throws {
        try strobe(reduceFlashing: true)
    }

    func testStrobeIsBoundedWithTheAlwaysOnCap() throws {
        try strobe(reduceFlashing: false)
    }

    func testSteadyPictureKeepsGainOne() throws {
        let rig = try GPURig()
        let layer = StrobeLayer()
        layer.color = { _ in Pixel(0.5, 0.5, 0.5, 1) }
        let compositor = try Compositor(device: rig.device, layers: [layer])
        let output = try rig.output()
        for i in 0..<10 {
            try rig.frame(compositor, into: output, time: UInt64(i) * Self.frameNanoseconds, reduceFlashing: true)
            XCTAssertEqual(compositor.lastFlashGain, 1)
        }
        assertAll(try rig.read(output), equal: Pixel(0.5, 0.5, 0.5, 1), tolerance: 1e-3, "unchanged")
    }

    func testResetLetsTheNextFrameThrough() throws {
        let rig = try GPURig()
        let layer = StrobeLayer()
        let compositor = try Compositor(device: rig.device, layers: [layer])
        let output = try rig.output()
        for i in 0..<30 { try rig.frame(compositor, into: output, time: UInt64(i) * Self.frameNanoseconds, reduceFlashing: true) }
        // Frame 30 is white; the envelope (rise 0.25/s) would hold it near black.
        compositor.resetFlashHistory()
        try rig.frame(compositor, into: output, time: 30 * Self.frameNanoseconds, reduceFlashing: true)
        XCTAssertEqual(compositor.lastFlashGain, 1)
        assertAll(try rig.read(output), equal: Pixel(1, 1, 1, 1), tolerance: 1e-3, "a new scene starts unlimited")
    }
}
#endif
