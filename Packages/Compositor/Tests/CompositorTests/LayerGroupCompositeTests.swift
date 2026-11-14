// CMP-011-T07, T09, T10, T11: layer groups through the real Metal compositor (CMP-011-R5 to R10, R13;
// S1-S3, S5). Output 96 × 64 (`rgba16Float`, linear premultiplied). `BoxLayer` draws one opaque coloured
// rectangle at a known place in its output-sized picture (blitted from a small staging texture, so no
// test shader is needed). The acceptance: a group moved, scaled and rotated moves both boxes to where
// the CPU composition G(a)·L(a) predicts (centroid within 1 px), and every child's own transform is
// unchanged. Then group opacity (isolated) against a CPU reference, a disabled group, flattening,
// a fade, steady-state allocation, a masked child, a screen child, a fitted photo, and an opt-in GPU
// time bench. Skipped without a Metal device.
#if canImport(Metal) && !COMPOSITOR_NO_METAL && canImport(ImageIO)
import Compositor
import Foundation
import ImageLayer
import Metal
import XCTest

/// Clears its picture to transparent, then copies an opaque `color` rectangle into it.
final class BoxLayer: LayerSource {
    let layerName: String
    let fallback = LayerFallback.transparent
    let color: Pixel
    let x: Int, y: Int, width: Int, height: Int
    private var staging: MTLTexture?

    init(_ name: String, color: Pixel, x: Int, y: Int, width: Int, height: Int) {
        layerName = name
        self.color = color
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// Float → half for the exact values the tests use (0, powers of two and their sums).
    static func half(_ f: Float) -> UInt16 {
        if f == 0 { return 0 }
        let bits: UInt32 = f.bitPattern
        let sign = UInt16((bits >> 16) & 0x8000)
        let exponent: Int = Int((bits >> 23) & 0xFF) - 127 + 15
        let mantissa = UInt16((bits >> 13) & 0x3FF)
        return sign | (UInt16(exponent) << 10) | mantissa
    }

    func prepare(picture: LayerPictureDescriptor, device: MTLDevice) throws(LayerSourceError) {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: LayerPictureDescriptor.metalPixelFormat, width: width,
                                                         height: height, mipmapped: false)
        d.storageMode = .shared
        guard let t = device.makeTexture(descriptor: d) else { throw .resourceUnavailable("box staging") }
        let texel: [UInt16] = [Self.half(color.x), Self.half(color.y), Self.half(color.z), Self.half(color.w)]
        var data: [UInt16] = []
        for _ in 0..<(width * height) { data.append(contentsOf: texel) }
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            if let base = raw.baseAddress {
                t.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: base, bytesPerRow: width * 8)
            }
        }
        staging = t
    }

    func render(into picture: MTLTexture, commandBuffer: MTLCommandBuffer, frame: LayerFrameContext,
                audio: LayerAudioContext) throws(LayerSourceError) {
        SolidLayer.clear(picture, to: .zero, commandBuffer: commandBuffer)
        guard let staging, let blit = commandBuffer.makeBlitCommandEncoder() else { throw .frameSkipped }
        blit.copy(from: staging, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: width, height: height, depth: 1), to: picture, destinationSlice: 0,
                  destinationLevel: 0, destinationOrigin: MTLOrigin(x: x, y: y, z: 0))
        blit.endEncoding()
    }

    /// The box's centre in normalized layer coordinates.
    func centre(_ w: Int, _ h: Int) -> LayerPoint {
        LayerPoint(x: (Double(x) + Double(width) / 2) / Double(w), y: (Double(y) + Double(height) / 2) / Double(h))
    }
}

final class LayerGroupCompositeTests: XCTestCase {
    private static let w = 96, h = 64
    private static let red = Pixel(1, 0, 0, 1)
    private static let green = Pixel(0, 1, 0, 1)
    private static let blue = Pixel(0, 0, 1, 1)
    private static let kind = LayerKind("cmp011.layer")
    private static let frame: UInt64 = 16_666_667

    // MARK: - Rig

    private final class Rig {
        let gpu: GPURig
        let compositor: Compositor
        let output: MTLTexture
        var stack = LayerStack()
        var layers: [LayerInstanceID: any LayerSource] = [:]
        var time: UInt64 = 0

        init() throws {
            gpu = try GPURig()
            compositor = try Compositor(device: gpu.device)
            output = try gpu.output(width: LayerGroupCompositeTests.w, height: LayerGroupCompositeTests.h)
        }

        @discardableResult
        func add(_ layer: any LayerSource, _ settings: LayerCompositeSettings = LayerCompositeSettings()) throws -> LayerInstanceID {
            let id = try stack.add(LayerDescriptor(kind: LayerGroupCompositeTests.kind), settings: settings)
            layers[id] = layer
            return id
        }

        func apply(_ transition: LayerOpacityTransition = .immediate) throws {
            let known = layers
            try compositor.apply(stack, opacityTransition: transition) { (entry: LayerStackEntry) throws(LayerSourceError) -> any LayerSource in
                guard let layer = known[entry.id] else { throw .notReady }
                return layer
            }
        }

        /// Applies the stack, draws `frames` frames and reads the last one back.
        func render(frames: Int = 2) throws -> [Pixel] {
            try apply()
            for _ in 0..<frames {
                try gpu.frame(compositor, into: output, time: time)
                time += LayerGroupCompositeTests.frame
            }
            return try gpu.read(output)
        }
    }

    // MARK: - Measuring

    /// Alpha-weighted centroid (pixel units, centres at +0.5) of pixels where `channel` dominates.
    private func centroid(_ pixels: [Pixel], channel: Int) -> LayerPoint? {
        var sx: Double = 0, sy: Double = 0, sw: Double = 0
        for j in 0..<Self.h {
            for i in 0..<Self.w {
                let p: Pixel = pixels[j * Self.w + i]
                var others: Float = 0
                for c in 0..<3 where c != channel { others = max(others, p[c]) }
                guard p[channel] > 0.01, others < 0.001 else { continue }
                let weight = Double(p[channel])
                sx += (Double(i) + 0.5) * weight
                sy += (Double(j) + 0.5) * weight
                sw += weight
            }
        }
        return sw > 0 ? LayerPoint(x: sx / sw, y: sy / sw) : nil
    }

    /// Where a box centre lands: G(a)·L(a) applied to its normalized centre, in pixels.
    private func predicted(_ box: BoxLayer, group: LayerTransform, local: LayerTransform) -> LayerPoint {
        let m = LayerGroupComposition.matrix(group: group, local: local, outputWidth: Self.w, outputHeight: Self.h)
        let p: LayerPoint = m.apply(box.centre(Self.w, Self.h))
        return LayerPoint(x: p.x * Double(Self.w), y: p.y * Double(Self.h))
    }

    // MARK: - US1: the acceptance (CMP-011-S1)

    func testMovingScalingAndRotatingAGroupMovesBothChildrenAndKeepsTheirLocalTransforms() throws {
        let redBox = BoxLayer("red", color: Self.red, x: 16, y: 24, width: 12, height: 12)
        let greenBox = BoxLayer("green", color: Self.green, x: 40, y: 12, width: 12, height: 12)   // stays on screen in every case
        let redLocal = try LayerTransform(translation: LayerPoint(x: -0.05, y: 0.1))
        let greenLocal = try LayerTransform(uniformScale: 1.25, rotation: 0.4)
        let cases: [(String, LayerTransform)] = [
            ("identity", .identity),
            ("move right ¼", try LayerTransform(translation: LayerPoint(x: 0.25, y: 0))),
            ("scale ½", try LayerTransform(uniformScale: 0.5)),
            ("rotate 0.3 rad", try LayerTransform(rotation: 0.3)),
            ("move + scale + rotate, off-centre anchor", try LayerTransform(translation: LayerPoint(x: 0.1, y: -0.05), uniformScale: 0.75,
                                                                           rotation: -0.5, anchor: LayerPoint(x: 0.4, y: 0.6))),
        ]
        var table: [String] = []
        for (name, groupTransform) in cases {
            let rig = try Rig()
            let r = try rig.add(redBox, LayerCompositeSettings(transform: redLocal))
            let g = try rig.add(greenBox, LayerCompositeSettings(transform: greenLocal))
            let group = try rig.stack.makeGroup([r, g], settings: LayerGroupSettings(name: "pair", transform: groupTransform))
            let pixels = try rig.render()
            XCTAssertEqual(rig.compositor.isolatedGroupDraws, 0, "\(name): opacity 1, normal children: flattened")
            for (label, box, local, channel) in [("red", redBox, redLocal, 0), ("green", greenBox, greenLocal, 1)] {
                let expected = predicted(box, group: groupTransform, local: local)
                let measured = try XCTUnwrap(centroid(pixels, channel: channel), "\(name): \(label) visible")
                let dx: Double = measured.x - expected.x
                let dy: Double = measured.y - expected.y
                let error: Double = (dx * dx + dy * dy).squareRoot()
                XCTAssertLessThanOrEqual(error, 1, "\(name): \(label) at \(measured), predicted \(expected)")
                table.append("| \(name) | \(label) | " + String(format: "(%.2f, %.2f) | (%.2f, %.2f) | %.3f", expected.x, expected.y,
                                                                    measured.x, measured.y, error) + " |")
            }
            // The local transforms are untouched, in the stack and in what the compositor draws.
            XCTAssertEqual(rig.stack.entry(r)?.settings.transform, redLocal)
            XCTAssertEqual(rig.stack.entry(g)?.settings.transform, greenLocal)
            XCTAssertEqual(rig.compositor.shownTransform(ofLayer: 0), redLocal)
            XCTAssertEqual(rig.compositor.shownTransform(ofLayer: 1), greenLocal)
            XCTAssertEqual(rig.stack.group(group)?.settings.transform, groupTransform)
        }
        print("CMP-011 pixel results (96 × 64): | case | child | predicted centre (px) | measured centre (px) | error (px) |")
        for line in table { print("CMP-011 pixels: " + line) }
    }

    func testAnIdentityGroupAndAnOneChildMovedGroupDrawExactlyAsWithoutGroups() throws {
        let move = try LayerTransform(translation: LayerPoint(x: 0.2, y: 0.1), rotation: 0.2)
        func pixels(grouped: Bool, transform: LayerTransform) throws -> [Pixel] {
            let rig = try Rig()
            try rig.add(SolidLayer("backdrop", color: Pixel(0.25, 0.25, 0.25, 1)))
            let id = try rig.add(BoxLayer("red", color: Self.red, x: 30, y: 20, width: 20, height: 16),
                                 LayerCompositeSettings(transform: grouped ? .identity : transform))
            if grouped { try rig.stack.makeGroup([id], settings: LayerGroupSettings(transform: transform)) }
            return try rig.render()
        }
        XCTAssertEqual(try pixels(grouped: true, transform: .identity), try pixels(grouped: false, transform: .identity),
                       "identity group: the layer's own path, bit for bit")
        XCTAssertEqual(try pixels(grouped: true, transform: move), try pixels(grouped: false, transform: move),
                       "G·identity = G: same matrix, same pixels")
    }

    // MARK: - US2: group opacity and enable state (CMP-011-S2)

    /// Two overlapping opaque boxes in a group over a blue backdrop (identity placements: exact pixel
    /// coverage, so the reference needs no filtering).
    private func overlapRig(opacity: Double, enabled: Bool = true) throws -> Rig {
        let rig = try Rig()
        try rig.add(SolidLayer("backdrop", color: Self.blue))
        let a = try rig.add(BoxLayer("red", color: Self.red, x: 10, y: 10, width: 40, height: 30))
        let b = try rig.add(BoxLayer("green", color: Self.green, x: 30, y: 20, width: 40, height: 30))
        try rig.stack.makeGroup([a, b], settings: LayerGroupSettings(isEnabled: enabled, opacity: opacity))
        return rig
    }

    private func inBox(_ i: Int, _ j: Int, _ x: Int, _ y: Int, _ w: Int, _ h: Int) -> Bool { i >= x && i < x + w && j >= y && j < y + h }

    func testGroupOpacityFadesTheGroupAsOnePicture() throws {
        let rig = try overlapRig(opacity: 0.5)
        let pixels = try rig.render()
        XCTAssertEqual(rig.compositor.isolatedGroupDraws, 1)
        var worst: Float = 0
        var differsFromPerChild = 0
        for j in 0..<Self.h {
            for i in 0..<Self.w {
                let r = inBox(i, j, 10, 10, 40, 30), g = inBox(i, j, 30, 20, 40, 30)
                // Isolated: O = green over red over transparent, then O × 0.5 over blue.
                let o: Pixel = g ? Self.green : (r ? Self.red : .zero)
                let isolated: Pixel = o * 0.5 + Self.blue * (1 - o.w * 0.5)
                // Per-child multiplication (rejected, ADR-0039): green×½ over (red×½ over blue).
                let lower: Pixel = r ? Self.red * 0.5 + Self.blue * 0.5 : Self.blue
                let perChild: Pixel = g ? Self.green * 0.5 + lower * 0.5 : lower
                let p = pixels[j * Self.w + i]
                for c in 0..<4 { worst = max(worst, abs(p[c] - isolated[c])) }
                if r && g, abs(p.x - perChild.x) > 0.1 { differsFromPerChild += 1 }
            }
        }
        XCTAssertLessThanOrEqual(worst, 0.01, "isolated group vs CPU reference")
        XCTAssertEqual(differsFromPerChild, 20 * 20, "every overlap pixel shows no trace of the lower box")
        XCTAssertEqual(pixels[30 * Self.w + 40], Pixel(0, 0.5, 0.5, 1), "overlap: half green, half blue")
        print("CMP-011 group opacity 0.5: max |GPU − reference| = \(worst); overlap pixel \(pixels[30 * Self.w + 40])")
    }

    func testADisabledGroupHidesItsChildrenWhichKeepRendering() throws {
        let rig = try overlapRig(opacity: 1, enabled: false)
        let pixels = try rig.render()
        assertAll(pixels, equal: Self.blue, tolerance: 0, "only the backdrop")
        for k in 1...2 { XCTAssertEqual(rig.compositor.outcome(ofLayer: k), .rendered, "children still render") }
        let zero = try overlapRig(opacity: 0)
        assertAll(try zero.render(), equal: Self.blue, tolerance: 0, "group opacity 0")
    }

    func testAFlattenedGroupEqualsTheSameLayersUngroupedWithNoExtraPass() throws {
        let grouped = try overlapRig(opacity: 1)
        let flattened = try grouped.render()
        XCTAssertEqual(grouped.compositor.isolatedGroupDraws, 0)
        let plain = try Rig()
        try plain.add(SolidLayer("backdrop", color: Self.blue))
        try plain.add(BoxLayer("red", color: Self.red, x: 10, y: 10, width: 40, height: 30))
        try plain.add(BoxLayer("green", color: Self.green, x: 30, y: 20, width: 40, height: 30))
        XCTAssertEqual(flattened, try plain.render())
        // The isolated path just below 1 stays within half-float rounding of the flattened one (ADR-0039).
        let nearlyOne = try overlapRig(opacity: 0.999)
        assertAll(try nearlyOne.render().enumerated().map { (k: Int, p: Pixel) -> Pixel in p - flattened[k] }, equal: .zero,
                  tolerance: 0.002, "isolated at 0.999 ≈ flattened (associativity)")
        XCTAssertEqual(nearlyOne.compositor.isolatedGroupDraws, 1)
    }

    func testGroupOpacityFadesWithATransitionAndCreatesNothingAtASteadySize() throws {
        let rig = try overlapRig(opacity: 1)
        _ = try rig.render()
        let group = try XCTUnwrap(rig.stack.groups.first?.id)
        try rig.stack.setGroupSettings(LayerGroupSettings(opacity: 0.2), of: group)
        try rig.apply(try LayerOpacityTransition(duration: 0.1))
        var values: [Double] = []
        var allocations: [Int] = []
        for _ in 0..<10 {
            try rig.gpu.frame(rig.compositor, into: rig.output, time: rig.time)
            rig.time += Self.frame
            values.append(try XCTUnwrap(rig.compositor.shownGroupOpacity(of: group)))
            allocations.append(rig.compositor.pictureAllocations)
        }
        XCTAssertGreaterThan(values[1], 0.2, "fading, not jumping")
        XCTAssertLessThan(values[1], 1)
        for k in 1..<values.count { XCTAssertLessThanOrEqual(values[k], values[k - 1]) }
        XCTAssertEqual(values.last ?? 0, 0.2, accuracy: 1e-9)
        XCTAssertEqual(Set(allocations.dropFirst()).count, 1, "the group picture is created once, then reused: \(allocations)")
        let misses = rig.compositor.texturePool.counters.misses
        for _ in 0..<3 {
            try rig.gpu.frame(rig.compositor, into: rig.output, time: rig.time)
            rig.time += Self.frame
        }
        XCTAssertEqual(rig.compositor.texturePool.counters.misses, misses, "no texture created at a steady size")
        XCTAssertEqual(rig.compositor.isolatedGroupDraws, 1)
    }

    // MARK: - US3: masks, blend modes and fit inside groups (CMP-011-S3)

    func testAMaskedChildMovesWithItsGroup() throws {
        let rig = try Rig()
        let mask = try LayerMask(shape: .ellipse, transform: LayerMaskTransform(scale: LayerPoint(x: 0.5, y: 0.5)))
        let color = Pixel(0.5, 0.25, 0.125, 1)
        let id = try rig.add(SolidLayer("masked", color: color), LayerCompositeSettings(mask: mask))
        let groupTransform = try LayerTransform(translation: LayerPoint(x: 0.25, y: 0.1), rotation: 0.3)
        try rig.stack.makeGroup([id], settings: LayerGroupSettings(transform: groupTransform))
        let pixels = try rig.render()
        XCTAssertEqual(rig.compositor.maskedDraws, 1)
        // Output pixel → layer pixel through the inverse of G·L (pixels), then the CPU mask reference.
        let m = LayerGroupComposition.matrix(group: groupTransform, local: .identity, outputWidth: Self.w, outputHeight: Self.h)
        let inverse = try XCTUnwrap(m.inverse)
        let geometry = mask.geometry(width: Self.w, height: Self.h)
        let half: Double = geometry.band / 2 + 0.05
        var outside = 0, outsideViolations = 0, inside = 0, insideViolations = 0
        for j in 0..<Self.h {
            for i in 0..<Self.w {
                let n = LayerPoint(x: (Double(i) + 0.5) / Double(Self.w), y: (Double(j) + 0.5) / Double(Self.h))
                let l: LayerPoint = inverse.apply(n)
                let lx: Double = l.x * Double(Self.w)
                let ly: Double = l.y * Double(Self.h)
                let d: Double = geometry.signedDistance(x: lx, y: ly)
                let p = pixels[j * Self.w + i]
                if d >= half {
                    outside += 1
                    if p != .zero { outsideViolations += 1 }
                } else if d <= -half, lx > 1, ly > 1, lx < Double(Self.w - 1), ly < Double(Self.h - 1) {
                    inside += 1
                    if abs(p.w - 1) > 0.001 || abs(p.x - color.x) > 0.001 { insideViolations += 1 }
                }
            }
        }
        XCTAssertGreaterThan(outside, 1000)
        XCTAssertGreaterThan(inside, 200)
        XCTAssertEqual(outsideViolations, 0, "outside the moved mask: exactly transparent")
        XCTAssertEqual(insideViolations, 0)
        // The circle's centre followed the group: layer centre (48, 32) → G applied.
        let c: LayerPoint = m.apply(LayerPoint(x: 0.5, y: 0.5))
        let k: Int = Int(c.y * Double(Self.h)) * Self.w + Int(c.x * Double(Self.w))
        XCTAssertEqual(pixels[k].w, 1, accuracy: 0.001)
    }

    func testAScreenChildBlendsWithinItsIsolatedGroup() throws {
        let gray = Pixel(0.5, 0.5, 0.5, 1)
        let screenColor = Pixel(0, 0.25, 0, 1)
        let rig = try Rig()
        try rig.add(SolidLayer("backdrop", color: gray))
        let a = try rig.add(BoxLayer("red", color: Self.red, x: 10, y: 10, width: 40, height: 30))
        let b = try rig.add(BoxLayer("screen", color: screenColor, x: 30, y: 20, width: 40, height: 30),
                            LayerCompositeSettings(blendMode: .screen))
        try rig.stack.makeGroup([a, b])
        let pixels = try rig.render()
        XCTAssertEqual(rig.compositor.isolatedGroupDraws, 1, "a non-normal child isolates the group even at opacity 1")
        XCTAssertEqual(rig.compositor.blendDraws, 1)
        func double(_ p: Pixel) -> LayerBlend.Pixel { LayerBlend.Pixel(Double(p.x), Double(p.y), Double(p.z), Double(p.w)) }
        var worst: Double = 0
        var passThroughDiffers = 0
        for j in 0..<Self.h {
            for i in 0..<Self.w {
                let r = inBox(i, j, 10, 10, 40, 30), s = inBox(i, j, 30, 20, 40, 30)
                let inner: LayerBlend.Pixel = r ? double(Self.red) : .zero
                let groupPicture: LayerBlend.Pixel = s ? LayerBlend.composite(.screen, backdrop: inner, source: double(screenColor)) : inner
                let expected: LayerBlend.Pixel = groupPicture + double(gray) * (1 - groupPicture[3])
                let below: LayerBlend.Pixel = r ? double(Self.red) : double(gray)
                let passThrough: LayerBlend.Pixel = s ? LayerBlend.composite(.screen, backdrop: below, source: double(screenColor)) : below
                let p = double(pixels[j * Self.w + i])
                for c in 0..<4 { worst = max(worst, abs(p[c] - expected[c])) }
                if abs(p[1] - passThrough[1]) > 0.05 { passThroughDiffers += 1 }
            }
        }
        XCTAssertLessThanOrEqual(worst, 0.01, "screen inside an isolated group vs CPU reference")
        XCTAssertGreaterThan(passThroughDiffers, 0, "the screen child does not reach the backdrop below the group")
        print("CMP-011 screen child in a group: max |GPU − reference| = \(worst); pixels differing from pass-through: \(passThroughDiffers)")
    }

    func testAFittedPhotoMovesWithItsGroupUnchanged() throws {
        let gpu = try GPURig()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CMP011-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = ImageFixtures.image(width: 30, height: 60) { (_: Int, y: Int) -> ImageFixtures.RGBA in
            ImageFixtures.RGBA(r: 255, g: UInt8(y * 4), b: 0, a: 255)
        }
        let url = directory.appendingPathComponent("portrait.png")
        try ImageFixtures.encode(image, .png).write(to: url)
        let move = try LayerTransform(translation: LayerPoint(x: -0.2, y: 0.05), uniformScale: 0.8)
        func render(grouped: Bool) throws -> [Pixel] {
            let rig = try Rig()
            let photo = ImageLayerSource(device: gpu.device)
            photo.content = .file(url)
            photo.waitUntilLoaded()
            let id = try rig.add(photo, LayerCompositeSettings(transform: grouped ? .identity : move, fit: LayerFit(mode: .fit)))
            if grouped { try rig.stack.makeGroup([id], settings: LayerGroupSettings(transform: move)) }
            return try rig.render()
        }
        let grouped = try render(grouped: true)
        XCTAssertGreaterThan(grouped.filter { (p: Pixel) -> Bool in p.w > 0.99 }.count, 500, "the fitted photo is visible")
        XCTAssertEqual(grouped, try render(grouped: false), "the fit is unchanged and moves with the group")
    }

    // MARK: - GPU time (CMP-011-S5; opt-in, not asserted)

    func testBenchGroupFlattenedVersusIsolated() throws {
        guard ProcessInfo.processInfo.environment["CMP011_BENCH"] == "1" else {
            throw XCTSkip("Set CMP011_BENCH=1 to measure GPU time of a 4-layer group (Release, Mac; not device evidence).")
        }
        let gpu = try GPURig()
        let output = try gpu.output(.bgra8Unorm_srgb, width: 1920, height: 1080)
        let cases: [(String, Bool, Double)] = [("4 layers, ungrouped", false, 1), ("4 layers, group flattened (opacity 1)", true, 1),
                                               ("4 layers, group isolated (opacity 0.5)", true, 0.5)]
        var lines: [String] = []
        for (name, grouped, opacity) in cases {
            var stack = LayerStack()
            var ids: [LayerInstanceID] = []
            for k in 0..<4 {
                let t = try LayerTransform(translation: LayerPoint(x: 0.05 * Double(k), y: 0), uniformScale: 0.6)
                ids.append(try stack.add(LayerDescriptor(kind: Self.kind), settings: LayerCompositeSettings(opacity: 0.8, transform: t)))
            }
            if grouped { try stack.makeGroup(ids, settings: LayerGroupSettings(opacity: opacity, transform: try LayerTransform(rotation: 0.1))) }
            let compositor = try Compositor(device: gpu.device)
            let layer = (0..<4).map { (k: Int) -> SolidLayer in SolidLayer("bench \(k)", color: Pixel(0.2 * Float(k), 0.3, 0.4, 1)) }
            var next = 0
            try compositor.apply(stack) { (_: LayerStackEntry) throws(LayerSourceError) -> any LayerSource in
                defer { next += 1 }
                return layer[next]
            }
            var samples: [Double] = []
            for k in 0..<130 {
                let commands = try XCTUnwrap(gpu.queue.makeCommandBuffer())
                _ = compositor.composite(into: output, commandBuffer: commands, presentationTimeNanoseconds: UInt64(k) * Self.frame,
                                         contentScale: 2, reduceFlashing: false, audio: .empty)
                commands.commit()
                commands.waitUntilCompleted()
                let gpuSeconds: Double = commands.gpuEndTime - commands.gpuStartTime
                if k >= 10 { samples.append(gpuSeconds * 1000) }
            }
            samples.sort()
            let median: Double = samples[samples.count / 2]
            let p95: Double = samples[samples.count * 95 / 100]
            lines.append("| \(name) | " + String(format: "%.3f | %.3f", median, p95) + " | \(compositor.isolatedGroupDraws) |")
        }
        print("CMP-011 GPU time per frame, 1920 × 1080 (ms): | case | median | p95 | isolated draws |")
        for line in lines { print("CMP-011 bench: " + line) }
    }
}
#endif
