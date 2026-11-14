// MIDI-011-T05 (MIDI-011-R1-R5, R7, R8; S1-S4): hot-plug recovery over the scripted MIDI system with handles and a
// manual scheduler (no clock, no threads). The acceptance fixture keeps exactly one live connection per present
// endpoint and none for absent ones at every step, delivers a message from A exactly once, and reports each loss
// (the app releases held keys on it). Also: unique-number collisions, a burst costs one reconcile, a reused handle,
// a refused connect, offline vs unwanted, close, and 20 cycles without growth. Pure Swift: runs on Linux too.
@testable import PerformanceControl
import XCTest

final class MIDIHotplugTests: XCTestCase {
    private static let aNumber: Int32 = 0x0A0A
    private static let bNumber: Int32 = 0x0B0B
    private let a: MIDIEndpointID = .unique(MIDIHotplugTests.aNumber)
    private let b: MIDIEndpointID = .unique(MIDIHotplugTests.bNumber)

    private static func source(_ number: Int32, _ name: String) -> MIDIEndpointRecord {
        MIDIEndpointRecord(uniqueID: number, direction: .source, displayName: name,
                           endpointName: "Port 1", entityName: name, deviceName: name)
    }

    private static let recordA: MIDIEndpointRecord = source(aNumber, "Keys A")
    private static let recordB: MIDIEndpointRecord = source(bNumber, "Pads B")
    private static let output = MIDIEndpointRecord(uniqueID: 0x0C0C, direction: .destination, displayName: "Synth")

    private struct Fixture {
        let system: ScriptedMIDISourceSystem
        let scheduler: ManualMIDIScheduler
        let provider: ScriptedMIDISourceInputProvider
        let service: MIDIInputService
        var subscriptions: MIDISourceSubscriptions { provider.subscriptions }
    }

    private func makeFixture(records: [MIDIEndpointRecord] = [recordA, recordB, output]) -> Fixture {
        let system = ScriptedMIDISourceSystem(records: records)
        let scheduler = ManualMIDIScheduler()
        let provider = ScriptedMIDISourceInputProvider(system: system, scheduler: scheduler.scheduler)
        return Fixture(system: system, scheduler: scheduler, provider: provider, service: MIDIInputService(provider: provider))
    }

    private func drainCount(_ service: MIDIInputService) -> Int {
        var out: [MIDIEvent] = []
        return service.ring.drain(into: &out, maxCount: 512)
    }

    /// One live connection per present endpoint, none for absent ones, one delivery per message from each present.
    private func assertOneListener(_ f: Fixture, present: Set<Int32>, _ step: String, line: UInt = #line) {
        for number in [Self.aNumber, Self.bNumber] {
            let expected: Int = present.contains(number) ? 1 : 0
            XCTAssertEqual(f.system.liveConnections(uniqueID: number), expected, step + ": connections " + String(number), line: line)
            XCTAssertEqual(f.provider.send([0x90, 60, 100], from: number, timestamp: 1), expected, step + ": deliveries", line: line)
            XCTAssertEqual(drainCount(f.service), expected, step + ": events in the ring", line: line)
            if present.contains(number) {
                XCTAssertEqual(f.subscriptions.activeHandles[.unique(number)], f.system.handles(uniqueID: number).last,
                               step + ": registry holds the current handle", line: line)
            }
            f.provider.send([0x80, 60, 0], from: number, timestamp: 2)
            _ = drainCount(f.service)
        }
        XCTAssertEqual(f.system.totalConnections, present.count, step + ": no stray connection", line: line)
        XCTAssertEqual(f.subscriptions.activeHandles.count, present.count, step + ": registry size", line: line)
    }

    // MARK: S1 — the row's acceptance

    func testDisconnectAndReconnectFixtureYieldsOneLiveListenerPerEndpoint() {
        let f = makeFixture()
        f.service.start(sources: [a, b])
        assertOneListener(f, present: [Self.aNumber, Self.bNumber], "1 connect both")
        XCTAssertEqual(f.service.sourceLossCount, 0)

        // Remove A (the app's discovery would also drop it from the wanted set later; the input does not wait for it).
        let oldA: UInt32 = f.system.handles(uniqueID: Self.aNumber)[0]
        f.system.unplug(uniqueIDs: [Self.aNumber])
        XCTAssertEqual(f.scheduler.runAll(), 1)
        assertOneListener(f, present: [Self.bNumber], "2 remove A")
        XCTAssertEqual(f.service.sourceLossCount, 1, "A's loss is reported (held keys released)")
        f.service.updateSources([b])
        assertOneListener(f, present: [Self.bNumber], "2b discovery drops A")

        // Re-add A with a new handle and the same unique number.
        f.system.plug([Self.recordA])
        XCTAssertNotEqual(f.system.handles(uniqueID: Self.aNumber)[0], oldA, "the system issued a new handle")
        _ = f.scheduler.runAll()
        f.service.updateSources([a, b])
        assertOneListener(f, present: [Self.aNumber, Self.bNumber], "3 re-add A")
        XCTAssertEqual(f.service.sourceLossCount, 1, "a return is not a loss")

        // Repeated setup notifications with nothing changed: no connect or disconnect.
        let connects: Int = f.system.connectCalls
        let disconnects: Int = f.system.disconnectCalls
        f.system.signal(times: 5)
        XCTAssertEqual(f.scheduler.runAll(), 1, "one reconcile for the burst")
        f.service.updateSources([a, b])
        XCTAssertEqual(f.system.connectCalls, connects)
        XCTAssertEqual(f.system.disconnectCalls, disconnects)
        assertOneListener(f, present: [Self.aNumber, Self.bNumber], "4 repeated notifications")

        // B removed and re-added twice: once with a reconcile in between, once inside a single burst (discovery's
        // list never changes, so only the input's own reconcile repairs it).
        f.system.unplug(uniqueIDs: [Self.bNumber])
        _ = f.scheduler.runAll()
        assertOneListener(f, present: [Self.aNumber], "5 remove B")
        f.system.plug([Self.recordB])
        _ = f.scheduler.runAll()
        assertOneListener(f, present: [Self.aNumber, Self.bNumber], "6 re-add B")
        f.system.unplug(uniqueIDs: [Self.bNumber])
        f.system.plug([Self.recordB])
        XCTAssertEqual(f.scheduler.pendingCount, 1, "removal and add coalesce into one reconcile")
        _ = f.scheduler.runAll()
        assertOneListener(f, present: [Self.aNumber, Self.bNumber], "7 quick replug of B")
        XCTAssertEqual(f.service.sourceLossCount, 3, "each of B's disappearances is a loss")
    }

    /// The system reused the handle on a quick replug: the removal mark still forces one fresh connection.
    func testAReusedHandleIsReconnectedOnce() {
        let f = makeFixture()
        f.service.start(sources: [a, b])
        let handle: UInt32 = f.system.handles(uniqueID: Self.aNumber)[0]
        f.system.unplug(uniqueIDs: [Self.aNumber])
        f.system.plug(Self.recordA, handle: handle)
        _ = f.scheduler.runAll()
        assertOneListener(f, present: [Self.aNumber, Self.bNumber], "same handle back")
        XCTAssertEqual(f.service.sourceLossCount, 1)
        XCTAssertEqual(f.system.connectCalls, 3, "A connected again exactly once")
    }

    // MARK: S2 — collision fallback

    func testCollidingUniqueNumbersFallBackToOneConnectionEach() {
        let first: MIDIEndpointRecord = Self.source(0x77, "Twin One")
        let second: MIDIEndpointRecord = Self.source(0x77, "Twin Two")
        let f = makeFixture(records: [first, second])
        let ids: [MIDIEndpointID] = MIDIEndpointList.make(from: [first, second]).endpoints.map { (e: MIDIEndpoint) -> MIDIEndpointID in e.id }
        XCTAssertTrue(ids.allSatisfy { (id: MIDIEndpointID) -> Bool in id.isFallback })
        XCTAssertEqual(Set(ids).count, 2)
        f.service.start(sources: Set(ids))
        XCTAssertEqual(f.system.liveConnections(uniqueID: 0x77), 2, "one per endpoint")
        XCTAssertEqual(Set(f.subscriptions.activeHandles.values).count, 2, "each handle connected once")
        f.system.signal()
        _ = f.scheduler.runAll()
        XCTAssertEqual(f.system.connectCalls, 2)
        XCTAssertEqual(f.provider.send([0xB0, 7, 1], from: 0x77, timestamp: 1), 2, "both twins deliver, each once")
    }

    // MARK: S3 — burst

    func testABurstCostsOneReconcile() {
        let f = makeFixture()
        f.service.start(sources: [a, b])
        let before: Int = f.subscriptions.reconcileCount
        f.system.signal(times: 50)
        XCTAssertEqual(f.scheduler.pendingCount, 1)
        XCTAssertEqual(f.scheduler.runAll(), 1)
        XCTAssertEqual(f.subscriptions.reconcileCount, before + 1)
        XCTAssertEqual(f.subscriptions.absorbedSignals, 49)
        f.system.signal()
        XCTAssertEqual(f.scheduler.pendingCount, 1, "a signal after the reconcile schedules the next one")
    }

    // MARK: S4 — no leak

    func testTwentyCyclesLeaveOneConnectionPerEndpoint() {
        let f = makeFixture()
        f.service.start(sources: [a, b])
        for _ in 0..<20 {
            f.system.unplug(uniqueIDs: [Self.aNumber])
            _ = f.scheduler.runAll()
            f.system.plug([Self.recordA])
            _ = f.scheduler.runAll()
        }
        XCTAssertEqual(f.system.totalConnections, 2)
        XCTAssertEqual(f.subscriptions.activeHandles.count, 2)
        XCTAssertEqual(f.system.connectCalls, 22, "two initial connects plus one per return")
        XCTAssertEqual(f.service.sourceLossCount, 20)
        XCTAssertEqual(f.subscriptions.reconcileCount, 41)
        assertOneListener(f, present: [Self.aNumber, Self.bNumber], "after 20 cycles")
    }

    // MARK: Edge cases

    func testARefusedConnectIsRetriedByTheNextReconcile() {
        let f = makeFixture()
        f.system.refuseConnects(uniqueID: Self.aNumber, true)
        f.service.start(sources: [a, b])
        XCTAssertNil(f.subscriptions.activeHandles[a], "not counted as connected")
        XCTAssertEqual(f.system.liveConnections(uniqueID: Self.aNumber), 0)
        f.system.refuseConnects(uniqueID: Self.aNumber, false)
        f.system.signal()
        _ = f.scheduler.runAll()
        assertOneListener(f, present: [Self.aNumber, Self.bNumber], "retried")
    }

    func testOfflineIsALossButUnwantedIsNot() {
        let f = makeFixture()
        f.service.start(sources: [a, b])
        f.service.updateSources([b])
        assertOneListener(f, present: [Self.bNumber], "A unwanted")
        XCTAssertEqual(f.service.sourceLossCount, 0)
        f.system.setOffline(uniqueID: Self.bNumber, true)
        _ = f.scheduler.runAll()
        XCTAssertEqual(f.system.liveConnections(uniqueID: Self.bNumber), 0)
        XCTAssertEqual(f.service.sourceLossCount, 1)
        f.system.setOffline(uniqueID: Self.bNumber, false)
        _ = f.scheduler.runAll()
        assertOneListener(f, present: [Self.bNumber], "B online again")
    }

    func testStopDropsEveryConnectionAndIgnoresLaterNotifications() {
        let f = makeFixture()
        f.service.start(sources: [a, b])
        f.service.stop()
        XCTAssertEqual(f.system.totalConnections, 0)
        XCTAssertTrue(f.subscriptions.activeHandles.isEmpty)
        f.system.unplug(uniqueIDs: [Self.aNumber])
        f.system.plug([Self.recordA])
        XCTAssertEqual(f.scheduler.pendingCount, 0, "closed: nothing scheduled")
        f.service.start(sources: [a, b])
        assertOneListener(f, present: [Self.aNumber, Self.bNumber], "restarted")
    }

    /// A reconcile scheduled before a stop does nothing after it.
    func testAReconcileScheduledBeforeStopDoesNothing() {
        let f = makeFixture()
        f.service.start(sources: [a, b])
        f.system.signal()
        f.service.stop()
        let connects: Int = f.system.connectCalls
        _ = f.scheduler.runAll()
        XCTAssertEqual(f.system.connectCalls, connects)
        XCTAssertEqual(f.system.totalConnections, 0)
    }

    /// The fixture can see a duplicate subscription (so the assertions above are meaningful).
    func testTheFixtureMakesDuplicatesVisible() {
        let system = ScriptedMIDISourceSystem(records: [Self.recordA])
        let ring = MIDIEventRing()
        let provider = ScriptedMIDISourceInputProvider(system: system, scheduler: ManualMIDIScheduler().scheduler)
        _ = provider.open(into: ring)
        let handle: UInt32 = system.handles(uniqueID: Self.aNumber)[0]
        XCTAssertTrue(system.connect(handle))
        XCTAssertTrue(system.connect(handle))
        XCTAssertEqual(provider.send([0x90, 60, 1], from: Self.aNumber, timestamp: 1), 2)
        var out: [MIDIEvent] = []
        XCTAssertEqual(ring.drain(into: &out, maxCount: 8), 2)
    }

    /// The pure registry alone: lost ⊆ disconnected, entries follow the snapshot.
    func testRegistryReportsLostSubsetOfDisconnected() {
        var registry = MIDISubscriptionRegistry()
        var live: Set<UInt32> = []
        let connect: (UInt32) -> Bool = { (h: UInt32) -> Bool in live.insert(h).inserted }
        let disconnect: (UInt32) -> Void = { (h: UInt32) -> Void in live.remove(h) }
        let one: [MIDISourceSnapshot] = [MIDISourceSnapshot(handle: 1, record: Self.recordA), MIDISourceSnapshot(handle: 2, record: Self.recordB)]
        var result: MIDIReconcileResult = registry.reconcile(wanted: [a, b], snapshot: one, connect: connect, disconnect: disconnect)
        XCTAssertEqual(result.connected, [a, b])
        let two: [MIDISourceSnapshot] = [MIDISourceSnapshot(handle: 3, record: Self.recordA), MIDISourceSnapshot(handle: 2, record: Self.recordB)]
        result = registry.reconcile(wanted: [b], snapshot: two, connect: connect, disconnect: disconnect)
        XCTAssertEqual(result.disconnected, [a])
        XCTAssertEqual(result.lost, [a], "A's handle changed")
        XCTAssertTrue(result.lost.isSubset(of: Set(result.disconnected)))
        XCTAssertEqual(registry.entries, [b: 2])
        XCTAssertEqual(live, [2])
    }
}
