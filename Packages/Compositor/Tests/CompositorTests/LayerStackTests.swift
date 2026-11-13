// CMP-002-T05 (US2): the layer stack's operations and refusals (CMP-002-R1 to R6, R12; S2). CPU
// only: runs on the Mac host and in the Linux shape.
import CameraLayer
import Compositor
import SpectrumLayers
import XCTest

final class LayerStackTests: XCTestCase {
    private let solid = LayerKind("test.solid")
    private func d(_ value: Double = 0) -> LayerDescriptor { LayerDescriptor(kind: solid, parameters: ["value": value]) }
    private func values(_ stack: LayerStack) -> [Double] {
        stack.entries.map { (e: LayerStackEntry) -> Double in e.descriptor.parameters["value"] ?? -1 }
    }

    func testAddAtTopBottomAndMiddleKeepsOrderAndDistinctIDs() throws {
        var stack = LayerStack()
        let a = try stack.add(d(1))            // [1]
        let b = try stack.add(d(2), at: 0)     // [2, 1]
        let c = try stack.add(d(3), at: 1)     // [2, 3, 1]
        XCTAssertEqual(values(stack), [2, 3, 1], "index 0 is the bottom")
        XCTAssertEqual(stack.ids, [b, c, a])
        XCTAssertEqual(Set([a, b, c]).count, 3)
        XCTAssertEqual(stack.index(of: c), 1)
        XCTAssertEqual(stack.entry(a)?.descriptor, d(1))
        XCTAssertEqual(stack.entry(a)?.settings, LayerCompositeSettings())
    }

    func testAddOutsideTheStackIsRefused() throws {
        var stack = LayerStack()
        try stack.add(d(1))
        let before = stack
        XCTAssertThrowsError(try stack.add(d(2), at: -1)) {
            XCTAssertEqual($0 as? LayerStackError, .indexOutOfRange(index: -1, validRange: 0...1))
        }
        XCTAssertThrowsError(try stack.add(d(2), at: 2)) {
            XCTAssertEqual($0 as? LayerStackError, .indexOutOfRange(index: 2, validRange: 0...1))
        }
        XCTAssertEqual(stack, before)
    }

    func testEightLayersAtMost() throws {
        var stack = LayerStack()
        var last = LayerInstanceID(rawValue: 0)
        for i in 0..<LayerStack.maximumLayerCount { last = try stack.add(d(Double(i))) }
        XCTAssertEqual(stack.count, 8)
        let before = stack
        XCTAssertThrowsError(try stack.add(d(9))) { XCTAssertEqual($0 as? LayerStackError, .stackFull(limit: 8)) }
        XCTAssertThrowsError(try stack.duplicate(last)) { XCTAssertEqual($0 as? LayerStackError, .stackFull(limit: 8)) }
        XCTAssertEqual(stack, before)
    }

    func testDuplicateGoesDirectlyAboveWithANewIDAndEqualContent() throws {
        var stack = LayerStack()
        let a = try stack.add(d(1))
        let b = try stack.add(d(2))
        let copy = try stack.duplicate(a)
        XCTAssertEqual(stack.ids, [a, copy, b])
        XCTAssertNotEqual(copy, a)
        XCTAssertEqual(stack.entry(copy)?.descriptor, stack.entry(a)?.descriptor)
        XCTAssertEqual(stack.entry(copy)?.settings, stack.entry(a)?.settings)
        let top = try stack.duplicate(b)
        XCTAssertEqual(stack.ids, [a, copy, b, top])
    }

    func testOneCameraPerStack() throws {
        var stack = LayerStack()
        let camera = try stack.add(LayerDescriptor(kind: .camera))
        try stack.add(LayerDescriptor(kind: .circularSpectrum))
        try stack.add(LayerDescriptor(kind: .circularSpectrum))   // spectra have no kind limit
        let before = stack
        XCTAssertThrowsError(try stack.add(LayerDescriptor(kind: .camera), at: 0)) {
            XCTAssertEqual($0 as? LayerStackError, .kindLimitReached(.camera))
        }
        XCTAssertThrowsError(try stack.duplicate(camera)) {
            XCTAssertEqual($0 as? LayerStackError, .kindLimitReached(.camera))
        }
        XCTAssertEqual(stack, before)
        try stack.remove(camera)
        XCTAssertNoThrow(try stack.add(LayerDescriptor(kind: .camera), at: 0), "a camera may come back once removed")
        XCTAssertNotEqual(LayerKind.camera, .circularSpectrum)
        XCTAssertNotEqual(LayerKind.circularSpectrum, .linearSpectrum)
    }

    func testRemoveAndIDsAreNeverReused() throws {
        var stack = LayerStack()
        let a = try stack.add(d(1))
        let b = try stack.add(d(2))
        let removed = try stack.remove(b)
        XCTAssertEqual(removed.id, b)
        XCTAssertEqual(stack.ids, [a])
        let before = stack
        XCTAssertThrowsError(try stack.remove(b)) { XCTAssertEqual($0 as? LayerStackError, .unknownLayer(b)) }
        XCTAssertThrowsError(try stack.duplicate(b)) { XCTAssertEqual($0 as? LayerStackError, .unknownLayer(b)) }
        XCTAssertThrowsError(try stack.move(b, to: 0)) { XCTAssertEqual($0 as? LayerStackError, .unknownLayer(b)) }
        XCTAssertEqual(stack, before)
        let c = try stack.add(d(3))
        XCTAssertGreaterThan(c, b, "a removed ID is never handed out again")
    }

    func testMoveToEveryIndex() throws {
        var stack = LayerStack()
        let a = try stack.add(d(1)), b = try stack.add(d(2)), c = try stack.add(d(3))
        try stack.move(a, to: 2)
        XCTAssertEqual(stack.ids, [b, c, a])
        try stack.move(a, to: 0)
        XCTAssertEqual(stack.ids, [a, b, c])
        try stack.move(c, to: 1)
        XCTAssertEqual(stack.ids, [a, c, b])
        let before = stack
        try stack.move(c, to: 1)
        XCTAssertEqual(stack, before, "moving to its own index is a no-op")
        XCTAssertThrowsError(try stack.move(c, to: 3)) {
            XCTAssertEqual($0 as? LayerStackError, .indexOutOfRange(index: 3, validRange: 0...2))
        }
        XCTAssertThrowsError(try stack.move(c, to: -1)) {
            XCTAssertEqual($0 as? LayerStackError, .indexOutOfRange(index: -1, validRange: 0...2))
        }
        XCTAssertEqual(stack, before)
    }

    func testEqualityComparesEntriesNotTheIDCounter() throws {
        var a = LayerStack()
        var b = LayerStack()
        try a.add(d(1))
        try b.add(d(1))
        XCTAssertEqual(a, b)
        let extra = try b.add(d(2))
        try b.remove(extra)
        XCTAssertEqual(a, b, "same entries, different counters")
        var c = a
        try c.add(d(2))
        XCTAssertNotEqual(a, c)
        XCTAssertEqual(LayerKind("x", maximumInstances: -3).maximumInstances, 0)
        XCTAssertEqual(LayerInstanceID(rawValue: 7).description, "layer#7")
    }
}
