// MIDI-002-T09 (MIDI-002-R1, R2, R5, R11): the shared input's lifecycle with the scripted provider (open once,
// connect exactly the requested sources, deliver only while open and connected, stop discards), the Linux
// provider (unavailable), and — where CoreMIDI exists — the system receive block walking a real
// `MIDIEventList` built with CoreMIDI's own helpers (no hardware needed).
#if canImport(CoreMIDI)
import CoreMIDI
#endif
@testable import PerformanceControl
import XCTest

final class MIDIInputServiceTests: XCTestCase {
    private let keys: MIDIEndpointID = .unique(0x10)
    private let pads: MIDIEndpointID = .unique(0x20)

    private func drain(_ service: MIDIInputService) -> [MIDIEvent] {
        var out: [MIDIEvent] = []
        service.ring.drain(into: &out, maxCount: 512)
        return out
    }

    func testStartConnectsTheRequestedSourcesAndStopClosesIdempotently() {
        let provider = ScriptedMIDIInputProvider()
        let service = MIDIInputService(provider: provider)
        XCTAssertEqual(service.state, .off)
        XCTAssertFalse(provider.send([0xB0, 7, 1], timestamp: 1), "closed: nothing delivered")

        service.start(sources: [keys])
        XCTAssertEqual(service.state, .receiving)
        XCTAssertEqual(provider.connectedSources, [keys])
        service.start(sources: [keys, pads])
        XCTAssertEqual(provider.openCount, 1, "a second start does not reopen")
        XCTAssertEqual(provider.connectedSources, [keys, pads])
        service.updateSources([pads])
        XCTAssertEqual(provider.connectedSources, [pads], "exactly the listed sources")

        XCTAssertTrue(provider.send([0xB0, 7, 100, 0x90, 60, 100], timestamp: 5))
        XCTAssertEqual(drain(service), [MIDIEvent(kind: .controlChange, number: 7, value: 100, timestamp: 5),
                                        MIDIEvent(kind: .noteOn, number: 60, value: 100, timestamp: 5)])

        provider.send([0xB0, 7, 1], timestamp: 6)
        service.stop()
        XCTAssertEqual(service.state, .off)
        XCTAssertEqual(service.ring.availableToRead, 0, "unread events are discarded on stop")
        XCTAssertTrue(provider.connectedSources.isEmpty)
        XCTAssertFalse(provider.send([0xB0, 7, 2], timestamp: 7), "nothing after stop")
        service.stop()
        XCTAssertEqual(provider.closeCount, 1, "stop is idempotent")
        service.updateSources([keys])
        XCTAssertTrue(provider.connectedSources.isEmpty, "updates are ignored while off")
    }

    func testNoConnectedSourceMeansNothingIsReceived() {
        let provider = ScriptedMIDIInputProvider()
        let service = MIDIInputService(provider: provider)
        service.start(sources: [])
        XCTAssertEqual(service.state, .receiving)
        XCTAssertFalse(provider.send([0x90, 60, 1], timestamp: 1))
        XCTAssertTrue(drain(service).isEmpty)
    }

    func testUnavailableOpenIsReportedAndRetriedByTheNextStart() {
        let provider = ScriptedMIDIInputProvider()
        provider.failOpen(code: -10_830)
        let service = MIDIInputService(provider: provider)
        service.start(sources: [keys])
        XCTAssertEqual(service.state, .unavailable(code: -10_830))
        XCTAssertTrue(provider.connectedSources.isEmpty)
        provider.failOpen(code: nil)
        service.start(sources: [keys])
        XCTAssertEqual(service.state, .receiving)
        XCTAssertEqual(provider.openCount, 2)
    }

    func testThePlatformWithoutMIDIReportsUnavailable() {
        let service = MIDIInputService(provider: UnavailableMIDIInputProvider())
        service.start(sources: [keys])
        XCTAssertEqual(service.state, .unavailable(code: 0))
        service.stop()
        XCTAssertEqual(service.state, .off)
    }

    #if canImport(CoreMIDI)
    /// The system receive block decodes a two-packet event list (CC, then a note) in place, converts host time
    /// to nanoseconds, and delivers nothing while closed.
    func testSystemReceiveBlockWalksAnEventListInPlace() {
        let ring = MIDIEventRing(capacity: 16)
        let receiver = CoreMIDIInputProvider.Receiver(ring: ring)
        let size: Int = 1_024
        let raw = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 8)
        defer { raw.deallocate() }
        let list: UnsafeMutablePointer<MIDIEventList> = raw.bindMemory(to: MIDIEventList.self, capacity: 1)
        var packet: UnsafeMutablePointer<MIDIEventPacket> = MIDIEventListInit(list, ._1_0)
        var first: [UInt32] = [0x20B0_0764]
        var second: [UInt32] = [0x2090_3C64, 0x10F8_0000]
        let ticks: MIDITimeStamp = 48_000
        packet = MIDIEventListAdd(list, size, packet, ticks, 1, &first)
        packet = MIDIEventListAdd(list, size, packet, ticks * 2, 2, &second)   // a new time: a second packet
        XCTAssertEqual(list.pointee.numPackets, 2)

        receiver.receive(list)
        XCTAssertEqual(ring.availableToRead, 0, "closed: nothing delivered")
        receiver.isOpen.store(true, ordering: .releasing)
        receiver.receive(list)
        var out: [MIDIEvent] = []
        ring.drain(into: &out, maxCount: 16)
        var info = mach_timebase_info_data_t()
        _ = mach_timebase_info(&info)
        let expected: UInt64 = ticks * UInt64(info.numer) / UInt64(info.denom)
        XCTAssertEqual(out, [MIDIEvent(kind: .controlChange, number: 7, value: 100, timestamp: expected),
                             MIDIEvent(kind: .noteOn, number: 60, value: 100, timestamp: 2 * expected)])
        XCTAssertEqual(ring.clockCount, 1)
    }
    #endif
}
