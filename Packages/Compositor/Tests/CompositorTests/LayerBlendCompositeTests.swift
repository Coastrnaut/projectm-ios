// CMP-004-T08 (US1: "Each mode matches reference pixel equations within tolerance"; CMP-004-S1-S3),
// T09 (US2: opacity, transforms, apply, chains, allocation, capture; CMP-004-S4, R5, R6) and T14 (the
// GPU time bench, CMP-004-S6). GPU tests at 64 × 64 through the real Metal compositor; skipped without a
// Metal device. Pictures are uploaded as half floats, so the CPU reference (`LayerBlend`, Double) sees
// exactly the inputs the GPU sees. Tolerances (research CMP-004-D6): 1e-3 per linear channel in the
// half-float composite, 1/255 per channel in an 8-bit sRGB output.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Compositor
import Foundation
import FrameCapture
import Metal
import XCTest

/// Float → IEEE half (round to nearest even); Float16 is unavailable on some Mac architectures.
private enum HalfEncoder {
    static func bits(_ value: Float) -> UInt16 {
        if value.isNaN { return 0x7E00 }
        let sign: UInt16 = value.sign == .minus ? 0x8000 : 0
        let a: Float = Swift.abs(value)
        if a >= 65520 { return sign | 0x7C00 }
        if a < 6.103515625e-05 {
            let steps: Float = (a / 5.9604644775390625e-08).rounded(.toNearestOrEven)
            return sign | UInt16(steps)
        }
        let e: Int = Int(a.exponent)
        let unit: Float = a / Float(sign: .plus, exponent: e, significand: 1)
        var mantissa: Float = ((unit - 1) * 1024).rounded(.toNearestOrEven)
        var biased: Int = e + 15
        if mantissa == 1024 { mantissa = 0; biased += 1 }
        return sign | UInt16(biased << 10) | UInt16(mantissa)
    }
}

/// Blits fixed half-float pixels (64 × 64, linear premultiplied RGBA) into its picture every frame.
private final class PatternLayer: LayerSource {
    let layerName: String
    let fallback = LayerFallback.transparent
    let width: Int
    let height: Int
    private let buffer: MTLBuffer
    var settings = LayerCompositeSettings()
    var compositeSettings: LayerCompositeSettings { settings }

    init(_ name: String, device: MTLDevice, width: Int, height: Int, halves: [UInt16]) throws {
        layerName = name
        self.width = width
        self.height = height
        buffer = try XCTUnwrap(halves.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> MTLBuffer? in
            device.makeBuffer(bytes: raw.baseAddress!, length: raw.count, options: .storageModeShared)
        })
    }

    func prepare(picture: LayerPictureDescriptor, device: MTLDevice) throws(LayerSourceError) {}

    func render(into picture: MTLTexture, commandBuffer: MTLCommandBuffer, frame: LayerFrameContext,
                audio: LayerAudioContext) throws(LayerSourceError) {
        guard let blit = commandBuffer.makeBlitCommandEncoder() else { throw .resourceUnavailable("blit") }
        blit.copy(from: buffer, sourceOffset: 0, sourceBytesPerRow: width * 8, sourceBytesPerImage: width * height * 8,
                  sourceSize: MTLSize(width: width, height: height, depth: 1), to: picture, destinationSlice: 0,
                  destinationLevel: 0, destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.endEncoding()
    }
}

/// Holds the capture handler's result (written once on Metal's completion thread).
private final class BlendCaptureBox: @unchecked Sendable {
    private let lock = NSLock()
    private var pixels: CapturedPixels?
    func set(_ p: CapturedPixels?) { lock.lock(); pixels = p; lock.unlock() }
    func get() -> CapturedPixels? { lock.lock(); defer { lock.unlock() }; return pixels }
}

/// One test picture: the half bits uploaded and the same values as Double (what the GPU reads).
private struct Pattern {
    var halves: [UInt16] = []
    var values: [LayerBlend.Pixel] = []

    init(width: Int, height: Int, pixel: (Int) -> LayerBlend.Pixel) {
        for k in 0..<(width * height) {
            let p = pixel(k)
            var v = LayerBlend.Pixel.zero
            for c in 0..<4 {
                let h = HalfEncoder.bits(Float(p[c]))
                halves.append(h)
                v[c] = Double(Half.toFloat(h))
            }
            values.append(v)
        }
    }
}

final class LayerBlendCompositeTests: XCTestCase {
    private static let size = 64
    private static let levels: [Double] = [0, 0.25, 0.5, 0.75, 1]
    /// (αb, αs) pairs of the grid.
    private static let alphaPairs: [(Double, Double)] = [(1, 1), (0.5, 1), (1, 0.5), (0.5, 0.25)]
    private static let kind = LayerKind("test.pattern")

    // MARK: - Grid patterns

    /// Backdrop: encoded level per channel (shifted per channel), alpha from the pair; pixel k.
    private static func backdropPixel(_ k: Int) -> LayerBlend.Pixel {
        let level = levels[k % 5], g = levels[(k + 1) % 5], b = levels[(k + 3) % 5]
        let alpha = alphaPairs[(k / 25) % 4].0
        return LayerBlend.premultipliedLinear(encoded: level, g, b, alpha: alpha)
    }

    /// Source: every combination with the backdrop over the first 100 pixels (per channel shifted);
    /// a few broken pixels (NaN, negative, infinite) at the end, which read 0 like normal.
    private static func sourcePixel(_ k: Int) -> LayerBlend.Pixel {
        let n = size * size
        if k == n - 1 { return LayerBlend.Pixel(.nan, 0.2, 0.2, 1) }
        if k == n - 2 { return LayerBlend.Pixel(-1, 0.2, 0.2, 1) }
        if k == n - 3 { return LayerBlend.Pixel(.infinity, 0.2, 0.2, 1) }
        let row = k / 5
        let level = levels[row % 5], g = levels[(row + 2) % 5], b = levels[(row + 4) % 5]
        let alpha = alphaPairs[(k / 25) % 4].1
        return LayerBlend.premultipliedLinear(encoded: level, g, b, alpha: alpha)
    }

    private func patterns() -> (backdrop: Pattern, source: Pattern) {
        (Pattern(width: Self.size, height: Self.size, pixel: Self.backdropPixel),
         Pattern(width: Self.size, height: Self.size, pixel: Self.sourcePixel))
    }

    // MARK: - Rig helpers

    /// A compositor holding `layers`, bottom first, applied as a stack with `settings` per layer.
    private func compositor(_ rig: GPURig, _ layers: [PatternLayer], _ settings: [LayerCompositeSettings]) throws
        -> (Compositor, LayerStack, [LayerInstanceID]) {
        let compositor = try Compositor(device: rig.device)
        var stack = LayerStack()
        var ids: [LayerInstanceID] = []
        for (n, s) in settings.enumerated() {
            ids.append(try stack.add(LayerDescriptor(kind: Self.kind, parameters: ["slot": Double(n)]), settings: s))
        }
        try compositor.apply(stack) { (entry: LayerStackEntry) throws(LayerSourceError) -> any LayerSource in
            layers[Int(entry.descriptor.parameters["slot"] ?? 0)]
        }
        return (compositor, stack, ids)
    }

    private func layers(_ rig: GPURig, _ patterns: [Pattern]) throws -> [PatternLayer] {
        try patterns.enumerated().map { (pair: (offset: Int, element: Pattern)) throws -> PatternLayer in
            try PatternLayer("pattern \(pair.offset)", device: rig.device, width: Self.size, height: Self.size, halves: pair.element.halves)
        }
    }

    private func raw(_ rig: GPURig, _ texture: MTLTexture, bytesPerPixel: Int) throws -> [UInt8] {
        let rowBytes = texture.width * bytesPerPixel
        let buffer = try XCTUnwrap(rig.device.makeBuffer(length: rowBytes * texture.height, options: .storageModeShared))
        let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
        let blit = try XCTUnwrap(commands.makeBlitCommandEncoder())
        blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: texture.width, height: texture.height, depth: 1), to: buffer,
                  destinationOffset: 0, destinationBytesPerRow: rowBytes, destinationBytesPerImage: rowBytes * texture.height)
        blit.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        let count = rowBytes * texture.height
        return Array(UnsafeBufferPointer(start: buffer.contents().bindMemory(to: UInt8.self, capacity: count), count: count))
    }

    /// Worst per-channel difference between GPU pixels and expected pixels.
    private func worst(_ gpu: [Pixel], _ expected: [LayerBlend.Pixel]) -> (Double, Int) {
        var worst = 0.0
        var at = -1
        for k in expected.indices {
            for c in 0..<4 {
                let d: Double = Swift.abs(Double(gpu[k][c]) - expected[k][c])
                if !(d <= worst) { worst = d; at = k }
            }
        }
        return (worst, at)
    }

    private func reference(_ mode: LayerBlendMode, _ backdrop: [LayerBlend.Pixel], _ source: [LayerBlend.Pixel],
                           opacity: Double = 1) -> [LayerBlend.Pixel] {
        zip(backdrop, source).map { (pair: (LayerBlend.Pixel, LayerBlend.Pixel)) -> LayerBlend.Pixel in
            LayerBlend.composite(mode, backdrop: pair.0, source: pair.1, opacity: opacity)
        }
    }

    // MARK: - US1: the acceptance

    func testEveryModeMatchesTheReferenceOnTheGrid() throws {
        let rig = try GPURig()
        let (backdrop, source) = patterns()
        var report: [String] = []
        for mode in LayerBlendMode.allCases {
            let (compositor, _, _) = try compositor(rig, try layers(rig, [backdrop, source]),
                                                    [LayerCompositeSettings(), LayerCompositeSettings(blendMode: mode)])
            let expected = reference(mode, backdrop.values, source.values)

            let linear = try rig.output()
            try rig.frame(compositor, into: linear, time: 1_000_000_000)
            let (linearError, at) = worst(try rig.read(linear), expected)
            XCTAssertLessThanOrEqual(linearError, 1e-3, "\(mode): composite pixel \(at) differs by \(linearError)")
            XCTAssertEqual(compositor.blendDraws, mode == .normal ? 0 : 1)

            // The same frame encoded to an 8-bit sRGB output (the screen's format).
            let encoded = try rig.output(.bgra8Unorm_srgb)
            try rig.frame(compositor, into: encoded, time: 1_016_666_667)
            let bytes = try raw(rig, encoded, bytesPerPixel: 4)
            var byteError = 0.0
            for k in expected.indices {
                let e = expected[k]
                let wanted: [Double] = [LayerBlend.encode(e[2]), LayerBlend.encode(e[1]), LayerBlend.encode(e[0]), min(max(e[3], 0), 1)]
                for c in 0..<4 {
                    let got: Double = Double(bytes[k * 4 + c])
                    let want: Double = wanted[c] * 255
                    byteError = max(byteError, Swift.abs(got - want))
                }
            }
            XCTAssertLessThanOrEqual(byteError, 1, "\(mode): 8-bit sRGB output differs by \(byteError)/255")
            report.append("\(mode.rawValue): linear \(String(format: "%.2e", linearError)), 8-bit \(String(format: "%.2f", byteError))/255")
        }
        print("CMP-004 worst errors vs the reference: " + report.joined(separator: "; "))
    }

    func testFiftyPercentGreysGiveTheHandCheckedValues() throws {
        let rig = try GPURig()
        let grey = LayerBlend.premultipliedLinear(encoded: 0.5, 0.5, 0.5, alpha: 1)
        let pattern = Pattern(width: Self.size, height: Self.size) { (_: Int) -> LayerBlend.Pixel in grey }
        let expected: [LayerBlendMode: Double] = [.multiply: 0.25, .screen: 0.75, .overlay: 0.5, .difference: 0, .add: 1, .normal: 0.5]
        for mode in LayerBlendMode.allCases {
            let (compositor, _, _) = try compositor(rig, try layers(rig, [pattern, pattern]),
                                                    [LayerCompositeSettings(), LayerCompositeSettings(blendMode: mode)])
            let output = try rig.output()
            try rig.frame(compositor, into: output, time: 1)
            let want = try XCTUnwrap(expected[mode])
            let pixel = try rig.read(output)[0]
            XCTAssertEqual(LayerBlend.encode(Double(pixel.y)), want, accuracy: 2e-3, "\(mode) of two 50 % greys (encoded)")
            XCTAssertEqual(Double(pixel.w), 1, accuracy: 1e-6)
        }
    }

    func testAModeOverTransparentIsExactlyNormal() throws {
        let rig = try GPURig()
        let (_, source) = patterns()
        let normalOutput = try rig.output()
        let (normal, _, _) = try compositor(rig, try layers(rig, [source]), [LayerCompositeSettings()])
        try rig.frame(normal, into: normalOutput, time: 1)
        let want = try raw(rig, normalOutput, bytesPerPixel: 8)
        for mode in LayerBlendMode.allCases where mode != .normal {
            let (alone, _, _) = try compositor(rig, try layers(rig, [source]), [LayerCompositeSettings(blendMode: mode)])
            let output = try rig.output()
            try rig.frame(alone, into: output, time: 1)
            XCTAssertEqual(try raw(rig, output, bytesPerPixel: 8), want, "\(mode) over transparent is normal, bit for bit")
        }
    }

    // MARK: - US2: opacity, transforms, apply, chains

    func testOpacityZeroIsTheStackWithoutTheLayerAndHalfMatchesTheReference() throws {
        let rig = try GPURig()
        let (backdrop, source) = patterns()
        let (without, _, _) = try compositor(rig, try layers(rig, [backdrop]), [LayerCompositeSettings()])
        let withoutOutput = try rig.output()
        try rig.frame(without, into: withoutOutput, time: 1)
        let want = try raw(rig, withoutOutput, bytesPerPixel: 8)
        for mode in LayerBlendMode.allCases {
            let (zero, _, _) = try compositor(rig, try layers(rig, [backdrop, source]),
                                              [LayerCompositeSettings(), LayerCompositeSettings(opacity: 0, blendMode: mode)])
            let zeroOutput = try rig.output()
            try rig.frame(zero, into: zeroOutput, time: 1)
            XCTAssertEqual(try raw(rig, zeroOutput, bytesPerPixel: 8), want, "\(mode) at opacity 0 contributes nothing")

            let (half, _, _) = try compositor(rig, try layers(rig, [backdrop, source]),
                                              [LayerCompositeSettings(), LayerCompositeSettings(opacity: 0.5, blendMode: mode)])
            let halfOutput = try rig.output()
            try rig.frame(half, into: halfOutput, time: 1)
            let (error, at) = worst(try rig.read(halfOutput), reference(mode, backdrop.values, source.values, opacity: 0.5))
            XCTAssertLessThanOrEqual(error, 1e-3, "\(mode) at opacity 0.5: pixel \(at) differs by \(error)")
        }
    }

    func testATransformedModeLayerBlendsItsPlacedPicture() throws {
        let rig = try GPURig()
        let (backdrop, source) = patterns()
        let moved = try LayerTransform(translation: LayerPoint(x: 0.25, y: 0))
        // The placed picture, as a normal layer alone shows it (whole-pixel shift: exact texels).
        let (placedAlone, _, _) = try compositor(rig, try layers(rig, [source]), [LayerCompositeSettings(transform: moved)])
        let placedOutput = try rig.output()
        try rig.frame(placedAlone, into: placedOutput, time: 1)
        let placed: [LayerBlend.Pixel] = try rig.read(placedOutput).map { (p: Pixel) -> LayerBlend.Pixel in
            LayerBlend.Pixel(Double(p.x), Double(p.y), Double(p.z), Double(p.w))
        }
        for mode in [LayerBlendMode.multiply, .overlay, .difference] {
            let (stacked, _, _) = try compositor(rig, try layers(rig, [backdrop, source]),
                                                 [LayerCompositeSettings(), LayerCompositeSettings(blendMode: mode, transform: moved)])
            let output = try rig.output()
            try rig.frame(stacked, into: output, time: 1)
            let (error, at) = worst(try rig.read(output), reference(mode, backdrop.values, placed))
            XCTAssertLessThanOrEqual(error, 1e-3, "transformed \(mode): pixel \(at) differs by \(error)")
            XCTAssertEqual(stacked.transformedDraws, 0, "a mode layer is drawn by the blend path")
            XCTAssertEqual(stacked.blendDraws, 1)
        }
    }

    func testAModeChangeAtApplyShowsNextFrameWithoutRecreatingTheLayer() throws {
        let rig = try GPURig()
        let (backdrop, source) = patterns()
        let made = try layers(rig, [backdrop, source])
        var calls = 0
        let compositor = try Compositor(device: rig.device)
        let factory: LayerFactory = { (entry: LayerStackEntry) throws(LayerSourceError) -> any LayerSource in
            calls += 1
            return made[Int(entry.descriptor.parameters["slot"] ?? 0)]
        }
        var stack = LayerStack()
        try stack.add(LayerDescriptor(kind: Self.kind, parameters: ["slot": 0]))
        let top = try stack.add(LayerDescriptor(kind: Self.kind, parameters: ["slot": 1]), settings: LayerCompositeSettings(blendMode: .multiply))
        try compositor.apply(stack, makeLayer: factory)
        let output = try rig.output()
        try rig.frame(compositor, into: output, time: 0)
        let preparations = compositor.layerPreparations
        let allocations = compositor.pictureAllocations

        try stack.setSettings(LayerCompositeSettings(blendMode: .screen), of: top)
        try compositor.apply(stack, makeLayer: factory)
        XCTAssertEqual(compositor.shownBlendMode(ofLayer: 1), .screen)
        try rig.frame(compositor, into: output, time: 16_666_667)
        let (error, at) = worst(try rig.read(output), reference(.screen, backdrop.values, source.values))
        XCTAssertLessThanOrEqual(error, 1e-3, "screen after the change: pixel \(at) differs by \(error)")
        XCTAssertEqual(calls, 2, "no layer created")
        XCTAssertEqual(compositor.layerPreparations, preparations, "no layer prepared")
        XCTAssertEqual(compositor.pictureAllocations, allocations, "the second composite is reused")
    }

    func testTwoModeLayersInARowEachReadTheResultBelow() throws {
        let rig = try GPURig()
        let (backdrop, source) = patterns()
        let third = Pattern(width: Self.size, height: Self.size) { (k: Int) -> LayerBlend.Pixel in
            Self.backdropPixel(k + 7)
        }
        let (compositor, _, _) = try compositor(rig, try layers(rig, [backdrop, source, third]),
                                                [LayerCompositeSettings(), LayerCompositeSettings(blendMode: .multiply),
                                                 LayerCompositeSettings(opacity: 0.75, blendMode: .screen)])
        let output = try rig.output()
        try rig.frame(compositor, into: output, time: 1)
        let middle = reference(.multiply, backdrop.values, source.values)
        let expected = reference(.screen, middle, third.values, opacity: 0.75)
        let (error, at) = worst(try rig.read(output), expected)
        XCTAssertLessThanOrEqual(error, 2e-3, "multiply then screen: pixel \(at) differs by \(error) (two half roundings)")
        XCTAssertEqual(compositor.blendDraws, 2)
    }

    func testNormalStacksAllocateNoSecondCompositeAndModesAllocateOne() throws {
        let rig = try GPURig()
        let (backdrop, source) = patterns()
        let (normal, _, _) = try compositor(rig, try layers(rig, [backdrop, source]), [LayerCompositeSettings(), LayerCompositeSettings()])
        let output = try rig.output()
        try rig.frame(normal, into: output, time: 1)
        let normalAllocations = normal.pictureAllocations
        XCTAssertEqual(normal.blendDraws, 0)

        let (moded, _, _) = try compositor(rig, try layers(rig, [backdrop, source]),
                                           [LayerCompositeSettings(), LayerCompositeSettings(blendMode: .difference)])
        try rig.frame(moded, into: output, time: 1)
        XCTAssertEqual(moded.pictureAllocations, normalAllocations + 1, "one pooled second composite")
        for k in 1...3 { try rig.frame(moded, into: output, time: 1 + UInt64(k) * 16_666_667) }
        XCTAssertEqual(moded.pictureAllocations, normalAllocations + 1, "nothing created per frame")
    }

    func testCaptureAndReduceFlashingSeeTheFinishedComposite() throws {
        let rig = try GPURig()
        let (backdrop, source) = patterns()
        let (compositor, _, _) = try compositor(rig, try layers(rig, [backdrop, source]),
                                                [LayerCompositeSettings(), LayerCompositeSettings(blendMode: .overlay)])
        let captured = expectation(description: "capture")
        let box = BlendCaptureBox()
        compositor.requestFrameCapture { (result: CapturedPixels?) in
            box.set(result)
            captured.fulfill()
        }
        let output = try rig.output()
        try rig.frame(compositor, into: output, time: 1)
        wait(for: [captured], timeout: 10)
        let shown = try raw(rig, output, bytesPerPixel: 8)
        let capture = try XCTUnwrap(box.get())
        guard case let .linearPremultipliedHalfRGBA(halves) = capture.layout else { return XCTFail("layout") }
        let capturedBytes: [UInt8] = halves.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> [UInt8] in Array(raw) }
        XCTAssertEqual(capturedBytes, shown, "the capture is the shown frame, after the blend")

        XCTAssertTrue(try rig.frame(compositor, into: output, time: 16_666_668, reduceFlashing: true),
                      "a Reduce-flashing frame with a mode layer encodes")
    }

    // MARK: - CMP-004-T14: GPU time per mode (a measurement; never an assertion)

    func testBenchGPUTimePerMode() throws {
        guard ProcessInfo.processInfo.environment["CMP004_BENCH"] == "1" else {
            throw XCTSkip("Set CMP004_BENCH=1 to measure GPU time per mode (Release, Mac; not device evidence).")
        }
        let rig = try GPURig()
        let width = 1920, height = 1080
        let output = try rig.output(.bgra8Unorm_srgb, width: width, height: height)
        var lines: [String] = []
        for mode in LayerBlendMode.allCases {
            let bottom = SolidLayer("bottom", color: Pixel(0.2, 0.3, 0.4, 1))
            let top = SolidLayer("top", color: Pixel(0.3, 0.2, 0.1, 0.6))
            top.settings = LayerCompositeSettings(blendMode: mode)
            let compositor = try Compositor(device: rig.device, layers: [bottom, top])
            var samples: [Double] = []
            for k in 0..<130 {
                let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
                _ = compositor.composite(into: output, commandBuffer: commands, presentationTimeNanoseconds: UInt64(k) * 16_666_667,
                                         contentScale: 2, reduceFlashing: false, audio: .empty)
                commands.commit()
                commands.waitUntilCompleted()
                let gpu: Double = commands.gpuEndTime - commands.gpuStartTime
                if k >= 10 { samples.append(gpu * 1000) }   // first 10 frames warm up
            }
            samples.sort()
            let median: Double = samples[samples.count / 2]
            let p95: Double = samples[samples.count * 95 / 100]
            lines.append("\(mode.rawValue): median \(String(format: "%.3f", median)) ms, p95 \(String(format: "%.3f", p95)) ms")
        }
        print("CMP-004 GPU time per frame, 1920×1080, two layers (whole frame: clears, composite, flash guard, output): "
              + lines.joined(separator: "; "))
    }
}
#endif
