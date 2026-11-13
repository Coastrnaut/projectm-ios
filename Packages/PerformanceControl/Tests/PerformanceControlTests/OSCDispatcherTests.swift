// OSC-001-T05: applying decoded messages under the parameter policy (OSC-001-R6, R12, R13;
// contract C3). OSC-002-T10: bundles and the new argument types (OSC-002-R10; contract P3).
import ParameterGraph
@testable import PerformanceControl
import XCTest

final class OSCDispatcherTests: XCTestCase {
    private let id = OSCReceiverCatalog.testValueID

    private func packet(_ address: String, _ arguments: [OSCArgument]) -> [UInt8] {
        OSCEncoder.encode(OSCMessage(address: address, arguments: arguments))
    }

    private func makeDispatcher() -> (OSCDispatcher, ParameterStore) {
        let store = OSCReceiverCatalog.makeStore()
        return (OSCDispatcher(store: store, routes: OSCReceiverCatalog.routes), store)
    }

    func testCatalog() throws {
        let registry = try OSCReceiverCatalog.makeRegistry()
        let d = try XCTUnwrap(registry.descriptor(for: id))
        XCTAssertTrue(d.id.isWellFormed)
        XCTAssertEqual(d.defaultValue, .continuous(0))
        XCTAssertTrue(d.modulation.allowsExternalControl)
        XCTAssertFalse(d.modulation.isModulatable)
        XCTAssertEqual(OSCReceiverCatalog.routes, [OSCRoute(address: "/projectm/test", parameter: id)])
    }

    func testFloatAndIntAreApplied() {
        let (dispatcher, store) = makeDispatcher()
        XCTAssertEqual(dispatcher.handle(packet("/projectm/test", [.float(0.42)])), .applied(id, Double(Float(0.42))))
        XCTAssertEqual(store.double(id), Double(Float(0.42)))
        XCTAssertEqual(dispatcher.handle(packet("/projectm/test", [.int(1)])), .applied(id, 1))
        XCTAssertEqual(store.double(id), 1)
    }

    func testValuesAreClampedByTheStore() {
        let (dispatcher, store) = makeDispatcher()
        XCTAssertEqual(dispatcher.handle(packet("/projectm/test", [.float(7)])), .applied(id, 1))
        XCTAssertEqual(dispatcher.handle(packet("/projectm/test", [.float(-3)])), .applied(id, 0))
        XCTAssertEqual(store.double(id), 0)
    }

    func testNonFiniteIsRefusedAndChangesNothing() {
        let (dispatcher, store) = makeDispatcher()
        _ = dispatcher.handle(packet("/projectm/test", [.float(0.25)]))
        XCTAssertEqual(dispatcher.handle(packet("/projectm/test", [.float(.nan)])), .refusedByStore)
        XCTAssertEqual(dispatcher.handle(packet("/projectm/test", [.float(.infinity)])), .refusedByStore)
        XCTAssertEqual(store.double(id), 0.25)
    }

    func testIgnoredMessages() {
        let (dispatcher, store) = makeDispatcher()
        XCTAssertEqual(dispatcher.handle(packet("/projectm/other", [.float(0.5)])), .unknownAddress)
        XCTAssertEqual(dispatcher.handle(packet("/projectm/test", [.float(0.5), .float(0.6)])), .wrongArguments)
        XCTAssertEqual(dispatcher.handle(packet("/projectm/test", [])), .wrongArguments)
        XCTAssertEqual(dispatcher.handle([1, 2, 3]), .rejected(.notAligned))
        XCTAssertEqual(store.double(id), 0)
    }

    func testPolicyWithoutExternalControlIsNeverChanged() throws {
        let locked: ParameterID = "osc.receiver.locked"
        let registry = try ParameterRegistry(descriptors: [
            ParameterDescriptor(id: locked, displayName: "Locked", group: ParameterGroup(id: "osc.receiver", displayName: "OSC"),
                                unit: .none, kind: .continuous(minimum: 0, maximum: 1, defaultValue: 0.5), modulation: .none),
        ])
        let store = ParameterStore(registry: registry)
        let dispatcher = OSCDispatcher(store: store, routes: [OSCRoute(address: "/locked", parameter: locked),
                                                              OSCRoute(address: "/missing", parameter: "osc.receiver.missing")])
        XCTAssertEqual(dispatcher.handle(packet("/locked", [.float(1)])), .notExternallyControllable)
        XCTAssertEqual(dispatcher.handle(packet("/missing", [.float(1)])), .notExternallyControllable)
        XCTAssertEqual(store.double(locked), 0.5)
    }

    func testCountersAddUp() {
        let (dispatcher, _) = makeDispatcher()
        _ = dispatcher.handle(packet("/projectm/test", [.float(0.5)]))
        _ = dispatcher.handle(packet("/nope", [.float(0.5)]))
        _ = dispatcher.handle([])
        _ = dispatcher.handle([0x2F, 0, 0])
        dispatcher.noteOversized(5000)
        dispatcher.noteDroppedNonLocal()
        let c = dispatcher.counters
        XCTAssertEqual(c.received, 5)
        XCTAssertEqual(c.applied, 1)
        XCTAssertEqual(c.ignored, 1)
        XCTAssertEqual(c.rejected, 3)
        XCTAssertEqual(c.droppedNonLocal, 1)
        XCTAssertEqual(c.rejectedByReason, ["empty": 1, "notAligned": 1, "oversized": 1])
    }

    // MARK: OSC-002 bundles

    private func bundle(_ elements: [OSCPacket], timeTag: OSCTimeTag = .immediately) -> [UInt8] {
        OSCEncoder.encode(OSCPacket.bundle(OSCBundle(timeTag: timeTag, elements: elements)))
    }

    private func message(_ address: String, _ arguments: [OSCArgument]) -> OSCPacket {
        .message(OSCMessage(address: address, arguments: arguments))
    }

    func testBundleMessagesAreAppliedImmediatelyInPacketOrder() {
        let (dispatcher, store) = makeDispatcher()
        // A time tag far in the future is ignored in this row (OSC-006 schedules).
        let future = OSCTimeTag(seconds: 0xFFFF_FFFF, fraction: 0)
        let outcome = dispatcher.handle(bundle([
            message("/projectm/test", [.float(0.25)]),
            .bundle(OSCBundle(timeTag: .immediately, elements: [message("/nope", [.float(1)])])),
            message("/projectm/test", [.float(0.75)]),
        ], timeTag: future))
        XCTAssertEqual(outcome, .bundle([.applied(id, 0.25), .unknownAddress, .applied(id, 0.75)]))
        XCTAssertEqual(store.double(id), 0.75, "the last message in packet order wins")
        let c = dispatcher.counters
        XCTAssertEqual(c.received, 1)
        XCTAssertEqual(c.bundles, 1)
        XCTAssertEqual(c.applied, 2)
        XCTAssertEqual(c.ignored, 1)
        XCTAssertEqual(c.rejected, 0)
    }

    func testMalformedElementRejectsTheWholeBundle() {
        let (dispatcher, store) = makeDispatcher()
        let first = message("/projectm/test", [.float(0.5)])
        var bytes = bundle([first, message("/projectm/test", [.float(0.9)])])
        // The second element's size word follows the header, the first size word and the first element.
        let secondSize = 16 + 4 + OSCEncoder.encode(first).count
        bytes.replaceSubrange(secondSize..<(secondSize + 4), with: [0x7F, 0xFF, 0xFF, 0xFC])
        XCTAssertEqual(dispatcher.handle(bytes), .rejected(.invalidElementSize))
        XCTAssertEqual(store.double(id), 0, "nothing in a rejected bundle is applied")
        XCTAssertEqual(dispatcher.counters.rejectedByReason, ["invalidElementSize": 1])
        XCTAssertEqual(dispatcher.counters.bundles, 0)
    }

    func testEmptyBundleAppliesNothing() {
        let (dispatcher, _) = makeDispatcher()
        XCTAssertEqual(dispatcher.handle(bundle([])), .bundle([]))
        XCTAssertEqual(dispatcher.counters.bundles, 1)
        XCTAssertEqual(dispatcher.counters.applied + dispatcher.counters.ignored, 0)
    }

    func testDoubleAndInt64AreNumbersOtherNewTypesAreNot() {
        let (dispatcher, store) = makeDispatcher()
        XCTAssertEqual(dispatcher.handle(packet("/projectm/test", [.double(0.5)])), .applied(id, 0.5))
        XCTAssertEqual(dispatcher.handle(packet("/projectm/test", [.int64(1)])), .applied(id, 1))
        for argument: OSCArgument in [.true, .false, .nil, .impulse, .string("0.3"), .blob([1])] {
            XCTAssertEqual(dispatcher.handle(packet("/projectm/test", [argument])), .wrongArguments, "\(argument)")
        }
        XCTAssertEqual(store.double(id), 1)
    }
}
