// FX-002-T06 to T08, T10, T12, T13: the output tone map on the GPU (FX-002-S1, S3, S4, S7). Special values go
// through the real `cmp_output` on a hand-filled composite (`OutputPassRig`; every layer pass already sanitises
// them); the reference gradient goes through the whole compositor. Results are compared with `ToneMap` (the
// plain-Swift reference). Skipped without a Metal device.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
@testable import Compositor
import FrameCapture
import Metal
import XCTest

/// FX-002: a fixed picture of linear values (any size the compositor asks for), filled by `fill(x, y, width, height)`
/// and blitted from a shared buffer every frame.
final class ValueLayer: LayerSource {
    let layerName = "values"
    let fallback = LayerFallback.transparent
    let fill: (Int, Int, Int, Int) -> SIMD4<Float>
    private var staging: MTLBuffer?
    private var size: LayerPictureDescriptor?

    init(fill: @escaping (Int, Int, Int, Int) -> SIMD4<Float>) { self.fill = fill }

    func prepare(picture: LayerPictureDescriptor, device: MTLDevice) throws(LayerSourceError) {
        let w = picture.width, h = picture.height
        var halves: [UInt16] = []
        halves.reserveCapacity(w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let p: SIMD4<Float> = fill(x, y, w, h)
                for c in 0..<4 { halves.append(Float16(p[c]).bitPattern) }
            }
        }
        staging = halves.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> MTLBuffer? in
            guard let base = raw.baseAddress else { return nil }
            return device.makeBuffer(bytes: base, length: raw.count, options: .storageModeShared)
        }
        size = picture
        if staging == nil { throw .resourceUnavailable("value layer staging") }
    }

    func render(into picture: MTLTexture, commandBuffer: MTLCommandBuffer, frame: LayerFrameContext,
                audio: LayerAudioContext) throws(LayerSourceError) {
        guard let staging, let size, let blit = commandBuffer.makeBlitCommandEncoder() else { throw .notReady }
        blit.copy(from: staging, sourceOffset: 0, sourceBytesPerRow: size.width * 8, sourceBytesPerImage: size.width * size.height * 8,
                  sourceSize: MTLSize(width: size.width, height: size.height, depth: 1), to: picture, destinationSlice: 0,
                  destinationLevel: 0, destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.endEncoding()
    }
}

final class ToneMapOutputTests: XCTestCase {
    private static let frameNanoseconds: UInt64 = 16_666_667
    /// The reference gradient's hues (research FX-002-D6), one per row.
    private static let hues: [SIMD3<Float>] = [SIMD3(1, 1, 1), SIMD3(1, 0.5, 0.25), SIMD3(0.2, 0.4, 1), SIMD3(1, 0.05, 0.05)]
    private static let gradientWidth = 256
    private static let gradientMaximum: Float = 16

    /// Linear 0…16 along x, one hue per row, alpha 1 (half-rounded, as the picture stores it).
    private static func gradientValue(_ x: Int, _ y: Int, _ w: Int, _ h: Int) -> SIMD4<Float> {
        let t: Float = gradientMaximum * Float(x) / Float(max(w - 1, 1))
        let v: SIMD3<Float> = hues[y % hues.count]
        return SIMD4<Float>(t * v.x, t * v.y, t * v.z, 1)
    }

    /// The reference's display value of a half-rounded linear pixel.
    private static func reference(_ p: SIMD4<Float>) -> SIMD4<Double> {
        let rounded = SIMD4<Double>(Double(Float(Float16(p.x))), Double(Float(Float16(p.y))), Double(Float(Float16(p.z))),
                                    Double(Float(Float16(p.w))))
        return ToneMap.map(rounded)
    }

    private static func encoded(_ linear: SIMD4<Double>) -> SIMD4<Double> {
        SIMD4<Double>(LayerBlend.encode(linear.x), LayerBlend.encode(linear.y), LayerBlend.encode(linear.z), linear.w)
    }

    /// Worst per-channel difference between a GPU pixel and the expected one (NaN counts as infinite).
    private static func difference(_ gpu: SIMD4<Float>, _ expected: SIMD4<Double>) -> Double {
        var worst: Double = 0
        for c in 0..<4 {
            let d: Double = Swift.abs(Double(gpu[c]) - expected[c])
            worst = d.isNaN ? .infinity : max(worst, d)
        }
        return worst
    }

    // MARK: - US1: special values through the real output pass (T06)

    func testSpecialValuesThroughTheOutputPassMatchTheReference() throws {
        let rig = try OutputPassRig()
        let nan: Float = .nan
        let inf: Float = .infinity
        let pixels: [SIMD4<Float>] = [
            SIMD4(nan, 0.5, 0.5, 1), SIMD4(inf, 0.5, 0.5, 1), SIMD4(-inf, 0.5, 0.5, 1), SIMD4(-0.5, 0.5, 0.5, 1),
            SIMD4(0.5, 0.5, 0.5, nan), SIMD4(0.5, 0.5, 0.5, 2), SIMD4(0.5, 0.5, 0.5, -1), SIMD4(nan, nan, nan, nan),
            SIMD4(2, 0.5, 0.25, 1), SIMD4(16, 16, 16, 1), SIMD4(4, 0.1, 0.1, 1), SIMD4(0.9, 0.9, 0.9, 1),
            SIMD4(1, 1, 1, 1), SIMD4(0, 0, 0, 0), SIMD4(0.25, 0.5, 0.75, 0.5), SIMD4(60000, 2, 0, 1),
        ]
        let composite: MTLTexture = try rig.composite(pixels)
        let half: [SIMD4<Float>] = try rig.output(composite, format: .rgba16Float)
        XCTAssertEqual(rig.lastNonFiniteCount, 5, "NaN, +Inf, -Inf, NaN alpha, all NaN")
        let screen: [SIMD4<Float>] = try rig.output(composite, format: .bgra8Unorm_srgb)
        for (i, p) in pixels.enumerated() {
            let expected: SIMD4<Double> = Self.reference(p)
            XCTAssertLessThanOrEqual(Self.difference(half[i], expected), 0.002, "half float: \(p) → \(half[i]) vs \(expected)")
            let encodedExpected: SIMD4<Double> = Self.encoded(expected)
            XCTAssertLessThanOrEqual(Self.difference(screen[i], encodedExpected), 1.0 / 255 + 1e-6,
                                     "sRGB: \(p) → \(screen[i]) vs \(encodedExpected)")
            for c in 0..<4 {
                XCTAssertTrue(half[i][c] >= 0 && half[i][c] <= 1, "half float in 0…1: \(p) → \(half[i])")
            }
        }
    }

    /// FX-002-R3: in-range pixels leave the output pass exactly as the previous `cmp_output` wrote them.
    func testInRangeHalfFloatOutputIsBitIdentical() throws {
        let rig = try OutputPassRig()
        var pixels: [SIMD4<Float>] = []
        for k in 0..<256 {
            let f: Float = Float(k) / 255
            pixels.append(SIMD4(f, 1 - f, f * f, k % 3 == 0 ? 1 : f))
        }
        let out: [SIMD4<Float>] = try rig.output(try rig.composite(pixels), format: .rgba16Float)
        for (i, p) in pixels.enumerated() {
            for c in 0..<4 {
                XCTAssertEqual(Float16(out[i][c]).bitPattern, Float16(p[c]).bitPattern, "pixel \(i) channel \(c)")
            }
        }
    }

    // MARK: - US1: the acceptance, the reference gradient through the compositor (T07)

    private func gradientFrame(_ rig: GPURig, format: MTLPixelFormat, passes: OutputPassRig) throws -> [SIMD4<Float>] {
        let compositor = try Compositor(device: rig.device, layers: [ValueLayer(fill: Self.gradientValue)])
        let output: MTLTexture = try passes.target(format, width: Self.gradientWidth, height: Self.hues.count)
        try rig.frame(compositor, into: output, time: 1_000_000_000)
        XCTAssertEqual(compositor.lastFlashGain, 1, "a still first frame is never dimmed")
        XCTAssertEqual(compositor.nonFiniteOutputPixels, 0)
        return passes.readRaw(output)
    }

    func testReferenceGradientIsOrderedInRangeAndNaNFree() throws {
        let passes = try OutputPassRig()
        let rig: GPURig = passes.rig
        let w: Int = Self.gradientWidth
        for format in [MTLPixelFormat.bgra8Unorm_srgb, .rgba16Float] {
            let pixels: [SIMD4<Float>] = try gradientFrame(rig, format: format, passes: passes)
            let tolerance: Double = format == .rgba16Float ? 0.002 : 1.0 / 255 + 1e-6
            var worst: Double = 0
            for row in 0..<Self.hues.count {
                var previous = SIMD4<Float>(repeating: 0)
                for x in 0..<w {
                    let p: SIMD4<Float> = pixels[row * w + x]
                    for c in 0..<4 {
                        XCTAssertFalse(p[c].isNaN, "format \(format.rawValue) row \(row) x \(x): NaN")
                        XCTAssertTrue(p[c] >= 0 && p[c] <= 1, "format \(format.rawValue) row \(row) x \(x): \(p)")
                    }
                    for c in 0..<3 {
                        XCTAssertGreaterThanOrEqual(p[c], previous[c], "format \(format.rawValue) row \(row) x \(x) channel \(c): order")
                    }
                    previous = p
                    var expected: SIMD4<Double> = Self.reference(Self.gradientValue(x, row, w, Self.hues.count))
                    if format != .rgba16Float { expected = Self.encoded(expected) }
                    worst = max(worst, Self.difference(p, expected))
                }
                XCTAssertEqual(pixels[row * w + w - 1], SIMD4<Float>(1, 1, 1, 1), "row \(row) ends white")
            }
            print("FX-002 gradient \(format.rawValue): worst difference from the reference \(worst)")
            XCTAssertLessThanOrEqual(worst, tolerance, "format \(format.rawValue): GPU vs reference")
        }
    }

    // MARK: - US1: the non-finite counter (T08)

    /// The layer passes sanitise every picture, and over-range "over" accumulation saturates at the largest half
    /// (65504) on Apple GPUs rather than overflowing to +Inf, so a real stack cannot make the composite non-finite:
    /// it shows white. The counter is a defence for GPUs that overflow, checked below by injection.
    func testOverflowingStackSaturatesToWhite() throws {
        let passes = try OutputPassRig()
        let rig: GPURig = passes.rig
        let layers: [any LayerSource] = [SolidLayer("a", color: Pixel(40000, 0.25, 0, 0)), SolidLayer("b", color: Pixel(40000, 0.25, 0, 0))]
        let compositor = try Compositor(device: rig.device, layers: layers)
        let screen: MTLTexture = try passes.target(.bgra8Unorm_srgb, width: 8, height: 8)
        try rig.frame(compositor, into: screen, time: 1_000_000_000)
        XCTAssertEqual(compositor.nonFiniteOutputPixels, 0, "80000 saturates at 65504 (finite)")
        for p in passes.readRaw(screen) { XCTAssertEqual(p, SIMD4<Float>(1, 1, 1, 0), "luminance far above 1: white") }
    }

    /// FX-002-R7: a NaN composite is counted once per pixel by the screen pass, never by recording or capture, and
    /// shows 0. The NaN is injected into the compositor's own composite: a still (cached) layer makes the next frame
    /// reuse that composite (CMP-013 level 2), so the guard and the output passes run on it unchanged.
    func testNonFiniteCounterCountsTheScreenPassOnly() throws {
        let passes = try OutputPassRig()
        let rig: GPURig = passes.rig
        let compositor = try Compositor(device: rig.device, layers: [StillLayer("still", color: Pixel(0.5, 0.25, 0, 1))])
        let screen: MTLTexture = try passes.target(.bgra8Unorm_srgb, width: 8, height: 8)
        let recording: MTLTexture = try passes.target(.bgra8Unorm_srgb, width: 8, height: 8)
        try rig.frame(compositor, into: screen, time: 1_000_000_000)
        // Frame 2: the stack phase only, then the composite it returns is overwritten with NaN.
        let poison = try XCTUnwrap(rig.queue.makeCommandBuffer())
        let composite: MTLTexture = try XCTUnwrap(compositor.encodeScene(width: 8, height: 8, commandBuffer: poison,
                                                                          presentationTimeNanoseconds: 1_016_666_667, contentScale: 2,
                                                                          reduceFlashing: false, audio: .empty))
        XCTAssertTrue(compositor.compositeReused)
        let nan = Double.nan
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = composite
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: nan, green: 0.5, blue: 0.25, alpha: 1)
        poison.makeRenderCommandEncoder(descriptor: pass)?.endEncoding()
        poison.commit()
        poison.waitUntilCompleted()
        // Frame 3: screen, recording and capture of the poisoned composite.
        let captured = expectation(description: "capture")
        let box = CaptureBox()
        compositor.requestFrameCapture { (pixels: CapturedPixels?) in
            box.pixels = pixels
            captured.fulfill()
        }
        let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
        XCTAssertTrue(compositor.composite(into: screen, commandBuffer: commands, presentationTimeNanoseconds: 1_033_333_333,
                                           contentScale: 2, reduceFlashing: false, audio: .empty))
        XCTAssertTrue(compositor.compositeReused, "the poisoned composite is the one shown")
        XCTAssertTrue(compositor.encodeOutput(into: recording, commandBuffer: commands))
        commands.commit()
        commands.waitUntilCompleted()
        wait(for: [captured], timeout: 5)
        XCTAssertEqual(compositor.nonFiniteOutputPixels, 64, "every pixel once: recording and capture do not count")
        XCTAssertEqual(compositor.lastFlashGain, 1, "the guard measured the tone-mapped (finite) frame")
        let shown: [SIMD4<Float>] = passes.readRaw(screen)
        for p in shown {
            XCTAssertEqual(p.x, 0, "the NaN red channel shows 0")
            XCTAssertEqual(p.y, Float(LayerBlend.encode(0.5)), accuracy: 1.0 / 255, "green unaffected")
        }
        XCTAssertEqual(passes.readRaw(recording), shown, "recording equals the screen")
        guard case .linearPremultipliedHalfRGBA(let halves)? = box.pixels?.layout else { return XCTFail("no capture") }
        XCTAssertEqual(Half.toFloat(halves[0]), 0, "capture: NaN → 0")
        XCTAssertEqual(Half.toFloat(halves[1]), 0.5, accuracy: 0.001)

        // The bus binds its counter for its frame and the sink for `encodeOutput`; a finite frame counts nothing.
        let bus = try SceneTransitionBus(device: rig.device)
        bus.show(compositor)
        let busCommands = try XCTUnwrap(rig.queue.makeCommandBuffer())
        XCTAssertTrue(bus.encodeFrame(into: screen, commandBuffer: busCommands, presentationTimeNanoseconds: 1_050_000_000,
                                      contentScale: 2, reduceFlashing: false, audio: .empty))
        XCTAssertTrue(bus.encodeOutput(into: recording, commandBuffer: busCommands))
        busCommands.commit()
        busCommands.waitUntilCompleted()
        XCTAssertEqual(bus.nonFiniteOutputPixels, 64, "the bus's frame showed the same reused NaN composite once")
    }

    // MARK: - US2: recording and capture match the screen (T10)

    func testRecordingAndCaptureMatchTheScreenForAnOverRangeFrame() throws {
        let passes = try OutputPassRig()
        let rig: GPURig = passes.rig
        let w: Int = Self.gradientWidth, h: Int = Self.hues.count
        let compositor = try Compositor(device: rig.device, layers: [ValueLayer(fill: Self.gradientValue)])
        let screen: MTLTexture = try passes.target(.bgra8Unorm_srgb, width: w, height: h)
        let recording: MTLTexture = try passes.target(.bgra8Unorm_srgb, width: w, height: h)
        let box = CaptureBox()
        let captured = expectation(description: "capture")
        compositor.requestFrameCapture { (pixels: CapturedPixels?) in
            box.pixels = pixels
            captured.fulfill()
        }
        let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
        XCTAssertTrue(compositor.composite(into: screen, commandBuffer: commands, presentationTimeNanoseconds: 1_000_000_000,
                                           contentScale: 2, reduceFlashing: false, audio: .empty))
        XCTAssertTrue(compositor.encodeOutput(into: recording, commandBuffer: commands))
        commands.commit()
        commands.waitUntilCompleted()
        wait(for: [captured], timeout: 5)
        let shown: [SIMD4<Float>] = passes.readRaw(screen)
        XCTAssertEqual(passes.readRaw(recording), shown, "the recording's output pass equals the screen's")
        guard case .linearPremultipliedHalfRGBA(let halves)? = box.pixels?.layout else { return XCTFail("no capture") }
        var worst: Double = 0
        for i in 0..<(w * h) {
            for c in 0..<3 {
                let linear: Double = Double(Half.toFloat(halves[i * 4 + c]))
                XCTAssertFalse(linear.isNaN)
                XCTAssertTrue(linear >= 0 && linear <= 1, "capture value \(linear) in 0…1")
                worst = max(worst, Swift.abs(LayerBlend.encode(linear) - Double(shown[i][c])))
            }
        }
        print("FX-002 capture vs screen: worst encoded difference \(worst)")
        XCTAssertLessThanOrEqual(worst, 1.0 / 255 + 1e-6, "capture equals the screen within one 8-bit step")
    }

    // MARK: - US3: the flash limiter judges the tone-mapped colour (T12)

    private func alternate(_ low: Float, _ high: Float) throws -> (minimumGain: Float, outputs: [(gain: Float, shown: Float)]) {
        let passes = try OutputPassRig()
        let rig: GPURig = passes.rig
        let layer = StrobeLayer()
        layer.color = { (i: Int) -> Pixel in i % 2 == 0 ? Pixel(high, high, high, 1) : Pixel(low, low, low, 1) }
        let compositor = try Compositor(device: rig.device, layers: [layer])
        let output: MTLTexture = try passes.target(.rgba16Float, width: 16, height: 16)
        var minimum: Float = 1
        var outputs: [(gain: Float, shown: Float)] = []
        for i in 0..<60 {
            try rig.frame(compositor, into: output, time: 1_000_000_000 + UInt64(i) * Self.frameNanoseconds)
            let gain: Float = compositor.lastFlashGain
            minimum = min(minimum, gain)
            if i % 2 == 0 { outputs.append((gain, passes.readRaw(output)[0].x)) }
        }
        return (minimum, outputs)
    }

    func testFlashLimiterMeasuresTheToneMappedFrame() throws {
        // 1 ↔ 16: the screen shows steady white, so nothing is dimmed.
        let steady = try alternate(1, 16)
        XCTAssertEqual(steady.minimumGain, 1, "1 ↔ 16 is no visible change: the gain stays 1")
        for frame in steady.outputs { XCTAssertEqual(frame.shown, 1, "16 shows white") }
        // 0 ↔ 16: a full black-white flash as shown; the limiter engages and its gain multiplies the mapped white.
        let flash = try alternate(0, 16)
        XCTAssertLessThan(flash.minimumGain, 1, "0 ↔ 16 is limited")
        for frame in flash.outputs { XCTAssertEqual(frame.shown, frame.gain, accuracy: 0.002, "shown = gain × tone_map(16) = gain") }
        print("FX-002 limiter: 1↔16 minimum gain \(steady.minimumGain), 0↔16 minimum gain \(flash.minimumGain)")
    }

    // MARK: - Polish: GPU time (T13, recorded only)

    /// The output pass before FX-002 (kept here only, for the timing comparison).
    private static let previousOutputSource = """
    #include <metal_stdlib>
    using namespace metal;
    struct FullScreenOut { float4 position [[position]]; };
    fragment float4 cmp_output_previous(FullScreenOut in [[stage_in]], texture2d<float, access::read> composite [[texture(0)]],
                                        device const float *gain [[buffer(0)]]) {
        float4 c = composite.read(uint2(in.position.xy));
        float g = clamp(gain[0], 0.0, 1.0);
        return float4(c.rgb * g, c.a);
    }
    """

    func testOutputPassGPUTimeIsRecorded() throws {
        let passes = try OutputPassRig()
        let rig: GPURig = passes.rig
        let w = 1920, h = 1080
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: w, height: h, mipmapped: false)
        d.usage = [.shaderRead, .renderTarget]
        d.storageMode = .private
        let composite: MTLTexture = try XCTUnwrap(rig.device.makeTexture(descriptor: d))
        // An over-range composite, so the tone map's slow branch runs on every pixel.
        let fillCommands = try XCTUnwrap(rig.queue.makeCommandBuffer())
        SolidLayer.clear(composite, to: Pixel(3, 0.6, 0.2, 1), commandBuffer: fillCommands)
        fillCommands.commit()
        let previous: MTLLibrary = try CompositorShaders.library(device: rig.device, source: Self.previousOutputSource)
        let vertexLibrary: MTLLibrary = try CompositorShaders.library(device: rig.device, source: CompositorShaders.source)
        let vertex: MTLFunction = try CompositorShaders.function(vertexLibrary, "cmp_fullscreen")
        let newPipeline = try CompositorShaders.pipeline(device: rig.device, vertex: vertex,
                                                         fragment: try CompositorShaders.function(vertexLibrary, "cmp_output"),
                                                         format: .bgra8Unorm_srgb, blendOver: false, label: "FX-002 timing new")
        let oldPipeline = try CompositorShaders.pipeline(device: rig.device, vertex: vertex,
                                                         fragment: try CompositorShaders.function(previous, "cmp_output_previous"),
                                                         format: .bgra8Unorm_srgb, blendOver: false, label: "FX-002 timing previous")
        let target: MTLTexture = try rig.output(.bgra8Unorm_srgb, width: w, height: h)
        var one: Float = 1
        let gain: MTLBuffer = try XCTUnwrap(rig.device.makeBuffer(bytes: &one, length: 4, options: .storageModeShared))
        let counter: MTLBuffer = try XCTUnwrap(rig.device.makeBuffer(length: 4, options: .storageModeShared))
        func milliseconds(_ pipeline: MTLRenderPipelineState) throws -> Double {
            let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = target
            pass.colorAttachments[0].loadAction = .dontCare
            pass.colorAttachments[0].storeAction = .store
            let encoder = try XCTUnwrap(commands.makeRenderCommandEncoder(descriptor: pass))
            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentTexture(composite, index: 0)
            encoder.setFragmentBuffer(gain, offset: 0, index: 0)
            encoder.setFragmentBuffer(counter, offset: 0, index: 1)
            Compositor.bindGrade(.neutral, encoder)   // FX-003: cmp_output's grade block (neutral)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
            commands.commit()
            commands.waitUntilCompleted()
            return (commands.gpuEndTime - commands.gpuStartTime) * 1000
        }
        for _ in 0..<5 { _ = try milliseconds(oldPipeline); _ = try milliseconds(newPipeline) }   // warm-up
        var old: [Double] = []
        var new: [Double] = []
        for _ in 0..<50 {
            old.append(try milliseconds(oldPipeline))
            new.append(try milliseconds(newPipeline))
        }
        let median = { (values: [Double]) -> Double in values.sorted()[values.count / 2] }
        print(String(format: "FX-002 GPU output pass 1920x1080 (Mac, over-range composite): previous median %.3f ms, tone-mapped median %.3f ms (50 frames each)",
                     median(old), median(new)))
        XCTAssertEqual(counter.contents().load(as: UInt32.self), 0, "a finite composite counts nothing")
    }
}

/// Receives a capture on Metal's completion thread (read after the expectation).
private final class CaptureBox: @unchecked Sendable {
    var pixels: CapturedPixels?
}
#endif
