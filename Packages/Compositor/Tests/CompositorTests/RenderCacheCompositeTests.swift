// CMP-013-T07, T09, T10, T12, T13: render caching through the real Metal compositor (CMP-013-R4 to R11,
// S1 to S5; contracts/render-caching.md). Small outputs (32 × 24) keep each test well under a second;
// skipped without a Metal device. Output frames are compared as raw `rgba16Float` bytes.
#if canImport(Metal) && !COMPOSITOR_NO_METAL && canImport(ImageIO)
import AnalysisFeatures
import Compositor
import FrameCapture
import Foundation
import ImageLayer
import Metal
import SpectrumLayers
import VisualGenerators
import XCTest

/// A solid layer that declares its dependencies (still by default) and counts its renders.
final class StillLayer: LayerSource, LayerRenderCaching {
    let layerName: String
    let fallback: LayerFallback
    var dependencies: LayerRenderDependencies
    /// Changing the colour bumps the content generation.
    var color: Pixel {
        didSet { dependencies.contentGeneration &+= 1 }
    }
    /// The next render draws garbage and throws this error.
    var failNext: LayerSourceError?
    private(set) var renders = 0
    private(set) var reuses = 0

    init(_ name: String, color: Pixel, fallback: LayerFallback = .transparent,
         dependencies: LayerRenderDependencies = .still(content: 1)) {
        layerName = name
        self.color = color
        self.fallback = fallback
        self.dependencies = dependencies
    }

    var renderDependencies: LayerRenderDependencies { dependencies }

    func renderReused(frame: LayerFrameContext) { reuses += 1 }

    func prepare(picture: LayerPictureDescriptor, device: MTLDevice) throws(LayerSourceError) {}

    func render(into picture: MTLTexture, commandBuffer: MTLCommandBuffer, frame: LayerFrameContext,
                audio: LayerAudioContext) throws(LayerSourceError) {
        if let error = failNext {
            failNext = nil
            SolidLayer.clear(picture, to: Pixel(0, 1, 0, 1), commandBuffer: commandBuffer)   // half-drawn garbage
            throw error
        }
        renders += 1
        SolidLayer.clear(picture, to: color, commandBuffer: commandBuffer)
    }
}

/// A solid layer that does not adopt `LayerRenderCaching` (unknown: always rendered).
final class UndeclaredLayer: LayerSource {
    let layerName = "undeclared"
    let fallback = LayerFallback.transparent
    private(set) var renders = 0

    func prepare(picture: LayerPictureDescriptor, device: MTLDevice) throws(LayerSourceError) {}

    func render(into picture: MTLTexture, commandBuffer: MTLCommandBuffer, frame: LayerFrameContext,
                audio: LayerAudioContext) throws(LayerSourceError) {
        renders += 1
        SolidLayer.clear(picture, to: Pixel(0.1, 0.2, 0.3, 1), commandBuffer: commandBuffer)
    }
}

/// A layer whose colour follows the frame index (truly time-dependent); declares `time`.
final class ClockLayer: LayerSource, LayerRenderCaching {
    let layerName = "clock"
    let fallback = LayerFallback.lastGoodFrame
    private(set) var renders = 0
    var renderDependencies: LayerRenderDependencies { LayerRenderDependencies(time: true) }

    func prepare(picture: LayerPictureDescriptor, device: MTLDevice) throws(LayerSourceError) {}

    func render(into picture: MTLTexture, commandBuffer: MTLCommandBuffer, frame: LayerFrameContext,
                audio: LayerAudioContext) throws(LayerSourceError) {
        renders += 1
        let v = Float(frame.frameIndex % 8) / 8
        SolidLayer.clear(picture, to: Pixel(v * 0.5, 0, 0.5, 0.5), commandBuffer: commandBuffer)
    }
}

/// One capture handed over from Metal's completion thread.
private final class HalvesBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [UInt16]?
    func set(_ value: [UInt16]) { lock.lock(); stored = value; lock.unlock() }
    var value: [UInt16]? { lock.lock(); defer { lock.unlock() }; return stored }
}

final class RenderCacheCompositeTests: XCTestCase {
    static let kind = LayerKind("cmp013.test")
    static let frameNanoseconds: UInt64 = 16_666_667
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("CMP013-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func photo(_ name: String, _ color: ImageFixtures.RGBA, width: Int = 40, height: Int = 20) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try ImageFixtures.encode(ImageFixtures.solid(color, width: width, height: height), .png).write(to: url)
        return url
    }

    /// A compositor driven through a `LayerStack`, with its own layer objects.
    final class Rig {
        let gpu: GPURig
        let compositor: Compositor
        var output: MTLTexture
        var stack = LayerStack()
        var layers: [LayerInstanceID: any LayerSource] = [:]
        var time: UInt64 = 1
        var reduceFlashing = false
        var scale: Double = 2

        init(gpu: GPURig, caching: Bool = true, width: Int = 32, height: Int = 24) throws {
            self.gpu = gpu
            compositor = try Compositor(device: gpu.device)
            compositor.isRenderCachingEnabled = caching
            output = try gpu.output(width: width, height: height)
        }

        @discardableResult
        func add(_ layer: any LayerSource, _ settings: LayerCompositeSettings = LayerCompositeSettings()) throws -> LayerInstanceID {
            let id = try stack.add(LayerDescriptor(kind: RenderCacheCompositeTests.kind), settings: settings)
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

        func edit(_ id: LayerInstanceID, _ change: (inout LayerCompositeSettings) throws -> Void) throws {
            var settings = try XCTUnwrap(stack.entry(id)).settings
            try change(&settings)
            try stack.setSettings(settings, of: id)
        }

        func overlay(_ change: (inout LayerSoloMute) -> Void) {
            var o = compositor.soloMute
            change(&o)
            compositor.setSoloMute(o)
        }

        @discardableResult
        func frame() throws -> Bool {
            let ok = try gpu.frame(compositor, into: output, time: time, reduceFlashing: reduceFlashing, scale: scale)
            time += RenderCacheCompositeTests.frameNanoseconds
            return ok
        }

        func frames(_ n: Int) throws {
            for _ in 0..<n { XCTAssertTrue(try frame()) }
        }

        /// The output's raw bytes.
        func bytes() throws -> [UInt8] { try RenderCacheCompositeTests.rawBytes(output, gpu: gpu) }

        func pixels() throws -> [Pixel] { try gpu.read(output) }
    }

    static func rawBytes(_ texture: MTLTexture, gpu: GPURig) throws -> [UInt8] {
        let rowBytes = texture.width * 8
        let count = rowBytes * texture.height
        let buffer = try XCTUnwrap(gpu.device.makeBuffer(length: count, options: .storageModeShared))
        let commands = try XCTUnwrap(gpu.queue.makeCommandBuffer())
        let blit = try XCTUnwrap(commands.makeBlitCommandEncoder())
        blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: texture.width, height: texture.height, depth: 1), to: buffer,
                  destinationOffset: 0, destinationBytesPerRow: rowBytes, destinationBytesPerImage: count)
        blit.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        return Array(UnsafeBufferPointer(start: buffer.contents().bindMemory(to: UInt8.self, capacity: count), count: count))
    }

    private let red = Pixel(1, 0, 0, 1)
    private let blue = Pixel(0, 0, 1, 1)

    // MARK: - US1: the acceptance (CMP-013-S1)

    /// "Static source renders once over ten frames; parameter change invalidates cache": the real photo layer.
    func testAStaticPhotoRendersOnceOverTenFramesAndAFitChangeRendersItExactlyOnce() throws {
        let rig = try Rig(gpu: try GPURig())
        let layer = ImageLayerSource(device: rig.gpu.device)
        layer.content = .file(try photo("teal.png", ImageFixtures.RGBA(r: 0, g: 128, b: 128, a: 255)))
        layer.waitUntilLoaded()
        let id = try rig.add(layer)
        try rig.apply()
        try rig.frames(10)
        XCTAssertEqual(layer.renderCount, 1, "S1: the photo renders once over ten frames")
        XCTAssertEqual(layer.framesShown, 10, "and is shown in all ten")
        XCTAssertEqual(rig.compositor.renderCacheHits, 1)
        XCTAssertTrue(rig.compositor.wasReused(layer: 0))
        XCTAssertEqual(rig.compositor.outcome(ofLayer: 0), .rendered, "a reused picture is a rendered outcome")
        let filled = try rig.pixels()

        try rig.edit(id) { (s: inout LayerCompositeSettings) in s.fit = LayerFit(mode: .fit) }   // a parameter of the photo's own render
        try rig.apply()
        try rig.frame()
        XCTAssertEqual(layer.renderCount, 2, "the fit change renders exactly once")
        XCTAssertFalse(rig.compositor.wasReused(layer: 0))
        try rig.frames(9)
        XCTAssertEqual(layer.renderCount, 2, "then the new picture is reused")
        XCTAssertEqual(layer.framesShown, 20)
        let fitted = try rig.pixels()
        XCTAssertNotEqual(fitted, filled, "the read-back shows the fit (transparent bars)")
        XCTAssertEqual(fitted[0].w, 0, "top-left is a bar")

        // A new photo: rendered once it is loaded; the old picture is never shown again.
        layer.content = .file(try photo("red.png", ImageFixtures.RGBA(r: 255, g: 0, b: 0, a: 255), width: 64, height: 48))
        try rig.frame()
        assertAll(try rig.pixels(), equal: .zero, tolerance: 0, "while loading: the transparent fallback, not the old photo")
        layer.waitUntilLoaded()
        let before = layer.renderCount
        try rig.frames(3)
        XCTAssertEqual(layer.renderCount, before + 1, "the new photo renders exactly once")
        assertAll(try rig.pixels(), equal: Pixel(1, 0, 0, 1), tolerance: 2.0 / 255, "and shows")
    }

    /// CMP-013-R5: placement parameters never cause a layer render, and the frame shows them.
    func testPlacementChangesDoNotRenderTheLayerButShowInTheFrame() throws {
        let rig = try Rig(gpu: try GPURig())
        let below = StillLayer("below", color: blue)
        let layer = StillLayer("top", color: Pixel(0.5, 0, 0, 0.5))
        try rig.add(below)
        let id = try rig.add(layer)
        try rig.apply()
        try rig.frames(2)
        XCTAssertEqual(layer.renders, 1)
        var last = try rig.bytes()
        let changes: [(String, (inout LayerCompositeSettings) throws -> Void)] = [
            ("opacity", { (s: inout LayerCompositeSettings) in s.opacity = 0.4 }),
            ("transform", { (s: inout LayerCompositeSettings) in s.transform = try LayerTransform(uniformScale: 0.5) }),
            ("blend", { (s: inout LayerCompositeSettings) in s.blendMode = .screen }),
            ("mask", { (s: inout LayerCompositeSettings) in s.mask = try LayerMask(shape: .ellipse) }),
        ]
        for (name, change) in changes {
            try rig.edit(id, change)
            try rig.apply()
            try rig.frame()
            XCTAssertEqual(layer.renders, 1, "\(name): no layer render")
            XCTAssertTrue(rig.compositor.wasReused(layer: 1), name)
            XCTAssertFalse(rig.compositor.compositeReused, "\(name): the composite is redrawn")
            let now = try rig.bytes()
            XCTAssertNotEqual(now, last, "\(name) shows in the frame")
            last = now
        }
        XCTAssertEqual(below.renders, 1)
    }

    // MARK: - US2: bit-identical output (CMP-013-R9, S3)

    /// Two compositors, caching on and off, run the same script; every output frame is byte-identical.
    func testOutputWithCachingIsBitIdenticalToWithoutOverAScriptedSequence() throws {
        let gpu = try GPURig()
        let tealURL = try photo("teal.png", ImageFixtures.RGBA(r: 0, g: 128, b: 128, a: 255))
        let orangeURL = try photo("orange.png", ImageFixtures.RGBA(r: 255, g: 128, b: 0, a: 255), width: 20, height: 40)
        final class Side {
            let rig: Rig
            let base: StillLayer
            let photo: ImageLayerSource
            let screen: StillLayer
            let grouped: StillLayer
            let clock: ClockLayer
            var ids: [LayerInstanceID] = []
            var group: LayerGroupID?
            init(_ gpu: GPURig, caching: Bool, photo url: URL) throws {
                rig = try Rig(gpu: gpu, caching: caching)
                base = StillLayer("base", color: Pixel(0.2, 0.3, 0.4, 1))
                photo = ImageLayerSource(device: gpu.device)
                photo.content = .file(url)
                photo.waitUntilLoaded()
                screen = StillLayer("screen", color: Pixel(0.3, 0.1, 0.0, 0.6))
                grouped = StillLayer("grouped", color: Pixel(0, 0.4, 0, 0.8), fallback: .lastGoodFrame)
                clock = ClockLayer()
                ids.append(try rig.add(base))
                ids.append(try rig.add(photo, LayerCompositeSettings(opacity: 0.9)))
                ids.append(try rig.add(screen, LayerCompositeSettings(blendMode: .screen)))
                ids.append(try rig.add(grouped))
                ids.append(try rig.add(clock))
                group = try rig.stack.makeGroup([ids[3], ids[4]], settings: LayerGroupSettings(name: "G"))
                try rig.apply()
            }
        }
        let sides = [try Side(gpu, caching: true, photo: tealURL), try Side(gpu, caching: false, photo: tealURL)]
        let fade = try LayerOpacityTransition(duration: 0.1)
        let script: [Int: (Side) throws -> Void] = [
            2: { (s: Side) in s.rig.overlay { (o: inout LayerSoloMute) in o.setMute(true, layer: s.ids[4]) } },   // only statics drawn
            6: { (s: Side) in s.base.color = Pixel(0.6, 0.2, 0.1, 1) },
            8: { (s: Side) in try s.rig.edit(s.ids[1]) { (c: inout LayerCompositeSettings) in c.fit = LayerFit(mode: .fit) }; try s.rig.apply() },
            10: { (s: Side) in try s.rig.edit(s.ids[2]) { (c: inout LayerCompositeSettings) in c.opacity = 0.3 }; try s.rig.apply(fade) },
            18: { (s: Side) in try s.rig.edit(s.ids[0]) { (c: inout LayerCompositeSettings) in c.transform = try LayerTransform(uniformScale: 0.75, rotation: 0.3) }; try s.rig.apply() },
            20: { (s: Side) in try s.rig.edit(s.ids[0]) { (c: inout LayerCompositeSettings) in c.blendMode = .multiply }; try s.rig.apply() },
            22: { (s: Side) in try s.rig.edit(s.ids[3]) { (c: inout LayerCompositeSettings) in c.mask = try LayerMask(shape: .rectangle(cornerRadius: 0.2)) }; try s.rig.apply() },
            24: { (s: Side) in
                try s.rig.stack.setGroupSettings(LayerGroupSettings(name: "G", opacity: 0.6), of: try XCTUnwrap(s.group))
                try s.rig.apply()
            },
            27: { (s: Side) in s.rig.overlay { (o: inout LayerSoloMute) in o.setSolo(true, layer: s.ids[1]) } },
            29: { (s: Side) in s.rig.overlay { (o: inout LayerSoloMute) in o.clear() } },   // the clock layer is back
            31: { (s: Side) in s.rig.overlay { (o: inout LayerSoloMute) in o.setMute(true, layer: s.ids[4]) } },
            33: { (s: Side) in s.rig.reduceFlashing = true },
            35: { (s: Side) in s.rig.compositor.texturePool.purge() },
            37: { (s: Side) in s.rig.output = try s.rig.gpu.output(width: 40, height: 30) },
            39: { (s: Side) in
                s.photo.content = .file(orangeURL)
                s.photo.waitUntilLoaded()
            },
            41: { (s: Side) in s.rig.scale = 3 },
        ]
        var compared = 0
        for f in 0..<44 {
            for side in sides {
                try script[f]?(side)
                XCTAssertTrue(try side.rig.frame(), "frame \(f)")
            }
            let cached = try sides[0].rig.bytes(), uncached = try sides[1].rig.bytes()
            XCTAssertEqual(cached, uncached, "frame \(f): byte-identical with and without caching")
            compared += 1
        }
        XCTAssertEqual(compared, 44)
        let on = sides[0].rig.compositor, off = sides[1].rig.compositor
        XCTAssertGreaterThan(on.compositeReuses, 5, "level 2 was exercised")
        XCTAssertEqual(off.compositeReuses, 0)
        XCTAssertLessThan(sides[0].base.renders, sides[1].base.renders, "level 1 was exercised")
        XCTAssertEqual(sides[0].clock.renders, sides[1].clock.renders, "the time-dependent layer rendered every frame on both")
        print("CMP-013 bit identity: 44 frames compared; base renders \(sides[0].base.renders) vs \(sides[1].base.renders); "
              + "photo renders \(sides[0].photo.renderCount) vs \(sides[1].photo.renderCount); composites reused \(on.compositeReuses)")
    }

    /// An all-static stack keeps its composite; the output and a frame capture stay identical.
    func testAnAllStaticStackReusesTheCompositeAndCapturesTheSameFrame() throws {
        let gpu = try GPURig()
        let on = try Rig(gpu: gpu), off = try Rig(gpu: gpu, caching: false)
        for rig in [on, off] {
            try rig.add(StillLayer("a", color: Pixel(0.2, 0.2, 0.2, 1)))
            try rig.add(StillLayer("b", color: Pixel(0, 0, 0.5, 0.5)), LayerCompositeSettings(blendMode: .overlay))
            try rig.apply()
            try rig.frames(3)
        }
        XCTAssertTrue(on.compositor.compositeReused)
        XCTAssertEqual(on.compositor.compositeReuses, 2, "frames 2 and 3 keep the composite frame 1 drew from the same pictures")
        XCTAssertEqual(try on.bytes(), try off.bytes())
        var captures: [[UInt16]] = []
        for rig in [on, off] {
            let done = expectation(description: "capture")
            let box = HalvesBox()
            rig.compositor.requestFrameCapture { (p: CapturedPixels?) in
                if let p, case .linearPremultipliedHalfRGBA(let halves) = p.layout { box.set(halves) }
                done.fulfill()
            }
            try rig.frame()
            wait(for: [done], timeout: 5)
            captures.append(try XCTUnwrap(box.value, "a capture"))
        }
        XCTAssertTrue(on.compositor.compositeReused, "the captured frame was a reused composite")
        XCTAssertEqual(captures[0], captures[1], "REC-001: the capture of a reused composite equals the uncached one")
    }

    // MARK: - US3: the invalidation table (CMP-013-R7, S2)

    private func cachedRig(_ layer: StillLayer, fallback: LayerFallback = .transparent) throws -> Rig {
        let rig = try Rig(gpu: try GPURig())
        try rig.add(layer)
        try rig.apply()
        try rig.frames(3)
        XCTAssertEqual(layer.renders, 1, "cached")
        XCTAssertTrue(rig.compositor.compositeReused)
        return rig
    }

    /// Runs `trigger`, then 3 frames: the layer renders exactly `renders` more times.
    private func expect(_ rig: Rig, _ layer: StillLayer, renders: Int, _ name: String, trigger: () throws -> Void,
                        file: StaticString = #filePath, line: UInt = #line) throws {
        let before = layer.renders
        try trigger()
        try rig.frames(3)
        XCTAssertEqual(layer.renders - before, renders, name, file: file, line: line)
        XCTAssertTrue(rig.compositor.wasReused(layer: 0), "\(name): cached again afterwards", file: file, line: line)
    }

    func testAContentChangeRendersOnceAndShowsTheNewContent() throws {
        let layer = StillLayer("s", color: red)
        let rig = try cachedRig(layer)
        try expect(rig, layer, renders: 1, "content") { layer.color = blue }
        assertAll(try rig.pixels(), equal: blue, tolerance: 0, "no stale picture")
    }

    func testAParameterChangeRendersOnce() throws {
        let layer = StillLayer("s", color: red)
        let rig = try cachedRig(layer)
        try expect(rig, layer, renders: 1, "parameter") { layer.dependencies.parameterGeneration &+= 1 }
    }

    func testAnOutputSizeChangeRendersOnce() throws {
        let layer = StillLayer("s", color: red)
        let rig = try cachedRig(layer)
        try expect(rig, layer, renders: 1, "size") { rig.output = try rig.gpu.output(width: 20, height: 20) }
        assertAll(try rig.pixels(), equal: red, tolerance: 0, "the new size is drawn")
    }

    func testReduceFlashingAndContentScaleChangesRenderOnce() throws {
        let layer = StillLayer("s", color: red)
        let rig = try cachedRig(layer)
        try expect(rig, layer, renders: 1, "Reduce flashing") { rig.reduceFlashing = true }
        try expect(rig, layer, renders: 1, "content scale") { rig.scale = 3 }
    }

    func testAPoolPurgeRendersOnce() throws {
        let layer = StillLayer("s", color: red)
        let rig = try cachedRig(layer)
        let epoch = rig.compositor.renderCacheEpoch
        try expect(rig, layer, renders: 1, "memory warning purge") { rig.compositor.texturePool.purge() }
        XCTAssertGreaterThan(rig.compositor.renderCacheEpoch, epoch)
    }

    func testResetRenderHealthAndExplicitInvalidationRenderOnce() throws {
        let layer = StillLayer("s", color: red)
        let rig = try cachedRig(layer)
        try expect(rig, layer, renders: 1, "render health reset") { rig.compositor.resetRenderHealth() }
        try expect(rig, layer, renders: 1, "explicit invalidation") { rig.compositor.invalidateRenderCache() }
    }

    func testSwitchingCachingOffRendersEveryFrameAndOnAgainRendersOnce() throws {
        let layer = StillLayer("s", color: red)
        let rig = try cachedRig(layer)
        rig.compositor.isRenderCachingEnabled = false
        let before = layer.renders
        try rig.frames(4)
        XCTAssertEqual(layer.renders - before, 4, "off: every frame, as before CMP-013")
        XCTAssertEqual(layer.reuses, 2, "off: never reused")
        XCTAssertFalse(rig.compositor.compositeReused)
        try expect(rig, layer, renders: 1, "on again") { rig.compositor.isRenderCachingEnabled = true }
    }

    func testAFailedRenderDropsTheEntryAndTheNextFrameRendersAgain() throws {
        let layer = StillLayer("s", color: red)
        let rig = try cachedRig(layer)
        layer.color = blue
        layer.failNext = .frameSkipped   // routine error: overwrites the single picture, shows transparent
        try rig.frame()
        XCTAssertEqual(rig.compositor.outcome(ofLayer: 0), .fallbackTransparent(.frameSkipped))
        assertAll(try rig.pixels(), equal: .zero, tolerance: 0, "the garbage is not shown")
        let before = layer.renders
        try rig.frames(3)
        XCTAssertEqual(layer.renders - before, 1, "the dropped entry renders once")
        assertAll(try rig.pixels(), equal: blue, tolerance: 0, "never the garbage picture")
    }

    func testAHeldFaultIsNotReusedAndRendersOnceAtItsRetry() throws {
        let layer = StillLayer("s", color: red, fallback: .lastGoodFrame)
        let rig = try cachedRig(layer)
        rig.compositor.faultInjection.failingRender = ["s"]
        try rig.frame()
        XCTAssertEqual(rig.compositor.outcome(ofLayer: 0), .fallbackLastGood(.engineFailure("injected")),
                       "the injected fault reaches render despite the cache")
        rig.compositor.faultInjection = RenderFaultInjection()
        let before = layer.renders
        for _ in 0..<29 {
            try rig.frame()
            XCTAssertFalse(rig.compositor.wasReused(layer: 0), "held: its fallback, never a cache hit")
        }
        XCTAssertEqual(layer.renders, before, "no render while held")
        try rig.frame()   // the retry tick (30 after the fault)
        try rig.frames(2)
        XCTAssertEqual(layer.renders - before, 1, "the retry renders once")
        XCTAssertTrue(rig.compositor.wasReused(layer: 0))
        assertAll(try rig.pixels(), equal: red, tolerance: 0, "")
    }

    func testAnObservedGPUErrorInvalidates() throws {
        let layer = StillLayer("s", color: red)
        let rig = try cachedRig(layer)
        let epoch = rig.compositor.renderCacheEpoch
        rig.compositor.faultInjection.gpuFault = .gpuError
        try rig.frame()   // observes the previous buffer as failed
        XCTAssertGreaterThan(rig.compositor.renderCacheEpoch, epoch, "the epoch moved: no picture of a failed buffer is reused")
        rig.compositor.faultInjection = RenderFaultInjection()
        rig.compositor.resetRenderHealth()
        try expect(rig, layer, renders: 1, "after the GPU error") {}
    }

    func testAFrameThatFailsHalfWayInvalidates() throws {
        let layer = StillLayer("s", color: red)
        let rig = try cachedRig(layer)
        let epoch = rig.compositor.renderCacheEpoch
        rig.compositor.faultInjection.missingPictures = ["composite"]
        rig.output = try rig.gpu.output(width: 16, height: 16)
        XCTAssertFalse(try rig.frame(), "the composite cannot be created")
        XCTAssertGreaterThan(rig.compositor.renderCacheEpoch, epoch)
        rig.compositor.faultInjection = RenderFaultInjection()
        rig.compositor.resetRenderHealth()
        try expect(rig, layer, renders: 1, "after the failed frame") {}
        assertAll(try rig.pixels(), equal: red, tolerance: 0, "")
    }

    /// Stack, group and solo/mute changes redraw the composite but never render a cached layer.
    func testStackGroupAndSoloMuteChangesRedrawTheCompositeOnly() throws {
        let rig = try Rig(gpu: try GPURig())
        let a = StillLayer("a", color: red), b = StillLayer("b", color: Pixel(0, 0, 0.5, 0.5))
        let ida = try rig.add(a)
        let idb = try rig.add(b)
        try rig.apply()
        try rig.frames(3)
        XCTAssertTrue(rig.compositor.compositeReused)
        let steps: [(String, () throws -> Void)] = [
            ("reorder", { try rig.stack.move(idb, to: 0); try rig.apply() }),
            ("group", { _ = try rig.stack.makeGroup([ida, idb], settings: LayerGroupSettings(name: "G", opacity: 0.5)); try rig.apply() }),
            ("mute", { rig.overlay { (o: inout LayerSoloMute) in o.setMute(true, layer: ida) } }),
            ("solo", { rig.overlay { (o: inout LayerSoloMute) in o.setSolo(true, layer: ida) } }),
            ("clear", { rig.overlay { (o: inout LayerSoloMute) in o.clear() } }),
        ]
        for (name, step) in steps {
            let before = try rig.bytes()
            try step()
            try rig.frame()
            XCTAssertFalse(rig.compositor.compositeReused, "\(name): composite redrawn")
            XCTAssertNotEqual(try rig.bytes(), before, "\(name): shows")
            try rig.frame()
            XCTAssertTrue(rig.compositor.compositeReused, "\(name): reused again on the next frame")
        }
        XCTAssertEqual(a.renders, 1, "never rendered again")
        XCTAssertEqual(b.renders, 1)
    }

    /// A hidden static layer stays cached; un-hiding draws its cached picture at once (spec clarification).
    func testAHiddenStaticLayerStaysCachedAndReappearsAtOnce() throws {
        let rig = try Rig(gpu: try GPURig())
        let layer = StillLayer("s", color: red)
        let id = try rig.add(layer)
        try rig.apply()
        try rig.frames(2)
        rig.overlay { (o: inout LayerSoloMute) in o.setMute(true, layer: id) }
        try rig.frames(5)
        assertAll(try rig.pixels(), equal: .zero, tolerance: 0, "muted")
        XCTAssertTrue(rig.compositor.wasReused(layer: 0), "hidden but cached")
        rig.overlay { (o: inout LayerSoloMute) in o.clear() }
        try rig.frame()
        assertAll(try rig.pixels(), equal: red, tolerance: 0, "back at once")
        XCTAssertEqual(layer.renders, 1)
    }

    // MARK: - US4: dynamic layers (CMP-013-S4)

    func testDynamicAndUndeclaredLayersRenderEveryFrame() throws {
        let rig = try Rig(gpu: try GPURig())
        let flags: [(String, LayerRenderDependencies)] = [
            ("time", LayerRenderDependencies(time: true)),
            ("audio", LayerRenderDependencies(audio: true)),
            ("modulation", LayerRenderDependencies(modulation: true)),
            ("external input", LayerRenderDependencies(externalInput: true)),
        ]
        var declared: [StillLayer] = []
        for (name, d) in flags {
            let layer = StillLayer(name, color: Pixel(0.1, 0.1, 0.1, 0.2), dependencies: d)
            declared.append(layer)
            try rig.add(layer)
        }
        let undeclared = UndeclaredLayer()
        try rig.add(undeclared)
        let generator = try LinearSpectrumGenerator(device: rig.gpu.device, pixelFormat: .rgba16Float,
                                                    configuration: LinearSpectrumConfiguration(barCount: .b16, background: LinearColor(red: 0, green: 0, blue: 0, alpha: 0)))
        let spectrum = try SpectrumLayerSource(device: rig.gpu.device, generator: generator)
        try rig.add(spectrum)
        try rig.apply()
        var spectrumRendered = 0
        for _ in 0..<10 {
            try rig.frame()
            XCTAssertEqual(rig.compositor.renderCacheHits, 0)
            XCTAssertFalse(rig.compositor.compositeReused, "a dynamic stack is recomposited every frame")
            if rig.compositor.outcome(ofLayer: 5) == .rendered && !rig.compositor.wasReused(layer: 5) { spectrumRendered += 1 }
        }
        for (k, layer) in declared.enumerated() { XCTAssertEqual(layer.renders, 10, "\(flags[k].0): 10 of 10") }
        XCTAssertEqual(undeclared.renders, 10, "unknown means render: 10 of 10")
        XCTAssertEqual(spectrumRendered, 10, "spectrum: 10 of 10")
    }

    // MARK: - US5: GPU time (CMP-013-S5; recorded, not asserted)

    /// Opt-in: `CMP013_BENCH=1`. Six static layers at 1920 × 1080, 120 frames, caching off vs on.
    func testRenderCacheBenchGPUTime() throws {
        guard ProcessInfo.processInfo.environment["CMP013_BENCH"] == "1" else { throw XCTSkip("bench: set CMP013_BENCH=1") }
        let gpu = try GPURig()
        var report: [String] = []
        for caching in [false, true] {
            let rig = try Rig(gpu: gpu, caching: caching, width: 1920, height: 1080)
            for k in 0..<6 {
                let layer = StillLayer("s\(k)", color: Pixel(Float(k) / 10, 0.2, 0.3, 0.5))
                try rig.add(layer, LayerCompositeSettings(opacity: 0.8, blendMode: k == 3 ? .screen : .normal,
                                                          transform: try LayerTransform(uniformScale: 0.9, rotation: Double(k) / 10)))
            }
            try rig.apply()
            try rig.frames(5)
            var samples: [Double] = []
            for _ in 0..<120 {
                let commands = try XCTUnwrap(gpu.queue.makeCommandBuffer())
                XCTAssertTrue(rig.compositor.composite(into: rig.output, commandBuffer: commands, presentationTimeNanoseconds: rig.time,
                                                       contentScale: 2, reduceFlashing: false, audio: .empty))
                rig.time += Self.frameNanoseconds
                commands.commit()
                commands.waitUntilCompleted()
                samples.append((commands.gpuEndTime - commands.gpuStartTime) * 1000)
            }
            samples.sort()
            let median = samples[samples.count / 2], p95 = samples[samples.count * 95 / 100]
            report.append(String(format: "caching %@: median %.3f ms, p95 %.3f ms", caching ? "on" : "off", median, p95))
        }
        print("CMP-013 bench (6 static layers, 1920 × 1080, 120 frames; Mac, not device evidence): " + report.joined(separator: "; "))
    }
}
#endif
