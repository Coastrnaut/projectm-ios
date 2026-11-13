// CMP-002-T07 (US1, the roadmap acceptance "Reordering overlapping red and blue layers changes
// topmost color"; CMP-002-S1) and T08 (US3, apply semantics; CMP-002-S3, S4). GPU tests at 64 × 64
// through the real Metal compositor; skipped without a Metal device.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Compositor
import Metal
import XCTest

/// Makes a `SolidLayer` per new entry from its parameters (r, g, b, a; `failPrepare` 1 fails its
/// prepare) and keeps only weak references, so tests can see a layer being released.
private final class SolidFactory {
    static let kind = LayerKind("test.solid")
    private(set) var calls = 0
    private var made: [LayerInstanceID: Weak] = [:]
    var failure: LayerSourceError?

    private final class Weak { weak var layer: SolidLayer?; init(_ l: SolidLayer) { layer = l } }

    static func solid(_ p: Pixel, failPrepare: Bool = false) -> LayerDescriptor {
        LayerDescriptor(kind: kind, parameters: ["r": Double(p.x), "g": Double(p.y), "b": Double(p.z), "a": Double(p.w),
                                                 "failPrepare": failPrepare ? 1 : 0])
    }

    func make(_ entry: LayerStackEntry) throws(LayerSourceError) -> any LayerSource {
        calls += 1
        if let failure { throw failure }
        let p = entry.descriptor.parameters
        let layer = SolidLayer("solid \(entry.id)", color: Pixel(Float(p["r"] ?? 0), Float(p["g"] ?? 0), Float(p["b"] ?? 0),
                                                                Float(p["a"] ?? 0)))
        layer.failPrepare = p["failPrepare"] == 1
        made[entry.id] = Weak(layer)
        return layer
    }

    func layer(_ id: LayerInstanceID) -> SolidLayer? { made[id]?.layer }
}

final class LayerStackApplyTests: XCTestCase {
    private let red = Pixel(1, 0, 0, 1)
    private let blue = Pixel(0, 0, 1, 1)
    private let green = Pixel(0, 1, 0, 1)

    private func apply(_ stack: LayerStack, _ compositor: Compositor, _ factory: SolidFactory) throws {
        try compositor.apply(stack) { (entry: LayerStackEntry) throws(LayerSourceError) -> any LayerSource in
            try factory.make(entry)
        }
    }

    // MARK: - US1: the acceptance

    func testReorderingRedAndBlueChangesTopmostColor() throws {
        let rig = try GPURig()
        let factory = SolidFactory()
        let compositor = try Compositor(device: rig.device)
        let output = try rig.output()
        var stack = LayerStack()
        let redID = try stack.add(SolidFactory.solid(red))
        let blueID = try stack.add(SolidFactory.solid(blue))   // on top: index 0 is the bottom
        try apply(stack, compositor, factory)
        try rig.frame(compositor, into: output, time: 1_000_000_000)
        assertAll(try rig.read(output), equal: blue, "blue on top of red")

        try stack.move(redID, to: 1)
        try apply(stack, compositor, factory)
        try rig.frame(compositor, into: output, time: 1_016_666_667)
        assertAll(try rig.read(output), equal: red, "red on top after the move")
        XCTAssertEqual(compositor.layerID(at: 0), blueID)
        XCTAssertEqual(compositor.layerID(at: 1), redID)
        XCTAssertEqual(factory.calls, 2, "a move creates no layer")
        XCTAssertEqual(factory.layer(redID)?.prepared.count, 1, "a move prepares nothing")
        XCTAssertEqual(factory.layer(blueID)?.prepared.count, 1)
    }

    // MARK: - US3: apply semantics

    func testAddingALayerPreparesOnlyTheNewOneAndAnEqualStackIsANoOp() throws {
        let rig = try GPURig()
        let factory = SolidFactory()
        let compositor = try Compositor(device: rig.device)
        let output = try rig.output()
        var stack = LayerStack()
        let a = try stack.add(SolidFactory.solid(red))
        let b = try stack.add(SolidFactory.solid(Pixel(0, 0, 0.5, 0.5)))
        try apply(stack, compositor, factory)
        try rig.frame(compositor, into: output, time: 1)
        XCTAssertEqual(compositor.layerPreparations, 2)

        let c = try stack.add(SolidFactory.solid(green), at: 1)
        try apply(stack, compositor, factory)
        XCTAssertEqual(factory.calls, 3, "only the new ID is created")
        XCTAssertEqual(compositor.layerPreparations, 3, "only the new layer is prepared, at apply")
        XCTAssertEqual(factory.layer(c)?.prepared, [try XCTUnwrap(LayerPictureDescriptor(width: 64, height: 64))])
        XCTAssertEqual(factory.layer(a)?.prepared.count, 1)
        XCTAssertEqual(factory.layer(b)?.prepared.count, 1)
        try rig.frame(compositor, into: output, time: 2)
        // half blue over opaque green: (0, 0, 0.5, 0.5) + (0, 1, 0, 1) × 0.5
        assertAll(try rig.read(output), equal: Pixel(0, 0.5, 0.5, 1), "new layer composited in the middle")
        for i in 0..<3 { XCTAssertEqual(compositor.outcome(ofLayer: i), .rendered) }

        let allocations = compositor.pictureAllocations
        let copy = stack
        try apply(copy, compositor, factory)
        XCTAssertEqual(factory.calls, 3, "an equal stack creates nothing")
        XCTAssertEqual(compositor.layerPreparations, 3, "an equal stack prepares nothing")
        XCTAssertEqual(compositor.pictureAllocations, allocations)
        XCTAssertEqual(compositor.appliedStack, stack)
    }

    func testRemovedLayerIsReleased() throws {
        let rig = try GPURig()
        let factory = SolidFactory()
        let compositor = try Compositor(device: rig.device)
        let output = try rig.output()
        var stack = LayerStack()
        try stack.add(SolidFactory.solid(red))
        let b = try stack.add(SolidFactory.solid(blue))
        try apply(stack, compositor, factory)
        try rig.frame(compositor, into: output, time: 1)
        XCTAssertNotNil(factory.layer(b))
        try stack.remove(b)
        try apply(stack, compositor, factory)
        XCTAssertNil(factory.layer(b), "the compositor holds no reference to a removed layer")
        XCTAssertEqual(compositor.layerCount, 1)
        try rig.frame(compositor, into: output, time: 2)
        assertAll(try rig.read(output), equal: red, "only red remains")
    }

    func testStackAppliedBeforeTheFirstFrameIsPreparedWithIt() throws {
        let rig = try GPURig()
        let factory = SolidFactory()
        let compositor = try Compositor(device: rig.device)
        var stack = LayerStack()
        let a = try stack.add(SolidFactory.solid(red))
        try apply(stack, compositor, factory)
        XCTAssertEqual(compositor.layerPreparations, 0, "no size yet")
        XCTAssertEqual(compositor.pictureAllocations, 0)
        XCTAssertEqual(compositor.outcome(ofLayer: 0), .notRendered)
        let output = try rig.output(width: 32, height: 16)
        try rig.frame(compositor, into: output, time: 1)
        XCTAssertEqual(factory.layer(a)?.prepared, [try XCTUnwrap(LayerPictureDescriptor(width: 32, height: 16))])
        assertAll(try rig.read(output), equal: red, "prepared and drawn on the first frame")
    }

    func testRefusedAppliesKeepThePreviousStack() throws {
        let rig = try GPURig()
        let factory = SolidFactory()
        let compositor = try Compositor(device: rig.device)
        let output = try rig.output()
        var stack = LayerStack()
        try stack.add(SolidFactory.solid(red))
        try stack.add(SolidFactory.solid(blue))
        try apply(stack, compositor, factory)
        try rig.frame(compositor, into: output, time: 1)
        let applied = stack

        // The factory fails for a new entry.
        var failing = stack
        try failing.add(SolidFactory.solid(green))
        factory.failure = .resourceUnavailable("test")
        XCTAssertThrowsError(try apply(failing, compositor, factory)) {
            XCTAssertEqual($0 as? CompositorError, .layerCreationFailed(index: 2, .resourceUnavailable("test")))
        }
        factory.failure = nil

        // The factory returns an object another entry already uses.
        var shared = stack
        try shared.add(SolidFactory.solid(green), at: 0)
        XCTAssertThrowsError(try compositor.apply(shared) { (_: LayerStackEntry) throws(LayerSourceError) -> any LayerSource in
            guard let existing = factory.layer(applied.ids[1]) else { throw .notReady }
            return existing
        }) { XCTAssertEqual($0 as? CompositorError, .duplicateLayer(index: 2)) }

        // Settings the compositor cannot draw yet (a transform until CMP-005; opacity: CMP-003).
        var faded = stack
        try faded.add(SolidFactory.solid(green),
                      settings: LayerCompositeSettings(transform: LayerTransform(a: 2, b: 0, c: 0, d: 1, tx: 0, ty: 0)))
        XCTAssertThrowsError(try apply(faded, compositor, factory)) {
            XCTAssertEqual($0 as? CompositorError, .unsupportedCompositeSettings(index: 2))
        }

        XCTAssertEqual(compositor.appliedStack, applied)
        XCTAssertEqual(compositor.layerCount, 2)
        XCTAssertEqual(compositor.layerPreparations, 2)
        try rig.frame(compositor, into: output, time: 2)
        assertAll(try rig.read(output), equal: blue, "the previous stack still draws")
    }

    func testFailedPrepareMakesOnlyThatLayerUnavailable() throws {
        let rig = try GPURig()
        let factory = SolidFactory()
        let compositor = try Compositor(device: rig.device)
        let output = try rig.output()
        var stack = LayerStack()
        try stack.add(SolidFactory.solid(red))
        try apply(stack, compositor, factory)
        try rig.frame(compositor, into: output, time: 1)
        try stack.add(SolidFactory.solid(blue, failPrepare: true))
        try apply(stack, compositor, factory)
        try rig.frame(compositor, into: output, time: 2)
        XCTAssertEqual(compositor.outcome(ofLayer: 0), .rendered)
        XCTAssertEqual(compositor.outcome(ofLayer: 1), .unavailable(.resourceUnavailable("test prepare failure")))
        assertAll(try rig.read(output), equal: red, "the unavailable layer is not drawn")
    }

    func testSteadyFramesAfterEditsCreateNoPictures() throws {
        let rig = try GPURig()
        let factory = SolidFactory()
        let compositor = try Compositor(device: rig.device)
        let output = try rig.output()
        var stack = LayerStack()
        let a = try stack.add(SolidFactory.solid(red))
        let b = try stack.add(SolidFactory.solid(blue))
        try apply(stack, compositor, factory)
        try rig.frame(compositor, into: output, time: 0)
        try stack.duplicate(a)
        try stack.move(b, to: 0)
        try stack.remove(a)
        try apply(stack, compositor, factory)
        let allocations = compositor.pictureAllocations
        let preparations = compositor.layerPreparations
        for i in 1...60 { try rig.frame(compositor, into: output, time: UInt64(i) * 16_666_667) }
        XCTAssertEqual(compositor.pictureAllocations, allocations, "no picture is created at a steady size (CMP-002-S4)")
        XCTAssertEqual(compositor.layerPreparations, preparations)
        assertAll(try rig.read(output), equal: red, "the duplicate of red is on top of blue")
    }

    func testReorderedLayerKeepsItsLastGoodPicture() throws {
        let rig = try GPURig()
        let compositor = try Compositor(device: rig.device)
        let output = try rig.output()
        let flaky = FailingLayer(color: red, fallback: .lastGoodFrame, failingFrames: [1])
        let under = SolidLayer("under", color: blue)
        var stack = LayerStack()
        let flakyID = try stack.add(LayerDescriptor(kind: LayerKind("test.flaky")))
        try stack.add(LayerDescriptor(kind: LayerKind("test.under")))
        let make = { (entry: LayerStackEntry) throws(LayerSourceError) -> any LayerSource in
            entry.id == flakyID ? flaky : under
        }
        try compositor.apply(stack, makeLayer: make)
        try rig.frame(compositor, into: output, time: 0)    // flaky draws red; blue on top
        try stack.move(flakyID, to: 1)
        try compositor.apply(stack, makeLayer: make)
        try rig.frame(compositor, into: output, time: 1)    // flaky fails: its last good red shows on top
        XCTAssertEqual(compositor.outcome(ofLayer: 1), .fallbackLastGood(.frameSkipped))
        assertAll(try rig.read(output), equal: red, "the last good picture survived the move")
    }

    func testApplyKeepsTheFlashHistory() throws {
        let rig = try GPURig()
        let compositor = try Compositor(device: rig.device)
        let output = try rig.output()
        let strobe = StrobeLayer()
        var stack = LayerStack()
        let strobeID = try stack.add(LayerDescriptor(kind: LayerKind("test.strobe")))
        let factory = SolidFactory()
        let make = { (entry: LayerStackEntry) throws(LayerSourceError) -> any LayerSource in
            entry.id == strobeID ? strobe : try factory.make(entry)
        }
        try compositor.apply(stack, makeLayer: make)
        // The strobe is white on even frame indices; the guard's gain matters on white frames.
        var time: UInt64 = 0
        func frame() throws { time += 16_666_667; try rig.frame(compositor, into: output, time: time, reduceFlashing: true) }
        for _ in 0...60 { try frame() }   // frames 0…60; 60 is white
        XCTAssertLessThan(compositor.lastFlashGain, 1, "the strobe is dimmed")

        try stack.add(SolidFactory.solid(Pixel(0, 0, 0, 0)), at: 0)   // a transparent layer below: same picture
        try compositor.apply(stack, makeLayer: make)
        try frame()   // 61, black
        try frame()   // 62, white
        XCTAssertLessThan(compositor.lastFlashGain, 1, "an apply keeps the guard's history (CMP-002-R14)")

        try frame()   // 63, black
        compositor.resetFlashHistory()   // control: a new scene forgets it
        try frame()   // 64, white
        XCTAssertEqual(compositor.lastFlashGain, 1, "control: a reset starts at full gain")
    }

    func testEmptyStackIsTransparentAndReleasesInitLayers() throws {
        let rig = try GPURig()
        weak var released: SolidLayer?
        let compositor: Compositor = try {
            let layer = SolidLayer("fixed", color: red)
            released = layer
            return try Compositor(device: rig.device, layers: [layer])
        }()
        let output = try rig.output()
        try rig.frame(compositor, into: output, time: 1)
        XCTAssertNil(compositor.layerID(at: 0), "init(device:layers:) layers have no stack ID")
        XCTAssertNil(compositor.appliedStack)
        let factory = SolidFactory()
        try apply(LayerStack(), compositor, factory)
        XCTAssertNil(released, "the first apply releases the init layers")
        XCTAssertEqual(compositor.layerCount, 0)
        try rig.frame(compositor, into: output, time: 2)
        assertAll(try rig.read(output), equal: .zero, "an empty stack is transparent")
    }
}
#endif
