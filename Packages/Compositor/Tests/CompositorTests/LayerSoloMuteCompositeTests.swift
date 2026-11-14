// CMP-012-T05, T07, T08, T09: solo and mute through the real Metal compositor (CMP-012-R3 to R12; S1-S4,
// S6). Output 96 × 64 (`rgba16Float`, linear premultiplied). References are drawn by the same compositor
// from the stack the overlay should be equivalent to (only the soloed layers, or without the muted ones),
// so equality is bit for bit. `BoxLayer` (LayerGroupCompositeTests) draws one opaque rectangle. The scene
// document side of the acceptance is SceneFormat's SceneSoloMuteTests. Skipped without a Metal device.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Compositor
import Foundation
import Metal
import XCTest

final class LayerSoloMuteCompositeTests: XCTestCase {
    private static let w = 96, h = 64
    private static let kind = LayerKind("cmp012.layer")
    private static let frame: UInt64 = 16_666_667

    private static func red() -> BoxLayer { BoxLayer("red", color: Pixel(1, 0, 0, 1), x: 8, y: 8, width: 40, height: 30) }
    private static func green() -> BoxLayer { BoxLayer("green", color: Pixel(0, 1, 0, 1), x: 28, y: 18, width: 40, height: 30) }
    private static func blue() -> BoxLayer { BoxLayer("blue", color: Pixel(0, 0, 1, 1), x: 48, y: 28, width: 40, height: 30) }

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
            output = try gpu.output(width: LayerSoloMuteCompositeTests.w, height: LayerSoloMuteCompositeTests.h)
        }

        @discardableResult
        func add(_ layer: any LayerSource, _ settings: LayerCompositeSettings = LayerCompositeSettings()) throws -> LayerInstanceID {
            let id = try stack.add(LayerDescriptor(kind: LayerSoloMuteCompositeTests.kind), settings: settings)
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

        /// Draws `frames` frames (the stack is applied first) and reads the last one back.
        func render(frames: Int = 2) throws -> [Pixel] {
            try apply()
            return try draw(frames: frames)
        }

        /// Draws without applying.
        func draw(frames: Int = 1) throws -> [Pixel] {
            for _ in 0..<frames {
                try gpu.frame(compositor, into: output, time: time)
                time += LayerSoloMuteCompositeTests.frame
            }
            return try gpu.read(output)
        }

        func overlay(_ edit: (inout LayerSoloMute) -> Void) {
            var o = compositor.soloMute
            edit(&o)
            compositor.setSoloMute(o)
        }
    }

    /// The same compositor path for a plain stack of `layers` (the reference).
    private func reference(_ layers: [(any LayerSource, LayerCompositeSettings)], group: LayerGroupSettings? = nil) throws -> [Pixel] {
        let rig = try Rig()
        var ids: [LayerInstanceID] = []
        for (layer, settings) in layers { ids.append(try rig.add(layer, settings)) }
        if let group { try rig.stack.makeGroup(ids, settings: group) }
        return try rig.render()
    }

    private func three() throws -> (Rig, [LayerInstanceID], [BoxLayer]) {
        let rig = try Rig()
        let boxes = [Self.red(), Self.green(), Self.blue()]
        var ids: [LayerInstanceID] = []
        for b in boxes { ids.append(try rig.add(b)) }
        return (rig, ids, boxes)
    }

    // MARK: - US1: the acceptance (CMP-012-S1, S3)

    func testSoloIsolatesTheSelectedLayerAndClearingRestoresTheFrameBitForBit() throws {
        let (rig, ids, boxes) = try three()
        let stackBefore = rig.stack
        let before = try rig.render()
        let preparations = rig.compositor.layerPreparations
        let allocations = rig.compositor.pictureAllocations
        let misses = rig.compositor.texturePool.counters.misses

        rig.overlay { $0.setSolo(true, layer: ids[1]) }
        XCTAssertEqual((0..<3).map { rig.compositor.isHiddenBySoloMute(layer: $0) }, [true, false, true])
        let soloed = try rig.draw()
        XCTAssertEqual(soloed, try reference([(Self.green(), LayerCompositeSettings())]), "only the soloed layer, from the next frame")
        XCTAssertNotEqual(soloed, before)
        XCTAssertEqual(rig.compositor.soloMuteHiddenLayers, 2)
        XCTAssertEqual(rig.compositor.lastFlashGain, 1, accuracy: 1e-6)
        XCTAssertEqual(rig.compositor.appliedStack, stackBefore, "the stack (saved settings) is unchanged during the solo")
        XCTAssertEqual(rig.stack.entries, stackBefore.entries)

        // Two solos: a union, in stack order (green over red where they overlap).
        rig.overlay { $0.setSolo(true, layer: ids[0]) }
        XCTAssertEqual(try rig.draw(), try reference([(Self.red(), LayerCompositeSettings()), (Self.green(), LayerCompositeSettings())]))

        rig.overlay { $0.clear() }
        XCTAssertEqual(try rig.draw(), before, "clearing restores the previous frame bit for bit")
        XCTAssertEqual(rig.compositor.soloMuteHiddenLayers, 0)
        XCTAssertEqual(rig.compositor.appliedStack, stackBefore)
        for k in 0..<3 { XCTAssertEqual(rig.compositor.outcome(ofLayer: k), .rendered) }
        XCTAssertEqual(rig.compositor.layerPreparations, preparations, "no layer prepared by solo")
        XCTAssertEqual(rig.compositor.pictureAllocations, allocations, "no picture created by solo")
        XCTAssertEqual(rig.compositor.texturePool.counters.misses, misses)
        _ = boxes
    }

    // MARK: - US2: mute (CMP-012-S3, S4)

    func testMuteHidesALayerThatKeepsRenderingAndUnmuteRestoresTheFrame() throws {
        let (rig, ids, _) = try three()
        let before = try rig.render()
        let preparations = rig.compositor.layerPreparations
        let allocations = rig.compositor.pictureAllocations

        rig.overlay { $0.setMute(true, layer: ids[2]) }
        for _ in 0..<3 {
            XCTAssertEqual(try rig.draw(), try reference([(Self.red(), LayerCompositeSettings()), (Self.green(), LayerCompositeSettings())]),
                           "= the stack without the muted layer")
            XCTAssertEqual(rig.compositor.outcome(ofLayer: 2), .rendered, "the muted layer keeps rendering")
        }

        // Solo plus mute of the same layer: mute wins and the solo keeps the others hidden.
        rig.overlay { $0.setSolo(true, layer: ids[2]) }
        assertAll(try rig.draw(), equal: .zero, tolerance: 0, "a soloed and muted layer: nothing drawn")
        rig.overlay { $0.setSolo(false, layer: ids[2]) }

        rig.overlay { $0.setMute(false, layer: ids[2]) }
        XCTAssertTrue(rig.compositor.soloMute.isEmpty)
        XCTAssertEqual(try rig.draw(), before, "un-mute restores the previous frame bit for bit, at once")
        XCTAssertEqual(rig.compositor.layerPreparations, preparations, "no restart: 0 preparations")
        XCTAssertEqual(rig.compositor.pictureAllocations, allocations, "0 picture allocations")
    }

    /// CMP-012-R11: a fade keeps running under a mute; the overlay change itself has no fade.
    func testAnOpacityFadeKeepsRunningWhileMuted() throws {
        let rig = try Rig()
        let color = Pixel(0, 0.5, 0.25, 1)
        let id = try rig.add(SolidLayer("solid", color: color))
        _ = try rig.render()
        try rig.stack.setSettings(LayerCompositeSettings(opacity: 0.25), of: id)
        try rig.apply(try LayerOpacityTransition(duration: 0.1))
        _ = try rig.draw()
        rig.overlay { $0.setMute(true, layer: id) }
        var values: [Double] = []
        for _ in 0..<3 {
            assertAll(try rig.draw(), equal: .zero, tolerance: 0, "muted: nothing drawn")
            values.append(rig.compositor.shownOpacity(ofLayer: 0))
        }
        for k in 1..<values.count { XCTAssertLessThan(values[k], values[k - 1], "the fade advances while muted: \(values)") }
        rig.overlay { $0.setMute(false, layer: id) }
        let shown = try rig.draw()
        let opacity = Float(rig.compositor.shownOpacity(ofLayer: 0))
        XCTAssertLessThan(opacity, Float(values.last ?? 1))
        assertAll(shown, equal: color * opacity, tolerance: 0.002, "un-muted at once, at the fade's current value")
    }

    // MARK: - US3: groups (CMP-012-S2)

    func testSoloingAGroupShowsOnlyItsLayers() throws {
        let rig = try Rig()
        let a = try rig.add(Self.red())
        let b = try rig.add(Self.green())
        try rig.add(Self.blue())
        let group = try rig.stack.makeGroup([a, b])
        _ = try rig.render()
        rig.overlay { $0.setSolo(true, group: group) }
        XCTAssertEqual(try rig.draw(), try reference([(Self.red(), LayerCompositeSettings()), (Self.green(), LayerCompositeSettings())]))
    }

    func testSoloingAChildOfAMovedFadedGroupKeepsTheGroupsPlacementAndOpacity() throws {
        let settings = LayerGroupSettings(opacity: 0.5, transform: try LayerTransform(translation: LayerPoint(x: 0.1, y: 0.05), rotation: 0.2))
        let rig = try Rig()
        try rig.add(SolidLayer("backdrop", color: Pixel(0.25, 0.25, 0.25, 1)))
        let a = try rig.add(Self.red())
        let b = try rig.add(Self.green())
        try rig.stack.makeGroup([a, b], settings: settings)
        _ = try rig.render()
        rig.overlay { $0.setSolo(true, layer: b) }
        let soloed = try rig.draw()
        XCTAssertEqual(rig.compositor.isolatedGroupDraws, 1, "opacity 0.5: still drawn as one picture")
        XCTAssertEqual(soloed, try reference([(Self.green(), LayerCompositeSettings())], group: settings),
                       "the group's placement and opacity still apply to the soloed child; the backdrop is hidden")
        XCTAssertGreaterThan(soloed[30 * Self.w + 50].y, 0.4)
        XCTAssertEqual(soloed[30 * Self.w + 50].y, 0.5, accuracy: 0.01, "green at the group's opacity")
    }

    func testAHiddenScreenChildNoLongerIsolatesItsGroup() throws {
        let rig = try Rig()
        let a = try rig.add(Self.red())
        let s = try rig.add(Self.green(), LayerCompositeSettings(blendMode: .screen))
        try rig.stack.makeGroup([a, s])
        _ = try rig.render()
        XCTAssertEqual(rig.compositor.isolatedGroupDraws, 1, "a screen child isolates the group")
        rig.overlay { $0.setSolo(true, layer: a) }
        XCTAssertEqual(try rig.draw(), try reference([(Self.red(), LayerCompositeSettings())]))
        XCTAssertEqual(rig.compositor.isolatedGroupDraws, 0, "only visible layers decide isolation: flattened")
        XCTAssertEqual(rig.compositor.blendDraws, 0)
    }

    func testMutingAGroupHidesItsLayersWhichKeepRendering() throws {
        let rig = try Rig()
        let a = try rig.add(Self.red())
        let b = try rig.add(Self.green())
        try rig.add(Self.blue())
        let group = try rig.stack.makeGroup([a, b])
        let before = try rig.render()
        rig.overlay { $0.setMute(true, group: group) }
        XCTAssertEqual(try rig.draw(), try reference([(Self.blue(), LayerCompositeSettings())]))
        for k in 0..<2 { XCTAssertEqual(rig.compositor.outcome(ofLayer: k), .rendered) }
        rig.overlay { $0.setMute(false, group: group) }
        XCTAssertEqual(try rig.draw(), before)
    }

    func testASwitchedOffGroupStaysHiddenWhenAChildIsSoloed() throws {
        let rig = try Rig()
        try rig.add(Self.blue())
        let a = try rig.add(Self.red())
        try rig.stack.makeGroup([a], settings: LayerGroupSettings(isEnabled: false))
        _ = try rig.render()
        rig.overlay { $0.setSolo(true, layer: a) }
        assertAll(try rig.draw(), equal: .zero, tolerance: 0, "solo never overrides a saved enable flag")
        XCTAssertEqual(rig.stack.groups.first?.settings.isEnabled, false)
    }

    // MARK: - GPU time (CMP-012-S6; opt-in, Mac only, not device evidence)

    func testBench() throws {
        guard ProcessInfo.processInfo.environment["CMP012_BENCH"] == "1" else {
            throw XCTSkip("Set CMP012_BENCH=1 to measure GPU time with layers muted (Release, Mac; not device evidence).")
        }
        let gpu = try GPURig()
        let output = try gpu.output(.bgra8Unorm_srgb, width: 1920, height: 1080)
        var lines: [String] = []
        for muted in [0, 4] {
            var stack = LayerStack()
            var ids: [LayerInstanceID] = []
            for k in 0..<8 {
                let t = try LayerTransform(translation: LayerPoint(x: 0.02 * Double(k), y: 0), uniformScale: 0.7)
                ids.append(try stack.add(LayerDescriptor(kind: Self.kind), settings: LayerCompositeSettings(opacity: 0.8, transform: t)))
            }
            let compositor = try Compositor(device: gpu.device)
            let layer = (0..<8).map { (k: Int) -> SolidLayer in SolidLayer("bench \(k)", color: Pixel(0.1 * Float(k), 0.3, 0.4, 1)) }
            var next = 0
            try compositor.apply(stack) { (_: LayerStackEntry) throws(LayerSourceError) -> any LayerSource in
                defer { next += 1 }
                return layer[next]
            }
            var overlay = LayerSoloMute()
            for k in 0..<muted { overlay.setMute(true, layer: ids[2 * k]) }
            compositor.setSoloMute(overlay)
            var samples: [Double] = []
            for k in 0..<130 {
                let commands = try XCTUnwrap(gpu.queue.makeCommandBuffer())
                _ = compositor.composite(into: output, commandBuffer: commands, presentationTimeNanoseconds: UInt64(k) * Self.frame,
                                         contentScale: 2, reduceFlashing: false, audio: .empty)
                commands.commit()
                commands.waitUntilCompleted()
                if k >= 10 { samples.append((commands.gpuEndTime - commands.gpuStartTime) * 1000) }
            }
            samples.sort()
            lines.append("| 8 layers, \(muted) muted | " + String(format: "%.3f | %.3f", samples[samples.count / 2], samples[samples.count * 95 / 100])
                         + " | \(compositor.soloMuteHiddenLayers) |")
        }
        print("CMP-012 GPU time per frame, 1920 × 1080 (ms): | case | median | p95 | hidden layers |")
        for line in lines { print("CMP-012 bench: " + line) }
    }
}
#endif
