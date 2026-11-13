// CMP-003-T05 (US1, the roadmap acceptance "Zero is transparent and one matches unmodified layer
// output"; CMP-003-S1, S2), T07 (US2, a fade on the GPU) and T08 (US3: reuse, no allocation, flash
// safety; CMP-003-S4, S5). GPU tests at 64 × 64 through the real Metal compositor; skipped without a
// Metal device.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Compositor
import FlashSafety
import Metal
import XCTest

/// Clears its picture to a colour and counts its renders.
private final class CountingLayer: LayerSource {
    let layerName: String
    let fallback = LayerFallback.transparent
    var color: Pixel
    private(set) var renders = 0

    init(_ name: String, color: Pixel) {
        layerName = name
        self.color = color
    }

    func prepare(picture: LayerPictureDescriptor, device: MTLDevice) throws(LayerSourceError) {}

    func render(into picture: MTLTexture, commandBuffer: MTLCommandBuffer, frame: LayerFrameContext,
                audio: LayerAudioContext) throws(LayerSourceError) {
        renders += 1
        SolidLayer.clear(picture, to: color, commandBuffer: commandBuffer)
    }
}

/// Makes a `CountingLayer` per new entry from its parameters (r, g, b, a) and keeps them.
private final class CountingFactory {
    static let kind = LayerKind("test.counting")
    private(set) var calls = 0
    private(set) var made: [LayerInstanceID: CountingLayer] = [:]

    static func solid(_ p: Pixel) -> LayerDescriptor {
        LayerDescriptor(kind: kind, parameters: ["r": Double(p.x), "g": Double(p.y), "b": Double(p.z), "a": Double(p.w)])
    }

    func make(_ entry: LayerStackEntry) -> any LayerSource {
        calls += 1
        let p = entry.descriptor.parameters
        let layer = CountingLayer("counting \(entry.id)",
                                  color: Pixel(Float(p["r"] ?? 0), Float(p["g"] ?? 0), Float(p["b"] ?? 0), Float(p["a"] ?? 0)))
        made[entry.id] = layer
        return layer
    }
}

final class LayerOpacityCompositeTests: XCTestCase {
    private static let frameNanoseconds: UInt64 = 16_666_667
    private let red = Pixel(1, 0, 0, 1)
    private let blue = Pixel(0, 0, 1, 1)
    private let white = Pixel(1, 1, 1, 1)
    private let black = Pixel(0, 0, 0, 1)
    /// An arbitrary premultiplied colour whose half-float values are not round numbers.
    private let odd = Pixel(0.3, 0.55, 0.1, 0.7)

    private func apply(_ stack: LayerStack, _ compositor: Compositor, _ factory: CountingFactory,
                       transition: LayerOpacityTransition = .immediate) throws {
        try compositor.apply(stack, opacityTransition: transition) { (entry: LayerStackEntry) throws(LayerSourceError) -> any LayerSource in
            factory.make(entry)
        }
    }

    private func settings(_ opacity: Double) -> LayerCompositeSettings { LayerCompositeSettings(opacity: opacity) }

    /// The output's raw bytes (rgba16Float): equality is bit-for-bit.
    private func raw(_ rig: GPURig, _ texture: MTLTexture) throws -> [UInt16] {
        let rowBytes = texture.width * 8
        let buffer = try XCTUnwrap(rig.device.makeBuffer(length: rowBytes * texture.height, options: .storageModeShared))
        let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
        let blit = try XCTUnwrap(commands.makeBlitCommandEncoder())
        blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: texture.width, height: texture.height, depth: 1), to: buffer,
                  destinationOffset: 0, destinationBytesPerRow: rowBytes, destinationBytesPerImage: rowBytes * texture.height)
        blit.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        let count = texture.width * texture.height * 4
        let halves = buffer.contents().bindMemory(to: UInt16.self, capacity: count)
        return Array(UnsafeBufferPointer(start: halves, count: count))
    }

    /// One frame of `stack` on a fresh compositor, as raw bytes.
    private func render(_ stack: LayerStack, _ rig: GPURig) throws -> [UInt16] {
        let compositor = try Compositor(device: rig.device)
        try apply(stack, compositor, CountingFactory())
        let output = try rig.output()
        try rig.frame(compositor, into: output, time: 1_000_000_000)
        return try raw(rig, output)
    }

    // MARK: - US1: the acceptance

    func testOpacityZeroIsExactlyTheStackWithoutTheLayer() throws {
        let rig = try GPURig()
        for bottom in [blue, odd] {
            var without = LayerStack()
            try without.add(CountingFactory.solid(bottom))
            var with = without
            try with.add(CountingFactory.solid(red), settings: settings(0))
            XCTAssertEqual(try render(with, rig), try render(without, rig), "opacity 0 contributes nothing (bottom \(bottom))")
        }
        var alone = LayerStack()
        try alone.add(CountingFactory.solid(odd), settings: settings(0))
        XCTAssertTrue(try render(alone, rig).allSatisfy { $0 == 0 }, "a single layer at opacity 0 is transparent")
    }

    func testOpacityOneMatchesTheUnmodifiedOutput() throws {
        let rig = try GPURig()
        // The CMP-001/CMP-002 path: layers with default settings given to the compositor directly.
        let unmodified = try Compositor(device: rig.device, layers: [SolidLayer("bottom", color: blue),
                                                                     SolidLayer("top", color: Pixel(0.5, 0, 0, 0.5))])
        let reference = try rig.output()
        try rig.frame(unmodified, into: reference, time: 1_000_000_000)
        var stack = LayerStack()
        try stack.add(CountingFactory.solid(blue), settings: settings(1))
        try stack.add(CountingFactory.solid(Pixel(0.5, 0, 0, 0.5)), settings: settings(1))
        XCTAssertEqual(try render(stack, rig), try raw(rig, reference), "opacity 1 is bit-identical")
        assertAll(try rig.read(reference), equal: Pixel(0.5, 0, 0.5, 1), "half red over blue (CMP-001-T07's value)")

        // One layer alone at opacity 1 is its own picture, bit for bit (over transparent, gain 1).
        let lone = try Compositor(device: rig.device, layers: [SolidLayer("odd", color: odd)])
        let loneOutput = try rig.output()
        try rig.frame(lone, into: loneOutput, time: 1_000_000_000)
        var oddStack = LayerStack()
        try oddStack.add(CountingFactory.solid(odd), settings: settings(1))
        XCTAssertEqual(try render(oddStack, rig), try raw(rig, loneOutput))
        assertAll(try rig.read(loneOutput), equal: odd, tolerance: 1e-3, "the layer's own colour")
    }

    func testHalfOpacityRedOverBlueIsThePremultipliedMix() throws {
        let rig = try GPURig()
        var stack = LayerStack()
        try stack.add(CountingFactory.solid(blue))
        try stack.add(CountingFactory.solid(red), settings: settings(0.5))
        let compositor = try Compositor(device: rig.device)
        try apply(stack, compositor, CountingFactory())
        let output = try rig.output()
        try rig.frame(compositor, into: output, time: 1_000_000_000)
        assertAll(try rig.read(output), equal: Pixel(0.5, 0, 0.5, 1), "0.5·red + (1 − 0.5)·blue")
    }

    func testLayersGivenDirectlyUseTheirOpacity() throws {
        let rig = try GPURig()
        let top = SolidLayer("red", color: red)
        top.settings = settings(0.25)
        let compositor = try Compositor(device: rig.device, layers: [SolidLayer("blue", color: blue), top])
        let output = try rig.output()
        try rig.frame(compositor, into: output, time: 1)
        assertAll(try rig.read(output), equal: Pixel(0.25, 0, 0.75, 1), "0.25·red + 0.75·blue")
        XCTAssertEqual(compositor.shownOpacity(ofLayer: 1), 0.25)
    }

    // MARK: - US2: a fade on the GPU

    func testFadeShowsTheIntermediateMixAndEndsExactly() throws {
        let rig = try GPURig()
        let factory = CountingFactory()
        let compositor = try Compositor(device: rig.device)
        let output = try rig.output()
        var stack = LayerStack()
        try stack.add(CountingFactory.solid(blue))
        let redID = try stack.add(CountingFactory.solid(red), settings: settings(0))
        try apply(stack, compositor, factory)
        let t0: UInt64 = 1_000_000_000
        try rig.frame(compositor, into: output, time: t0)
        assertAll(try rig.read(output), equal: blue, tolerance: 0, "starts at opacity 0")

        try stack.setSettings(settings(1), of: redID)
        try apply(stack, compositor, factory, transition: try LayerOpacityTransition(duration: 0.5, curve: .linear))
        for k in 1...32 {
            try rig.frame(compositor, into: output, time: t0 + UInt64(k) * Self.frameNanoseconds)
            if k == 15 {
                XCTAssertEqual(compositor.shownOpacity(ofLayer: 1), 0.5, accuracy: 1e-6)
                assertAll(try rig.read(output), equal: Pixel(0.5, 0, 0.5, 1), "half way after 0.25 s")
            }
            if k >= 30 {
                XCTAssertEqual(compositor.shownOpacity(ofLayer: 1), 1, "exact end once 0.5 s has been summed")
                assertAll(try rig.read(output), equal: red, tolerance: 0, "exactly red at the end (frame \(k))")
            }
        }
        XCTAssertEqual(factory.calls, 2, "a fade creates no layer")
    }

    // MARK: - US3: cheap and safe

    func testOpacityEditsReuseLayersAndAllocateNothing() throws {
        let rig = try GPURig()
        let factory = CountingFactory()
        let compositor = try Compositor(device: rig.device)
        let output = try rig.output()
        var stack = LayerStack()
        try stack.add(CountingFactory.solid(blue))
        let redID = try stack.add(CountingFactory.solid(red))
        try apply(stack, compositor, factory)
        try rig.frame(compositor, into: output, time: 0)
        let pictures = compositor.pictureAllocations
        XCTAssertEqual(compositor.layerPreparations, 2)

        // Opacity 0: not composited, still rendering, still prepared.
        try stack.setSettings(settings(0), of: redID)
        try apply(stack, compositor, factory)
        let rendersBefore = try XCTUnwrap(factory.made[redID]).renders
        for i in 1...5 { try rig.frame(compositor, into: output, time: UInt64(i) * Self.frameNanoseconds) }
        assertAll(try rig.read(output), equal: blue, tolerance: 0, "hidden at opacity 0")
        XCTAssertEqual(try XCTUnwrap(factory.made[redID]).renders, rendersBefore + 5, "it keeps rendering")
        XCTAssertEqual(compositor.outcome(ofLayer: 1), .rendered)

        // Back to 1 at once: shown at the next frame.
        try stack.setSettings(settings(1), of: redID)
        try apply(stack, compositor, factory)
        try rig.frame(compositor, into: output, time: 6 * Self.frameNanoseconds)
        assertAll(try rig.read(output), equal: red, tolerance: 0, "reappears at once")

        // A 1 s fade over 60 frames; an equal stack mid-fade does not restart it.
        try stack.setSettings(settings(0.2), of: redID)
        try apply(stack, compositor, factory, transition: try LayerOpacityTransition(duration: 1, curve: .easeInOut))
        var previous = compositor.shownOpacity(ofLayer: 1)
        for i in 7..<67 {
            if i == 30 { try apply(stack, compositor, factory, transition: .immediate) }
            try rig.frame(compositor, into: output, time: UInt64(i) * Self.frameNanoseconds)
            let shown = compositor.shownOpacity(ofLayer: 1)
            XCTAssertLessThanOrEqual(shown, previous, "monotonic, not restarted (frame \(i))")
            previous = shown
        }
        XCTAssertEqual(previous, 0.2, "the fade ended exactly")
        XCTAssertEqual(factory.calls, 2, "opacity edits create no layer")
        XCTAssertEqual(compositor.layerPreparations, 2, "opacity edits prepare nothing")
        XCTAssertEqual(compositor.pictureAllocations, pictures, "no picture created during edits and fades")
    }

    func testOpacityEditKeepsTheFlashHistory() throws {
        let rig = try GPURig()
        let factory = CountingFactory()
        let compositor = try Compositor(device: rig.device)
        let output = try rig.output()
        var stack = LayerStack()
        try stack.add(CountingFactory.solid(black))
        let whiteID = try stack.add(CountingFactory.solid(white), settings: settings(0))
        try apply(stack, compositor, factory)
        for i in 0..<10 { try rig.frame(compositor, into: output, time: UInt64(i) * Self.frameNanoseconds, reduceFlashing: true) }
        XCTAssertEqual(compositor.lastFlashGain, 1)
        try stack.setSettings(settings(1), of: whiteID)
        try apply(stack, compositor, factory)
        try rig.frame(compositor, into: output, time: 10 * Self.frameNanoseconds, reduceFlashing: true)
        XCTAssertLessThan(compositor.lastFlashGain, 0.1, "a jump to white is held (rise 0.25/s): the history was kept")
    }

    /// The 17 area luminances of a 64 × 64 linear picture (16 tiles, then their mean).
    private func areaLuminances(_ pixels: [Pixel], side: Int = 64) -> [Double] {
        var out: [Double] = []
        let tile = side / 4
        for ty in 0..<4 {
            for tx in 0..<4 {
                var y = 0.0
                for py in (ty * tile)..<((ty + 1) * tile) {
                    for px in (tx * tile)..<((tx + 1) * tile) {
                        let p = pixels[py * side + px]
                        y += FlashColor.relativeLuminance(red: Double(p.x), green: Double(p.y), blue: Double(p.z))
                    }
                }
                out.append(y / Double(tile * tile))
            }
        }
        out.append(out.reduce(0, +) / 16)
        return out
    }

    func testThirtyHertzOpacityStrobeIsLimitedWithReduceFlashing() throws {
        let rig = try GPURig()
        let factory = CountingFactory()
        let compositor = try Compositor(device: rig.device)
        let output = try rig.output()
        var stack = LayerStack()
        try stack.add(CountingFactory.solid(black))
        let whiteID = try stack.add(CountingFactory.solid(white))
        let configuration = FlashEnvelopeConfiguration.forReduceFlashing(true)
        var series = [[Double]](repeating: [], count: FlashZones.count)
        var frameTimes: [Double] = []
        for i in 0..<120 {
            // 60 fps, opacity flipped every 2 frames: a 30 Hz 0 ↔ 1 strobe through opacity alone.
            try stack.setSettings(settings((i / 2) % 2 == 0 ? 1 : 0), of: whiteID)
            try apply(stack, compositor, factory)
            try rig.frame(compositor, into: output, time: 1_000_000_000 + UInt64(i) * Self.frameNanoseconds, reduceFlashing: true)
            let shown = areaLuminances(try rig.read(output))
            frameTimes.append(i == 0 ? 0 : Double(Self.frameNanoseconds) / 1e9)
            for z in 0..<FlashZones.count { series[z].append(shown[z]) }
        }
        for z in 0..<FlashZones.count {
            let report = FlashAnalysis.analyze(series[z], frameTimes: frameTimes, threshold: configuration.luminanceThreshold)
            XCTAssertLessThanOrEqual(report.maxTransitionsPerWindow, 4, "area \(z): transitions per 1 s window")
            XCTAssertLessThanOrEqual(report.maxRise, 0.25 / 60 + 1e-3, "area \(z): rise per frame")
        }
        XCTAssertEqual(factory.calls, 2, "the strobe reuses its layers")
    }
}
#endif
