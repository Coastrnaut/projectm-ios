// CMP-010-T07, T08: the colour key through the real Metal compositor (CMP-010-R2 to R7, R11; S1, S2, S5).
// A fixture layer (160 × 96, uploaded as half floats; `LumaFixtureLayer` from the CMP-009 tests) is drawn into an
// rgba16Float output. The row's acceptance ("Green patch keys out and unrelated colors remain opaque"): with a green
// key every green-patch pixel has alpha ≤ 1/255, and every red, blue, white, skin-tone and dark-green pixel equals the
// unkeyed draw (colour and alpha) within 1/255. Then: the feather ramp is monotonic and matches the CPU reference
// (`LayerColorKey`) within 1/255, opacity does not move the threshold, colour key × luma key × shape × gradient, the
// screen blend mode, a transformed layer, a change at apply, a key that keys nothing, no extra pass, and an opt-in
// GPU bench. Skipped without a Metal device.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Compositor
import Foundation
import Metal
import XCTest

final class LayerColorKeyCompositeTests: XCTestCase {
    private static let size = (w: 160, h: 96)
    private static let tolerance: Float = 1.0 / 255
    private static let backdropColor = Pixel(0.6, 0.1, 0.3, 1)

    /// Columns of the acceptance fixture (displayed sRGB colours): 0..<32 green (0, 1, 0), then 16 columns each of red,
    /// blue, white, skin (0.87, 0.67, 0.55) and dark green (0, 0.3, 0), then 112..<160 a ramp from green to mid-grey.
    enum Region: CaseIterable { case green, red, blue, white, skin, darkGreen, ramp }

    static func region(_ i: Int) -> Region {
        if i < 32 { return .green }
        if i >= 112 { return .ramp }
        let all: [Region] = [.red, .blue, .white, .skin, .darkGreen]
        return all[(i - 32) / 16]
    }

    /// A displayed colour as the compositor holds it (premultiplied linear, opaque).
    static func linear(_ r: Double, _ g: Double, _ b: Double) -> Pixel {
        Pixel(Float(LayerBlend.decode(r)), Float(LayerBlend.decode(g)), Float(LayerBlend.decode(b)), 1)
    }

    /// From green (t 0) to mid-grey (t 1) in displayed values: the chroma distance to green is t × 0.596.
    static func rampColour(_ t: Double) -> Pixel { linear(0.5 * t, 1 - 0.5 * t, 0.5 * t) }

    static func greenFixture() -> LumaFixtureLayer {
        LumaFixtureLayer(width: size.w, height: size.h) { (i: Int, _: Int) -> Pixel in
            switch region(i) {
            case .green: return linear(0, 1, 0)
            case .red: return linear(1, 0, 0)
            case .blue: return linear(0, 0, 1)
            case .white: return linear(1, 1, 1)
            case .skin: return linear(0.87, 0.67, 0.55)
            case .darkGreen: return linear(0, 0.3, 0)
            case .ramp: return rampColour(Double(i - 112) / 47)
            }
        }
    }

    /// The green-to-grey ramp across the whole width.
    static func rampFixture() -> LumaFixtureLayer {
        LumaFixtureLayer(width: size.w, height: size.h) { (i: Int, _: Int) -> Pixel in rampColour(Double(i) / 159) }
    }

    // MARK: - Rig

    private func render(_ settings: LayerCompositeSettings, layer: LumaFixtureLayer, backdrop: Pixel? = nil) throws
        -> (pixels: [Pixel], compositor: Compositor) {
        let gpu = try GPURig()
        var stack = LayerStack()
        if backdrop != nil { try stack.add(LayerDescriptor(kind: LayerKind("cmp010.backdrop"))) }
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

    private static func keep(_ key: LayerColorKey, _ p: Pixel) -> Float {
        Float(key.keep(red: Double(p.x), green: Double(p.y), blue: Double(p.z), alpha: Double(p.w)))
    }

    private static func maxDifference(_ a: Pixel, _ b: Pixel) -> Float {
        let d: Pixel = a - b
        let rg: Float = max(Swift.abs(d.x), Swift.abs(d.y))
        let ba: Float = max(Swift.abs(d.z), Swift.abs(d.w))
        return max(rg, ba)
    }

    // MARK: - The acceptance (CMP-010-S1)

    func testGreenPatchKeysOutAndUnrelatedColoursRemainOpaque() throws {
        let fixture = Self.greenFixture()
        let unkeyed = try render(LayerCompositeSettings(), layer: fixture).pixels
        let (keyed, compositor) = try render(LayerCompositeSettings(colorKey: .greenKey), layer: fixture)
        XCTAssertEqual(compositor.maskedDraws, 1, "drawn in the open over pass")
        XCTAssertEqual(compositor.blendDraws, 0, "no extra pass")
        var counts: [Region: Int] = [:]
        var violations: [Region: Int] = [:]
        var worstGreen: Float = 0, worstKept: Float = 0
        for j in 0..<Self.size.h {
            for i in 0..<Self.size.w {
                let k: Int = j * Self.size.w + i
                let region: Region = Self.region(i)
                if region == .ramp { continue }
                counts[region, default: 0] += 1
                if region == .green {
                    worstGreen = max(worstGreen, keyed[k].w)
                    if keyed[k].w > Self.tolerance { violations[region, default: 0] += 1 }
                } else {
                    let off: Float = Self.maxDifference(keyed[k], unkeyed[k])
                    worstKept = max(worstKept, off)
                    if off > Self.tolerance || keyed[k].w < 1 - Self.tolerance { violations[region, default: 0] += 1 }
                }
            }
        }
        XCTAssertEqual(counts[.green], 32 * 96)
        for region in [Region.red, .blue, .white, .skin, .darkGreen] { XCTAssertEqual(counts[region], 16 * 96, "\(region)") }
        XCTAssertEqual(violations, [:], "green alpha ≤ 1/255 (worst \(worstGreen)); others unchanged and opaque (worst Δ \(worstKept))")
        XCTAssertEqual(unkeyed[48 * Self.size.w + 10].w, 1, accuracy: Self.tolerance, "the unkeyed green patch is opaque")
        print("CMP-010 green key read-back (160 × 96): green \(counts[.green] ?? 0) px, worst alpha \(worstGreen); "
              + "unrelated \(5 * 16 * 96) px, worst Δ \(worstKept)")
    }

    func testOverABackdropTheGreenPatchShowsTheBackdrop() throws {
        let fixture = Self.greenFixture()
        let (pixels, _) = try render(LayerCompositeSettings(colorKey: .greenKey), layer: fixture, backdrop: Self.backdropColor)
        let row: Int = Self.size.h / 2
        for i in [0, 15, 31] {
            XCTAssertLessThanOrEqual(Self.maxDifference(pixels[row * Self.size.w + i], Self.backdropColor), Self.tolerance, "column \(i)")
        }
        XCTAssertLessThanOrEqual(Self.maxDifference(pixels[row * Self.size.w + 40], Self.linear(1, 0, 0)), Self.tolerance, "red")
    }

    // MARK: - Feather and opacity (CMP-010-S2, R3)

    func testFeatherGivesAMonotonicRampThatMatchesTheReference() throws {
        let fixture = Self.rampFixture()
        let key = LayerColorKey(red: 0, green: 1, blue: 0, tolerance: 0.15, feather: 0.25)
        let (pixels, _) = try render(LayerCompositeSettings(colorKey: key), layer: fixture)
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
        XCTAssertEqual(monotonic, 0, "alpha never falls as the colour moves away from the key")
        XCTAssertEqual(reference, 0, "worst \(worst)")
        XCTAssertEqual(pixels[row * Self.size.w].w, 0, accuracy: Self.tolerance)
        XCTAssertEqual(pixels[row * Self.size.w + 159].w, 1, accuracy: Self.tolerance)
        let ramped: Int = (0..<Self.size.w).filter { (i: Int) -> Bool in
            let a: Float = pixels[row * Self.size.w + i].w
            return a > 0.05 && a < 0.95
        }.count
        XCTAssertGreaterThan(ramped, 40, "the feather band spans many columns")
        print("CMP-010 feather ramp read-back: 160 samples, worst Δ vs reference \(worst)")
    }

    func testOpacityDoesNotMoveTheThreshold() throws {
        let fixture = Self.greenFixture()
        let (pixels, _) = try render(LayerCompositeSettings(opacity: 0.5, colorKey: .greenKey), layer: fixture)
        let row: Int = Self.size.h / 2
        XCTAssertEqual(pixels[row * Self.size.w + 10].w, 0, accuracy: Self.tolerance, "still keyed at half opacity")
        XCTAssertEqual(pixels[row * Self.size.w + 40].w, 0.5, accuracy: Self.tolerance)
    }

    // MARK: - Composition (CMP-010-R6)

    func testColourKeyTimesLumaKeyTimesShapeTimesGradientIsTheProduct() throws {
        let fixture = Self.rampFixture()
        let key = LayerColorKey(red: 0, green: 1, blue: 0, tolerance: 0.1, feather: 0.3)
        let luma = LayerLumaKey(low: 0.95, high: 1, softness: 0.3)
        let circle = try LayerMask(shape: .ellipse, transform: LayerMaskTransform(scale: LayerPoint(x: 0.8, y: 0.8)))
        let gradient = try LayerGradientMask(kind: .linear(start: LayerPoint(x: 0.5, y: 0), end: LayerPoint(x: 0.5, y: 1)),
                                             stops: [LayerGradientStop(position: 0, alpha: 1), LayerGradientStop(position: 1, alpha: 0.3)])
        let settings = LayerCompositeSettings(mask: circle, gradientMask: gradient, lumaKey: luma, colorKey: key)
        let (pixels, compositor) = try render(settings, layer: fixture)
        XCTAssertEqual(compositor.maskedDraws, 1)
        let shape = circle.geometry(width: Self.size.w, height: Self.size.h)
        let g = gradient.geometry(width: Self.size.w, height: Self.size.h)
        var worst: Double = 0
        var bothActive = 0
        for j in 0..<Self.size.h {
            for i in 0..<Self.size.w {
                let x: Double = Double(i) + 0.5, y: Double = Double(j) + 0.5
                let k: Int = j * Self.size.w + i
                let p: Pixel = fixture.texels[k]
                let lumaKeep: Double = luma.keep(red: Double(p.x), green: Double(p.y), blue: Double(p.z), alpha: Double(p.w))
                let colourKeep: Double = Double(Self.keep(key, p))
                if lumaKeep < 0.99 && colourKeep < 0.99 && lumaKeep > 0.01 && colourKeep > 0.01 { bothActive += 1 }
                let coverage: Double = shape.coverage(x: x, y: y) * g.alpha(x: x, y: y)
                let expected: Double = coverage * lumaKeep * colourKeep
                worst = max(worst, abs(Double(pixels[k].w) - expected))
            }
        }
        XCTAssertLessThanOrEqual(worst, 0.01)
        XCTAssertGreaterThan(bothActive, 100, "both keys partly active on the same pixels")
    }

    func testAScreenLayerTakesTheKeyInItsOwnPass() throws {
        let fixture = Self.greenFixture()
        let unkeyed = try render(LayerCompositeSettings(blendMode: .screen), layer: fixture, backdrop: Self.backdropColor).pixels
        let (pixels, compositor) = try render(LayerCompositeSettings(blendMode: .screen, colorKey: .greenKey), layer: fixture,
                                              backdrop: Self.backdropColor)
        XCTAssertEqual(compositor.blendDraws, 1)
        XCTAssertEqual(compositor.maskedDraws, 0)
        let row: Int = Self.size.h / 2
        XCTAssertLessThanOrEqual(Self.maxDifference(pixels[row * Self.size.w + 20], Self.backdropColor), Self.tolerance, "keyed: backdrop")
        XCTAssertGreaterThan(Self.maxDifference(unkeyed[row * Self.size.w + 20], Self.backdropColor), 0.1, "unkeyed green brightens it")
        XCTAssertLessThanOrEqual(Self.maxDifference(pixels[row * Self.size.w + 56], unkeyed[row * Self.size.w + 56]), Self.tolerance, "blue")
    }

    func testATransformedLayerIsKeyedOnItsResampledColour() throws {
        let fixture = Self.rampFixture()
        let key = LayerColorKey(red: 0, green: 1, blue: 0, tolerance: 0.2, feather: 0.15)
        let transform = try LayerTransform(translation: LayerPoint(x: 0.1, y: 0), uniformScale: 0.85, rotation: 0.4)
        let unkeyed = try render(LayerCompositeSettings(transform: transform), layer: fixture).pixels
        let keyed = try render(LayerCompositeSettings(transform: transform, colorKey: key), layer: fixture).pixels
        var worst: Float = 0
        var keyedOut = 0
        for k in unkeyed.indices {
            let expected: Pixel = unkeyed[k] * Self.keep(key, unkeyed[k])
            worst = max(worst, Self.maxDifference(keyed[k], expected))
            if unkeyed[k].w > 0.99 && keyed[k].w < Self.tolerance { keyedOut += 1 }
        }
        XCTAssertLessThanOrEqual(worst, 2 * Self.tolerance, "keyed = unkeyed × keep(unkeyed) at every pixel")
        XCTAssertGreaterThan(keyedOut, 500, "the key colour is keyed out inside the moved layer")
    }

    // MARK: - Apply and no-op (CMP-010-R7, R11)

    func testAKeyThatKeysNothingDrawsLikeNoKey() throws {
        let fixture = Self.greenFixture()
        let plain = try render(LayerCompositeSettings(), layer: fixture).pixels
        let magenta = LayerColorKey(red: 1, green: 0, blue: 1, tolerance: 0.05, feather: 0)
        let idle = try render(LayerCompositeSettings(colorKey: magenta), layer: fixture).pixels
        var worst: Float = 0
        for k in plain.indices { worst = max(worst, Self.maxDifference(plain[k], idle[k])) }
        XCTAssertLessThanOrEqual(worst, Self.tolerance)
    }

    func testAKeyChangeAtApplyShowsNextFrameWithoutRecreatingAnything() throws {
        let gpu = try GPURig()
        let fixture = Self.greenFixture()
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
        try stack.setSettings(LayerCompositeSettings(colorKey: .greenKey), of: id)
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
        // A colour change alone reaches the next frame too (the cached block is rebuilt).
        try stack.setSettings(LayerCompositeSettings(colorKey: LayerColorKey(red: 1, green: 0, blue: 0, tolerance: 0.2, feather: 0)), of: id)
        try compositor.apply(stack) { (_: LayerStackEntry) throws(LayerSourceError) -> any LayerSource in SolidLayer("unexpected", color: .zero) }
        compositor.resetFlashHistory()
        try gpu.frame(compositor, into: output, time: 150_000_000)
        let red = try gpu.read(output)
        XCTAssertEqual(red[Self.size.h / 2 * Self.size.w + 10].w, 1, accuracy: Self.tolerance, "green kept under a red key")
        XCTAssertEqual(red[Self.size.h / 2 * Self.size.w + 40].w, 0, accuracy: Self.tolerance, "red keyed")
        try stack.setSettings(LayerCompositeSettings(), of: id)
        try compositor.apply(stack) { (_: LayerStackEntry) throws(LayerSourceError) -> any LayerSource in SolidLayer("unexpected", color: .zero) }
        compositor.resetFlashHistory()
        try gpu.frame(compositor, into: output, time: 200_000_000)
        XCTAssertEqual(compositor.maskedDraws, 0)
        XCTAssertEqual(try gpu.read(output), plain, "no key again, bit for bit")
    }

    // MARK: - GPU time (CMP-010-S5; opt-in, not asserted)

    func testColorKeyGPUTimeBench() throws {
        guard ProcessInfo.processInfo.environment["CMP010_BENCH"] == "1" else {
            throw XCTSkip("Set CMP010_BENCH=1 to measure GPU time of a full-screen colour-keyed layer (Mac; not device evidence).")
        }
        let gpu = try GPURig()
        let output = try gpu.output(.bgra8Unorm_srgb, width: 1920, height: 1080)
        let cases: [(String, LayerCompositeSettings)] = [
            ("no key", LayerCompositeSettings()),
            ("green key", LayerCompositeSettings(colorKey: .greenKey)),
            ("green key × black key", LayerCompositeSettings(lumaKey: .blackKey, colorKey: .greenKey)),
        ]
        var lines: [String] = []
        for (name, settings) in cases {
            var stack = LayerStack()
            try stack.add(LayerDescriptor(kind: .photo), settings: settings)
            let compositor = try Compositor(device: gpu.device)
            let layer = SolidLayer("bench", color: Self.linear(0.87, 0.67, 0.55))
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
        print("CMP-010 GPU time per frame, 1920 × 1080 (ms): | case | median | p95 |")
        for line in lines { print("CMP-010 bench: " + line) }
    }
}
#endif
