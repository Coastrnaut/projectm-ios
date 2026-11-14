// CMP-009-T07, T08: the luma key through the real Metal compositor (CMP-009-R2 to R7, R11; S1, S2, S5).
// A fixture layer (160 × 96, uploaded as half floats) is drawn into an rgba16Float output. The row's acceptance
// ("Black key test eliminates dark region without affecting bright patch"): with a black key the black and
// near-black columns contribute alpha ≤ 1/255 and every bright-patch pixel equals the unkeyed draw within 1/255.
// Then: the softness ramp is monotonic and matches the CPU reference (`LayerLumaKey`) within 1/255, opacity does not
// move the threshold, invert, key × shape × gradient, the multiply blend mode (black would darken the backdrop unkeyed), a transformed layer (keyed = unkeyed ×
// keep(unkeyed) at every pixel), a change at apply, a key that keys nothing, no extra pass, and an opt-in GPU bench.
// Skipped without a Metal device.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Compositor
import Foundation
import Metal
import XCTest

/// Uploads a fixed picture (premultiplied linear, rounded to half) and copies it into the layer picture each frame.
final class LumaFixtureLayer: LayerSource {
    let layerName = "pattern"
    let fallback = LayerFallback.transparent
    let width: Int
    let height: Int
    /// The texels as the GPU holds them (half-rounded).
    let texels: [Pixel]
    private var staging: MTLTexture?

    init(width: Int, height: Int, _ texel: (Int, Int) -> Pixel) {
        self.width = width
        self.height = height
        var all: [Pixel] = []
        for j in 0..<height {
            for i in 0..<width {
                let p: Pixel = texel(i, j)
                all.append(Pixel(Float(Float16(p.x)), Float(Float16(p.y)), Float(Float16(p.z)), Float(Float16(p.w))))
            }
        }
        texels = all
    }

    func prepare(picture: LayerPictureDescriptor, device: MTLDevice) throws(LayerSourceError) {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: LayerPictureDescriptor.metalPixelFormat, width: width,
                                                         height: height, mipmapped: false)
        d.storageMode = .shared
        guard let t = device.makeTexture(descriptor: d) else { throw .resourceUnavailable("pattern staging") }
        var halves: [UInt16] = []
        halves.reserveCapacity(texels.count * 4)
        for p in texels {
            halves.append(Float16(p.x).bitPattern)
            halves.append(Float16(p.y).bitPattern)
            halves.append(Float16(p.z).bitPattern)
            halves.append(Float16(p.w).bitPattern)
        }
        let w: Int = width
        let h: Int = height
        halves.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            if let base = raw.baseAddress {
                t.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: base, bytesPerRow: w * 8)
            }
        }
        staging = t
    }

    func render(into picture: MTLTexture, commandBuffer: MTLCommandBuffer, frame: LayerFrameContext,
                audio: LayerAudioContext) throws(LayerSourceError) {
        guard let staging, let blit = commandBuffer.makeBlitCommandEncoder() else { throw .resourceUnavailable("pattern blit") }
        blit.copy(from: staging, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: min(width, picture.width), height: min(height, picture.height), depth: 1),
                  to: picture, destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.endEncoding()
    }
}

final class LayerLumaKeyCompositeTests: XCTestCase {
    private static let size = (w: 160, h: 96)
    private static let tolerance: Float = 1.0 / 255
    private static let bright = Pixel(0.8, 0.6, 0.4, 1)
    private static let backdropColor = Pixel(0.1, 0.3, 0.6, 1)

    /// Columns: 0..<48 black, 48..<64 near-black (linear 0.004, luma ≈ 0.05), 64..<112 the bright patch, 112..<160 a
    /// grey ramp whose displayed value runs 0…0.47.
    enum Region { case black, nearBlack, bright, ramp }

    static func region(_ i: Int) -> Region {
        if i < 48 { return .black }
        if i < 64 { return .nearBlack }
        if i < 112 { return .bright }
        return .ramp
    }

    static func blackKeyFixture() -> LumaFixtureLayer {
        LumaFixtureLayer(width: size.w, height: size.h) { (i: Int, _: Int) -> Pixel in
            switch region(i) {
            case .black: return Pixel(0, 0, 0, 1)
            case .nearBlack: return Pixel(0.004, 0.004, 0.004, 1)
            case .bright: return bright
            case .ramp:
                let v: Float = Float(LayerBlend.decode(Double(i - 112) / 100))
                return Pixel(v, v, v, 1)
            }
        }
    }

    /// A grey ramp across the whole width: displayed value i / 159 × 0.5 (luma 0…0.5).
    static func rampFixture() -> LumaFixtureLayer {
        LumaFixtureLayer(width: size.w, height: size.h) { (i: Int, _: Int) -> Pixel in
            let v: Float = Float(LayerBlend.decode(Double(i) / 159 * 0.5))
            return Pixel(v, v, v, 1)
        }
    }

    // MARK: - Rig

    private func render(_ settings: LayerCompositeSettings, layer: LumaFixtureLayer, backdrop: Pixel? = nil) throws
        -> (pixels: [Pixel], compositor: Compositor) {
        let gpu = try GPURig()
        var stack = LayerStack()
        if backdrop != nil { try stack.add(LayerDescriptor(kind: LayerKind("cmp009.backdrop"))) }
        try stack.add(LayerDescriptor(kind: .photo), settings: settings)
        let compositor = try Compositor(device: gpu.device)
        let below = SolidLayer("backdrop", color: backdrop ?? .zero)
        try compositor.apply(stack) { (entry: LayerStackEntry) throws(LayerSourceError) -> any LayerSource in
            entry.descriptor.kind == .photo ? layer : below
        }
        let output = try gpu.output(width: Self.size.w, height: Self.size.h)
        for k in 0..<2 { try gpu.frame(compositor, into: output, time: UInt64(k) * 16_666_667) }
        return (try gpu.read(output), compositor)
    }

    private static func keep(_ key: LayerLumaKey, _ p: Pixel) -> Float {
        Float(key.keep(red: Double(p.x), green: Double(p.y), blue: Double(p.z), alpha: Double(p.w)))
    }

    private static func maxDifference(_ a: Pixel, _ b: Pixel) -> Float {
        let d: Pixel = a - b
        let rg: Float = max(Swift.abs(d.x), Swift.abs(d.y))
        let ba: Float = max(Swift.abs(d.z), Swift.abs(d.w))
        return max(rg, ba)
    }

    // MARK: - The acceptance (CMP-009-S1)

    func testBlackKeyEliminatesTheDarkRegionWithoutAffectingTheBrightPatch() throws {
        let fixture = Self.blackKeyFixture()
        let key = LayerLumaKey(low: 0, high: 0.1, softness: 0)
        let unkeyed = try render(LayerCompositeSettings(), layer: fixture).pixels
        let (keyed, compositor) = try render(LayerCompositeSettings(lumaKey: key), layer: fixture)
        XCTAssertEqual(compositor.maskedDraws, 1, "drawn in the open over pass")
        XCTAssertEqual(compositor.blendDraws, 0, "no extra pass")
        var dark = 0, darkViolations = 0, patch = 0, patchViolations = 0
        var worstDark: Float = 0, worstPatch: Float = 0
        for j in 0..<Self.size.h {
            for i in 0..<Self.size.w {
                let k: Int = j * Self.size.w + i
                switch Self.region(i) {
                case .black, .nearBlack:
                    dark += 1
                    worstDark = max(worstDark, keyed[k].w)
                    if keyed[k].w > Self.tolerance { darkViolations += 1 }
                case .bright:
                    patch += 1
                    let off: Float = Self.maxDifference(keyed[k], unkeyed[k])
                    worstPatch = max(worstPatch, off)
                    if off > Self.tolerance { patchViolations += 1 }
                case .ramp:
                    continue
                }
            }
        }
        XCTAssertEqual(dark, 64 * 96)
        XCTAssertEqual(patch, 48 * 96)
        XCTAssertEqual(darkViolations, 0, "dark region alpha ≤ 1/255 (worst \(worstDark))")
        XCTAssertEqual(patchViolations, 0, "bright patch unchanged within 1/255 (worst \(worstPatch))")
        XCTAssertEqual(unkeyed[48 * Self.size.w + 10].w, 1, accuracy: Self.tolerance, "the unkeyed dark region is opaque")
        print("CMP-009 black key read-back (160 × 96): dark \(dark) px, worst alpha \(worstDark); bright \(patch) px, worst Δ \(worstPatch)")
    }

    func testOverABackdropTheDarkRegionShowsTheBackdrop() throws {
        let fixture = Self.blackKeyFixture()
        let (pixels, _) = try render(LayerCompositeSettings(lumaKey: LayerLumaKey(low: 0, high: 0.1)), layer: fixture,
                                     backdrop: Self.backdropColor)
        let row: Int = Self.size.h / 2
        for i in [0, 30, 50, 63] {
            XCTAssertLessThanOrEqual(Self.maxDifference(pixels[row * Self.size.w + i], Self.backdropColor), Self.tolerance, "column \(i)")
        }
        XCTAssertLessThanOrEqual(Self.maxDifference(pixels[row * Self.size.w + 80], Self.bright), Self.tolerance)
    }

    // MARK: - Softness, opacity, invert (CMP-009-S2, R3)

    func testSoftnessGivesAMonotonicRampThatMatchesTheReference() throws {
        let fixture = Self.rampFixture()
        let key = LayerLumaKey(low: 0, high: 0.1, softness: 0.2)
        let (pixels, _) = try render(LayerCompositeSettings(lumaKey: key), layer: fixture)
        let row: Int = Self.size.h / 2
        var monotonic = 0, reference = 0
        var worst: Float = 0
        var previous: Float = -1
        for i in 0..<Self.size.w {
            let alpha: Float = pixels[row * Self.size.w + i].w
            let expected: Float = Self.keep(key, fixture.texels[row * Self.size.w + i])
            worst = max(worst, abs(alpha - expected))
            if abs(alpha - expected) > Self.tolerance { reference += 1 }
            if alpha < previous - Self.tolerance { monotonic += 1 }
            previous = alpha
        }
        XCTAssertEqual(monotonic, 0, "alpha never falls as luma rises out of the range")
        XCTAssertEqual(reference, 0, "worst \(worst)")
        XCTAssertEqual(pixels[row * Self.size.w].w, 0, accuracy: Self.tolerance)
        XCTAssertEqual(pixels[row * Self.size.w + 159].w, 1, accuracy: Self.tolerance)
        let ramped: Int = (0..<Self.size.w).filter { (i: Int) -> Bool in
            let a: Float = pixels[row * Self.size.w + i].w
            return a > 0.05 && a < 0.95
        }.count
        XCTAssertGreaterThan(ramped, 40, "the softness band spans many columns")
        print("CMP-009 softness ramp read-back: 160 samples, worst Δ vs reference \(worst)")
    }

    func testOpacityDoesNotMoveTheThreshold() throws {
        let fixture = Self.blackKeyFixture()
        let (pixels, _) = try render(LayerCompositeSettings(opacity: 0.5, lumaKey: LayerLumaKey(low: 0, high: 0.1)), layer: fixture)
        let row: Int = Self.size.h / 2
        XCTAssertEqual(pixels[row * Self.size.w + 50].w, 0, accuracy: Self.tolerance, "still keyed at half opacity")
        XCTAssertEqual(pixels[row * Self.size.w + 80].w, 0.5, accuracy: Self.tolerance)
    }

    func testInvertKeepsOnlyTheRange() throws {
        let fixture = Self.blackKeyFixture()
        let (pixels, _) = try render(LayerCompositeSettings(lumaKey: LayerLumaKey(low: 0, high: 0.1, inverted: true)), layer: fixture)
        let row: Int = Self.size.h / 2
        XCTAssertEqual(pixels[row * Self.size.w + 10].w, 1, accuracy: Self.tolerance, "black kept")
        XCTAssertEqual(pixels[row * Self.size.w + 80].w, 0, accuracy: Self.tolerance, "bright removed")
    }

    // MARK: - Composition (CMP-009-R6)

    func testKeyTimesShapeTimesGradientIsTheProduct() throws {
        let fixture = Self.rampFixture()
        let key = LayerLumaKey(low: 0, high: 0.05, softness: 0.3)
        let circle = try LayerMask(shape: .ellipse, transform: LayerMaskTransform(scale: LayerPoint(x: 0.8, y: 0.8)))
        let gradient = try LayerGradientMask(kind: .linear(start: LayerPoint(x: 0.5, y: 0), end: LayerPoint(x: 0.5, y: 1)),
                                             stops: [LayerGradientStop(position: 0, alpha: 1), LayerGradientStop(position: 1, alpha: 0.3)])
        let (pixels, compositor) = try render(LayerCompositeSettings(mask: circle, gradientMask: gradient, lumaKey: key), layer: fixture)
        XCTAssertEqual(compositor.maskedDraws, 1)
        let shape = circle.geometry(width: Self.size.w, height: Self.size.h)
        let g = gradient.geometry(width: Self.size.w, height: Self.size.h)
        var worst: Double = 0
        for j in 0..<Self.size.h {
            for i in 0..<Self.size.w {
                let x: Double = Double(i) + 0.5, y: Double = Double(j) + 0.5
                let k: Int = j * Self.size.w + i
                let expected: Double = shape.coverage(x: x, y: y) * g.alpha(x: x, y: y) * Double(Self.keep(key, fixture.texels[k]))
                worst = max(worst, abs(Double(pixels[k].w) - expected))
            }
        }
        XCTAssertLessThanOrEqual(worst, 0.01)
    }

    func testAMultiplyLayerTakesTheKeyInItsOwnPass() throws {
        let fixture = Self.blackKeyFixture()
        let key = LayerLumaKey(low: 0, high: 0.1)
        let unkeyed = try render(LayerCompositeSettings(blendMode: .multiply), layer: fixture, backdrop: Self.backdropColor).pixels
        let (pixels, compositor) = try render(LayerCompositeSettings(blendMode: .multiply, lumaKey: key), layer: fixture,
                                              backdrop: Self.backdropColor)
        XCTAssertEqual(compositor.blendDraws, 1)
        XCTAssertEqual(compositor.maskedDraws, 0)
        let row: Int = Self.size.h / 2
        XCTAssertLessThanOrEqual(Self.maxDifference(pixels[row * Self.size.w + 20], Self.backdropColor), Self.tolerance, "keyed: backdrop")
        XCTAssertLessThanOrEqual(Self.maxDifference(pixels[row * Self.size.w + 80], unkeyed[row * Self.size.w + 80]), Self.tolerance)
    }

    func testATransformedLayerIsKeyedOnItsResampledColour() throws {
        let fixture = Self.rampFixture()
        let key = LayerLumaKey(low: 0.1, high: 0.2, softness: 0.15)
        let transform = try LayerTransform(translation: LayerPoint(x: 0.1, y: 0), uniformScale: 0.85, rotation: 0.4)
        let unkeyed = try render(LayerCompositeSettings(transform: transform), layer: fixture).pixels
        let keyed = try render(LayerCompositeSettings(transform: transform, lumaKey: key), layer: fixture).pixels
        var worst: Float = 0
        var keyedOut = 0
        for k in unkeyed.indices {
            let expected: Pixel = unkeyed[k] * Self.keep(key, unkeyed[k])
            worst = max(worst, Self.maxDifference(keyed[k], expected))
            if unkeyed[k].w > 0.99 && keyed[k].w < Self.tolerance { keyedOut += 1 }
        }
        XCTAssertLessThanOrEqual(worst, 2 * Self.tolerance, "keyed = unkeyed × keep(unkeyed) at every pixel")
        XCTAssertGreaterThan(keyedOut, 500, "the range is keyed out inside the moved layer")
    }

    // MARK: - Apply and no-op (CMP-009-R7, R11)

    func testAKeyThatKeysNothingDrawsLikeNoKey() throws {
        let fixture = Self.blackKeyFixture()
        let plain = try render(LayerCompositeSettings(), layer: fixture).pixels
        let idle = try render(LayerCompositeSettings(lumaKey: LayerLumaKey(low: 0.98, high: 1)), layer: fixture).pixels
        var worst: Float = 0
        for k in plain.indices { worst = max(worst, Self.maxDifference(plain[k], idle[k])) }
        XCTAssertLessThanOrEqual(worst, Self.tolerance)
    }

    func testAKeyChangeAtApplyShowsNextFrameWithoutRecreatingAnything() throws {
        let gpu = try GPURig()
        let fixture = Self.blackKeyFixture()
        var stack = LayerStack()
        let id = try stack.add(LayerDescriptor(kind: .photo), settings: LayerCompositeSettings())
        let compositor = try Compositor(device: gpu.device)
        try compositor.apply(stack) { (_: LayerStackEntry) throws(LayerSourceError) -> any LayerSource in fixture }
        let output = try gpu.output(width: Self.size.w, height: Self.size.h)
        for k in 0..<2 { try gpu.frame(compositor, into: output, time: UInt64(k) * 16_666_667) }
        let plain = try gpu.read(output)
        XCTAssertEqual(compositor.maskedDraws, 0)
        let pictures = compositor.pictureAllocations
        let preparations = compositor.layerPreparations
        try stack.setSettings(LayerCompositeSettings(lumaKey: LayerLumaKey(low: 0, high: 0.1)), of: id)
        var calls = 0
        try compositor.apply(stack) { (_: LayerStackEntry) throws(LayerSourceError) -> any LayerSource in
            calls += 1
            return SolidLayer("unexpected", color: .zero)
        }
        XCTAssertEqual(calls, 0, "no layer re-created")
        compositor.resetFlashHistory()
        try gpu.frame(compositor, into: output, time: 100_000_000)
        let keyed = try gpu.read(output)
        XCTAssertEqual(keyed[Self.size.h / 2 * Self.size.w + 10].w, 0, accuracy: Self.tolerance, "keyed on the first frame")
        XCTAssertEqual(compositor.maskedDraws, 1)
        XCTAssertEqual(compositor.pictureAllocations, pictures)
        XCTAssertEqual(compositor.layerPreparations, preparations)
        try stack.setSettings(LayerCompositeSettings(), of: id)
        try compositor.apply(stack) { (_: LayerStackEntry) throws(LayerSourceError) -> any LayerSource in SolidLayer("unexpected", color: .zero) }
        compositor.resetFlashHistory()
        try gpu.frame(compositor, into: output, time: 200_000_000)
        XCTAssertEqual(compositor.maskedDraws, 0)
        XCTAssertEqual(try gpu.read(output), plain, "no key again, bit for bit")
    }

    // MARK: - GPU time (CMP-009-S5; opt-in, not asserted)

    func testLumaKeyGPUTimeBench() throws {
        guard ProcessInfo.processInfo.environment["CMP009_BENCH"] == "1" else {
            throw XCTSkip("Set CMP009_BENCH=1 to measure GPU time of a full-screen keyed layer (Mac; not device evidence).")
        }
        let gpu = try GPURig()
        let output = try gpu.output(.bgra8Unorm_srgb, width: 1920, height: 1080)
        let cases: [(String, LayerCompositeSettings)] = [
            ("no key", LayerCompositeSettings()),
            ("black key", LayerCompositeSettings(lumaKey: .blackKey)),
            ("black key × circle × radial", LayerCompositeSettings(mask: try LayerMask(shape: .ellipse, feather: 0.05),
                                                                   gradientMask: .radialDefault, lumaKey: .blackKey)),
        ]
        var lines: [String] = []
        for (name, settings) in cases {
            var stack = LayerStack()
            try stack.add(LayerDescriptor(kind: .photo), settings: settings)
            let compositor = try Compositor(device: gpu.device)
            let layer = SolidLayer("bench", color: Self.bright)
            try compositor.apply(stack) { (_: LayerStackEntry) throws(LayerSourceError) -> any LayerSource in layer }
            var samples: [Double] = []
            for k in 0..<130 {
                let commands = try XCTUnwrap(gpu.queue.makeCommandBuffer())
                _ = compositor.composite(into: output, commandBuffer: commands, presentationTimeNanoseconds: UInt64(k) * 16_666_667,
                                         contentScale: 2, reduceFlashing: false, audio: .empty)
                commands.commit()
                commands.waitUntilCompleted()
                if k >= 10 { samples.append((commands.gpuEndTime - commands.gpuStartTime) * 1000) }
            }
            samples.sort()
            let median: Double = samples[samples.count / 2]
            let p95: Double = samples[samples.count * 95 / 100]
            lines.append("| \(name) | " + String(format: "%.3f | %.3f", median, p95) + " |")
        }
        print("CMP-009 GPU time per frame, 1920 × 1080 (ms): | case | median | p95 |")
        for line in lines { print("CMP-009 bench: " + line) }
    }
}
#endif
