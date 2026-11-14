// MIDIEndpointDiscoveryTests.swift — MIDI-001 acceptance with a scripted MIDI system and a manual scheduler:
// "Mock endpoints appear and disappear with stable IDs" (S1), identical devices (S2), bursts (S3),
// online/offline (S4), virtual and rename (US2), stop and unavailable (R7, R8), delivery on the scheduler
// (R12). No clock, no threads: every refresh runs inside `runAll()`.
import Synchronization
import XCTest
@testable import PerformanceControl

final class MIDIEndpointDiscoveryTests: XCTestCase {
    private final class Recorder: Sendable {
        private let updates = Mutex<[MIDIDiscoveryUpdate]>([])
        private let states = Mutex<[MIDIDiscoveryState]>([])
        var all: [MIDIDiscoveryUpdate] { updates.withLock { (u: inout [MIDIDiscoveryUpdate]) -> [MIDIDiscoveryUpdate] in u } }
        var stateLog: [MIDIDiscoveryState] { states.withLock { (s: inout [MIDIDiscoveryState]) -> [MIDIDiscoveryState] in s } }
        func add(_ update: MIDIDiscoveryUpdate) { updates.withLock { (u: inout [MIDIDiscoveryUpdate]) -> Void in u.append(update) } }
        func add(_ state: MIDIDiscoveryState) { states.withLock { (s: inout [MIDIDiscoveryState]) -> Void in s.append(state) } }
    }

    private struct Harness {
        let provider: ScriptedMIDIEndpointProvider
        let scheduler: ManualMIDIScheduler
        let discovery: MIDIEndpointDiscovery
        let recorder: Recorder
    }

    private func makeHarness(_ records: [MIDIEndpointRecord] = []) -> Harness {
        let provider = ScriptedMIDIEndpointProvider(records: records)
        let scheduler = ManualMIDIScheduler()
        let discovery = MIDIEndpointDiscovery(provider: provider, scheduler: scheduler.scheduler)
        let recorder = Recorder()
        discovery.onUpdate { (update: MIDIDiscoveryUpdate) -> Void in recorder.add(update) }
        discovery.onStateChange { (state: MIDIDiscoveryState) -> Void in recorder.add(state) }
        return Harness(provider: provider, scheduler: scheduler, discovery: discovery, recorder: recorder)
    }

    /// A USB controller: one input and one output.
    private func keys(_ base: Int32, name: String = "Keys") -> [MIDIEndpointRecord] {
        [MIDIEndpointRecord(uniqueID: base, direction: .source, displayName: name, endpointName: "Port 1",
                            entityName: name, deviceName: name),
         MIDIEndpointRecord(uniqueID: base + 1, direction: .destination, displayName: name, endpointName: "Port 1",
                            entityName: name, deviceName: name)]
    }

    private func ids(_ list: MIDIEndpointList) -> [MIDIEndpointID] {
        list.endpoints.map { (e: MIDIEndpoint) -> MIDIEndpointID in e.id }
    }

    // MARK: S1 — the acceptance

    func testMockEndpointsAppearAndDisappearWithStableIDs() {
        let h: Harness = makeHarness()
        h.discovery.start()
        XCTAssertEqual(h.discovery.state, .listening)
        h.scheduler.runAll()
        XCTAssertEqual(h.recorder.all.count, 1)
        XCTAssertTrue(h.recorder.all[0].isInitial)
        XCTAssertTrue(h.discovery.endpoints.isEmpty)

        h.provider.plug(keys(100))
        h.scheduler.runAll()
        let firstIDs: [MIDIEndpointID] = ids(h.discovery.endpoints)
        XCTAssertEqual(firstIDs, [.unique(100), .unique(101)])
        XCTAssertEqual(h.recorder.all.last?.changes.map(MIDIEndpointModelTests.describe), ["appeared midi:100", "appeared midi:101"])
        XCTAssertEqual(h.recorder.all.last?.isInitial, false)

        h.provider.unplug(uniqueIDs: [100, 101])
        h.scheduler.runAll()
        XCTAssertTrue(h.discovery.endpoints.isEmpty)
        XCTAssertEqual(h.recorder.all.last?.changes.map(MIDIEndpointModelTests.describe), ["disappeared midi:100", "disappeared midi:101"])

        h.provider.plug(keys(100))       // the same device again: the system keeps its numbers
        h.scheduler.runAll()
        XCTAssertEqual(ids(h.discovery.endpoints), firstIDs, "replug keeps every ID")
        XCTAssertEqual(h.recorder.all.count, 4)
    }

    // MARK: S2 — identical devices, rename

    func testTwoIdenticalControllersHaveDistinctIDsAndRenameKeepsTheID() {
        let h: Harness = makeHarness(keys(200) + keys(300))
        h.discovery.start()
        h.scheduler.runAll()
        let list: MIDIEndpointList = h.discovery.endpoints
        XCTAssertEqual(Set(ids(list)).count, 4)
        XCTAssertEqual(list.displayNames[.unique(300)], "Keys (2)")

        h.provider.rename(uniqueID: 300, to: "Keys B")
        h.scheduler.runAll()
        XCTAssertEqual(h.recorder.all.last?.changes.map(MIDIEndpointModelTests.describe), ["renamed midi:300 Keys→Keys B"])
        XCTAssertEqual(h.discovery.endpoints.endpoint(.unique(300))?.name, "Keys B")
    }

    // MARK: S3 — bursts

    func testBurstOfTenSignalsCostsOneRefresh() {
        let h: Harness = makeHarness()
        h.discovery.start()
        h.scheduler.runAll()
        let before: Int = h.discovery.refreshCount
        h.provider.signal(times: 9)
        h.provider.plug(keys(400))         // the tenth signal
        XCTAssertEqual(h.scheduler.pendingCount, 1, "one refresh pending for the whole burst")
        XCTAssertEqual(h.scheduler.pendingDelays, [MIDIEndpointDiscovery.defaultCoalescingDelayNanoseconds])
        h.scheduler.runAll()
        XCTAssertEqual(h.discovery.refreshCount - before, 1)
        XCTAssertEqual(h.discovery.absorbedSignals, 9)
        XCTAssertEqual(h.recorder.all.count, 2, "one update for the burst")
    }

    // MARK: S4 — offline and online

    func testOfflineAndOnlineKeepTheIDAndReportOnce() {
        let h: Harness = makeHarness(keys(500))
        h.discovery.start()
        h.scheduler.runAll()
        h.provider.setOffline(uniqueID: 500, true)
        h.scheduler.runAll()
        XCTAssertEqual(h.recorder.all.last?.changes.map(MIDIEndpointModelTests.describe), ["online midi:500 false"])
        XCTAssertEqual(h.discovery.endpoints.endpoint(.unique(500))?.isOnline, false)
        h.provider.setOffline(uniqueID: 500, false)
        h.scheduler.runAll()
        XCTAssertEqual(h.recorder.all.last?.changes.map(MIDIEndpointModelTests.describe), ["online midi:500 true"])
        h.provider.signal()
        h.scheduler.runAll()
        XCTAssertEqual(h.recorder.all.count, 3, "an unchanged refresh reports nothing")
    }

    // MARK: US2 — virtual endpoints

    func testVirtualEndpointIsListedAsVirtual() {
        let h: Harness = makeHarness()
        h.discovery.start()
        h.scheduler.runAll()
        h.provider.plug([MIDIEndpointRecord(uniqueID: 600, direction: .source, displayName: "Synth App", isVirtual: true)])
        h.scheduler.runAll()
        XCTAssertEqual(h.discovery.endpoints.endpoint(.unique(600))?.isVirtual, true)
    }

    // MARK: R7, R8 — stop, unavailable, network

    func testStopClearsAndIgnoresAPendingRefresh() {
        let h: Harness = makeHarness(keys(700))
        h.discovery.start()
        h.scheduler.runAll()
        h.provider.plug(keys(710))
        XCTAssertEqual(h.scheduler.pendingCount, 1)
        h.discovery.stop()
        XCTAssertFalse(h.provider.isForwarding)
        h.scheduler.runAll()
        XCTAssertEqual(h.discovery.state, .off)
        XCTAssertTrue(h.discovery.endpoints.isEmpty)
        XCTAssertEqual(h.recorder.all.count, 1, "the stale refresh delivered nothing")
        h.provider.plug(keys(720))
        XCTAssertEqual(h.scheduler.pendingCount, 0, "no signal after stop")

        h.discovery.start()                 // a fresh start reports a fresh initial list
        h.scheduler.runAll()
        XCTAssertEqual(h.recorder.all.last?.isInitial, true)
        XCTAssertEqual(h.discovery.endpoints.count, 6)
        XCTAssertEqual(h.recorder.stateLog, [.listening, .off, .listening])
    }

    func testUnavailableStartIsReportedAndNotRetried() {
        let h: Harness = makeHarness(keys(800))
        h.provider.failStart(code: -10_830)
        h.discovery.start()
        XCTAssertEqual(h.discovery.state, .unavailable(code: -10_830))
        XCTAssertEqual(h.scheduler.pendingCount, 0)
        h.discovery.start()
        XCTAssertEqual(h.provider.startCount, 1, "no retry until stop and start")
        h.provider.failStart(code: nil)
        h.discovery.stop()
        h.discovery.start()
        h.scheduler.runAll()
        XCTAssertEqual(h.discovery.state, .listening)
        XCTAssertEqual(h.discovery.endpoints.count, 2)
    }

    func testNetworkSessionEndpointsAreHidden() {
        let h: Harness = makeHarness([MIDIEndpointRecord(uniqueID: 900, direction: .source, displayName: "Session 1",
                                                         transport: .network)])
        h.discovery.start()
        h.scheduler.runAll()
        XCTAssertTrue(h.discovery.endpoints.isEmpty)
    }

    // MARK: R12 — delivery on the scheduler, never inline

    func testUpdatesAreDeliveredOnlyFromTheScheduler() {
        let h: Harness = makeHarness()
        h.discovery.start()
        XCTAssertTrue(h.recorder.all.isEmpty, "the initial list waits for the scheduler")
        h.scheduler.runAll()
        h.provider.plug(keys(1000))
        XCTAssertEqual(h.recorder.all.count, 1, "a provider signal never delivers inline")
        h.scheduler.runAll()
        XCTAssertEqual(h.recorder.all.count, 2)
    }

    func testUnavailableProviderOnPlatformsWithoutMIDI() {
        let discovery = MIDIEndpointDiscovery(provider: UnavailableMIDIEndpointProvider(), scheduler: ManualMIDIScheduler().scheduler)
        discovery.start()
        XCTAssertEqual(discovery.state, .unavailable(code: 0))
    }
}

#if canImport(CoreMIDI)
/// The system provider reads whatever the host exposes (often nothing) without a client and without
/// starting; the list it builds is well-formed. Smoke only: hardware behaviour is MIDI-001-S8 on a device.
final class CoreMIDIEndpointProviderSmokeTests: XCTestCase {
    func testSystemReadBuildsAWellFormedList() {
        let provider = CoreMIDIEndpointProvider()
        let records: [MIDIEndpointRecord] = provider.currentEndpoints()
        let list: MIDIEndpointList = MIDIEndpointList.make(from: records)
        let unique: Set<MIDIEndpointID> = Set(list.endpoints.map { (e: MIDIEndpoint) -> MIDIEndpointID in e.id })
        XCTAssertEqual(unique.count, list.count)
        XCTAssertFalse(list.endpoints.contains { (e: MIDIEndpoint) -> Bool in e.name.isEmpty })
    }
}
#endif
