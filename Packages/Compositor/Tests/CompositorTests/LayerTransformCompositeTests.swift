// CMP-005-T07 (US2: moved, scaled and rotated layers on screen; identity unchanged; CMP-005-S3, S4)
// and T08 (US3: transform edits reuse layers and allocate nothing; CMP-005-S5). GPU tests at 64 × 64
// through the real Metal compositor; skipped without a Metal device.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Compositor
import Metal
import XCTest

/// Red top-left quarter, green top-right quarter, transparent bottom half: an asymmetric pattern
/// (a quarter turn, its opposite and a mirror all land differently). Its pixels are a staging
/// buffer created in `prepare` and copied into the picture each frame.
private final class QuadrantLayer: LayerSource {
    let layerName = "quadrants"
    let fallback = LayerFallback.transparent
    private var staging: MTLBuffer?
    private var size = (width: 0, height: 0)

    func prepare(picture: LayerPictureDescriptor, device: MTLDevice) throws(LayerSourceError) {
        let w = picture.width, h = picture.height
        guard let buffer = device.makeBuffer(length: w * h * 8, options: .storageModeShared) else {
            throw .resourceUnavailable("staging")
        }
        let one: UInt16 = 0x3C00   // 1.0 as a half float
        let halves = buffer.contents().bindMemory(to: UInt16.self, capacity: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let i = (y * w + x) * 4
                let top = y < h / 2, left = x < w / 2
                halves[i] = top && left ? one : 0
                halves[i + 1] = top && !left ? one : 0
                halves[i + 2] = 0
                halves[i + 3] = top ? one : 0
            }
        }
        staging = buffer
        size = (w, h)
    }

    func render(into picture: MTLTexture, commandBuffer: MTLCommandBuffer, frame: LayerFrameContext,
                audio: LayerAudioContext) throws(LayerSourceError) {
        guard let staging, let blit = commandBuffer.makeBlitCommandEncoder() else { throw .notReady }
        blit.copy(from: staging, sourceOffset: 0, sourceBytesPerRow: size.width * 8, sourceBytesPerImage: size.width * size.height * 8,
                  sourceSize: MTLSize(width: size.width, height: size.height, depth: 1), to: picture, destinationSlice: 0,
                  destinationLevel: 0, destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.endEncoding()
    }
}

/// Makes a `SolidLayer` per new entry from its parameters (r, g, b, a), or a `QuadrantLayer`.
private final class TransformFactory {
    static let solidKind = LayerKind("test.transform.solid")
    static let quadrantKind = LayerKind("test.transform.quadrants")
    private(set) var calls = 0

    static func solid(_ p: Pixel) -> LayerDescriptor {
        LayerDescriptor(kind: solidKind, parameters: ["r": Double(p.x), "g": Double(p.y), "b": Double(p.z), "a": Double(p.w)])
    }

    func make(_ entry: LayerStackEntry) -> any LayerSource {
        calls += 1
        if entry.descriptor.kind == Self.quadrantKind { return QuadrantLayer() }
        let p = entry.descriptor.parameters
        return SolidLayer("solid \(entry.id)", color: Pixel(Float(p["r"] ?? 0), Float(p["g"] ?? 0), Float(p["b"] ?? 0), Float(p["a"] ?? 0)))
    }
}

final class LayerTransformCompositeTests: XCTestCase {
    private static let frameNanoseconds: UInt64 = 16_666_667
    private let red = Pixel(1, 0, 0, 1)
    private let green = Pixel(0, 1, 0, 1)
    private let blue = Pixel(0, 0, 1, 1)
    private let white = Pixel(1, 1, 1, 1)
    private let black = Pixel(0, 0, 0, 1)
    private let odd = Pixel(0.3, 0.55, 0.1, 0.7)

    private func apply(_ stack: LayerStack, _ compositor: Compositor, _ factory: TransformFactory) throws {
        try compositor.apply(stack) { (entry: LayerStackEntry) throws(LayerSourceError) -> any LayerSource in
            factory.make(entry)
        }
    }

    private func p(_ x: Double, _ y: Double) -> LayerPoint { LayerPoint(x: x, y: y) }

    /// Half size about the top-left corner, moved by half the output: the bottom-right quarter.
    private func quarterBottomRight() throws -> LayerTransform {
        try LayerTransform(translation: p(0.5, 0.5), uniformScale: 0.5, anchor: p(0, 0))
    }

    private func settings(_ transform: LayerTransform, opacity: Double = 1) -> LayerCompositeSettings {
        LayerCompositeSettings(opacity: opacity, transform: transform)
    }

    /// Pixels of a 64 × 64 read-back for which `region` holds, skipping a 1 px band on each side of
    /// the lines x = 32 and y = 32 (the edge tolerance).
    private func pixels(_ all: [Pixel], where region: (Int, Int) -> Bool) -> [Pixel] {
        var out: [Pixel] = []
        for y in 0..<64 where y != 31 && y != 32 {
            for x in 0..<64 where x != 31 && x != 32 && region(x, y) { out.append(all[y * 64 + x]) }
        }
        return out
    }

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
        return Array(UnsafeBufferPointer(start: buffer.contents().bindMemory(to: UInt16.self, capacity: count), count: count))
    }

    // MARK: - US2

    func testMovedQuarterSizeSquareLandsInTheCorner() throws {
        let rig = try GPURig()
        let compositor = try Compositor(device: rig.device)
        var stack = LayerStack()
        try stack.add(TransformFactory.solid(red), settings: settings(try quarterBottomRight()))
        try apply(stack, compositor, TransformFactory())
        let output = try rig.output()
        try rig.frame(compositor, into: output, time: 0)
        XCTAssertEqual(compositor.transformedDraws, 1)
        let all = try rig.read(output)
        assertAll(pixels(all) { (x: Int, y: Int) -> Bool in x >= 32 && y >= 32 }, equal: red, "bottom-right quarter")
        assertAll(pixels(all) { (x: Int, y: Int) -> Bool in x < 32 || y < 32 }, equal: .zero, tolerance: 0, "transparent elsewhere")
    }

    func testQuarterTurnMovesTheAsymmetricPatternClockwise() throws {
        let rig = try GPURig()
        let compositor = try Compositor(device: rig.device)
        var stack = LayerStack()
        try stack.add(LayerDescriptor(kind: TransformFactory.quadrantKind), settings: settings(try LayerTransform(rotation: .pi / 2)))
        try apply(stack, compositor, TransformFactory())
        let output = try rig.output()
        try rig.frame(compositor, into: output, time: 0)
        let all = try rig.read(output)
        assertAll(pixels(all) { (x: Int, y: Int) -> Bool in x >= 32 && y < 32 }, equal: red, "red: top-left → top-right")
        assertAll(pixels(all) { (x: Int, y: Int) -> Bool in x >= 32 && y >= 32 }, equal: green, "green: top-right → bottom-right")
        assertAll(pixels(all) { (x: Int, y: Int) -> Bool in x < 32 }, equal: .zero, tolerance: 0, "left half transparent")
    }

    func testIdentityWithAnyAnchorIsBitIdenticalAndTakesThePlainPath() throws {
        let rig = try GPURig()
        func render(_ transform: LayerTransform) throws -> (bits: [UInt16], transformed: Int) {
            let compositor = try Compositor(device: rig.device)
            var stack = LayerStack()
            try stack.add(TransformFactory.solid(blue))
            try stack.add(TransformFactory.solid(odd), settings: settings(transform, opacity: 0.6))
            try apply(stack, compositor, TransformFactory())
            let output = try rig.output()
            try rig.frame(compositor, into: output, time: 1_000_000_000)
            return (try raw(rig, output), compositor.transformedDraws)
        }
        let reference = try render(.identity)
        let anchored = try render(try LayerTransform(anchor: p(0.1, 0.9)))
        XCTAssertEqual(anchored.bits, reference.bits, "bit-identical to the CMP-003 output")
        XCTAssertEqual(anchored.transformed, 0)
        XCTAssertEqual(reference.transformed, 0)
    }

    func testOpacityAndDirectLayersApplyToTransformedLayers() throws {
        let rig = try GPURig()
        let bottom = SolidLayer("blue", color: blue)
        let top = SolidLayer("red", color: red)
        top.settings = settings(try quarterBottomRight(), opacity: 0.5)
        let compositor = try Compositor(device: rig.device, layers: [bottom, top])
        XCTAssertEqual(compositor.shownTransform(ofLayer: 1), try quarterBottomRight())
        let output = try rig.output()
        try rig.frame(compositor, into: output, time: 0)
        let all = try rig.read(output)
        assertAll(pixels(all) { (x: Int, y: Int) -> Bool in x >= 32 && y >= 32 }, equal: Pixel(0.5, 0, 0.5, 1), "half red over blue")
        assertAll(pixels(all) { (x: Int, y: Int) -> Bool in x < 32 || y < 32 }, equal: blue, tolerance: 0, "blue elsewhere")
    }

    func testTransformedLayersAreLimitedByTheFlashGuard() throws {
        let rig = try GPURig()
        let factory = TransformFactory()
        let compositor = try Compositor(device: rig.device)
        let output = try rig.output()
        var stack = LayerStack()
        try stack.add(TransformFactory.solid(black))
        let whiteID = try stack.add(TransformFactory.solid(white), settings: settings(try LayerTransform(translation: p(5, 0))))
        try apply(stack, compositor, factory)
        for i in 0..<10 { try rig.frame(compositor, into: output, time: UInt64(i) * Self.frameNanoseconds, reduceFlashing: true) }
        XCTAssertEqual(compositor.lastFlashGain, 1, "white is off screen: black only")
        try stack.setSettings(settings(try LayerTransform(rotation: .pi)), of: whiteID)   // covers the whole output
        try apply(stack, compositor, factory)
        try rig.frame(compositor, into: output, time: 10 * Self.frameNanoseconds, reduceFlashing: true)
        XCTAssertEqual(compositor.transformedDraws, 1)
        XCTAssertLessThan(compositor.lastFlashGain, 0.1, "a transformed jump to white is held (CMP-005-R9)")
    }

    // MARK: - US3

    func testTransformEditsReuseLayersAndAllocateNothing() throws {
        let rig = try GPURig()
        let factory = TransformFactory()
        let compositor = try Compositor(device: rig.device)
        let output = try rig.output()
        var stack = LayerStack()
        try stack.add(TransformFactory.solid(blue))
        let redID = try stack.add(TransformFactory.solid(red))
        try apply(stack, compositor, factory)
        try rig.frame(compositor, into: output, time: 0)
        let pictures = compositor.pictureAllocations
        XCTAssertEqual(compositor.layerPreparations, 2)
        XCTAssertEqual(factory.calls, 2)

        // A transform-only edit: shown at the next frame, nothing created or prepared.
        try stack.setSettings(settings(try quarterBottomRight()), of: redID)
        try apply(stack, compositor, factory)
        XCTAssertEqual(factory.calls, 2)
        XCTAssertEqual(compositor.layerPreparations, 2)
        try rig.frame(compositor, into: output, time: Self.frameNanoseconds)
        var all = try rig.read(output)
        assertAll(pixels(all) { (x: Int, y: Int) -> Bool in x >= 32 && y >= 32 }, equal: red, "moved at the next frame")
        assertAll(pixels(all) { (x: Int, y: Int) -> Bool in x < 32 || y < 32 }, equal: blue, tolerance: 0, "blue elsewhere")

        // 30 transformed frames at a steady size create no pictures.
        for i in 2..<32 { try rig.frame(compositor, into: output, time: UInt64(i) * Self.frameNanoseconds) }
        XCTAssertEqual(compositor.pictureAllocations, pictures)
        XCTAssertEqual(compositor.transformedDraws, 1)

        // Moved fully off the output: only the layer below shows.
        try stack.setSettings(settings(try LayerTransform(translation: p(-3, 0))), of: redID)
        try apply(stack, compositor, factory)
        try rig.frame(compositor, into: output, time: 40 * Self.frameNanoseconds)
        all = try rig.read(output)
        assertAll(all, equal: blue, tolerance: 0, "off screen")
        XCTAssertEqual(compositor.layerPreparations, 2)
        XCTAssertEqual(compositor.pictureAllocations, pictures)
    }
}
#endif
