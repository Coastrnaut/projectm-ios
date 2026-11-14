// MIDI-011-T09, T10: hot-plug recovery in the app with the scripted MIDI system (discovery and an input over a source
// system with handles), one manual scheduler for both, a manual clock and `drain()` for the display link. Everything
// from MIDI bytes to the parameter value, the cue step and the blackout is the app's real code.
// * S5: a mapped CC changes its parameter once per message after unplug and replug, and a mapped note fires once.
// * R5: a quick replug that leaves discovery's list unchanged still repairs the connection and releases a held key.
// * R6: a returning device is announced "reconnected"; a new one, or one first listed after a restart, "connected".
import ParameterGraph
import PerformanceControl
import VisualParameters
import XCTest
@testable import projectM_iOS

@MainActor
final class MIDIHotplugCoordinatorTests: XCTestCase {
    @MainActor private final class Log {
        var actions: [String] = []
        var blackedOut = false
        var discoveryAnnouncements: [String] = []
        var applied: [[ParameterID: Double]] = []
        var now: UInt64 = 1_000_000_000
    }

    private struct Harness {
        let defaults: UserDefaults
        let suite: String
        let endpoints: ScriptedMIDIEndpointProvider
        let system: ScriptedMIDISourceSystem
        let scheduler: ManualMIDIScheduler
        let discovery: MIDIDiscoveryCoordinator
        let inputProvider: ScriptedMIDISourceInputProvider
        let input: MIDIInputCoordinator
        let mappings: MIDIMappingCoordinator
        let log: Log
    }

    private static let keysID: Int32 = 0x1101
    private static let padsID: Int32 = 0x1102
    private static let keys = MIDIEndpointRecord(uniqueID: keysID, direction: .source, displayName: "Keys",
                                                 endpointName: "Port", entityName: "Keys", deviceName: "Keys")
    private static let pads = MIDIEndpointRecord(uniqueID: padsID, direction: .source, displayName: "Pads",
                                                 endpointName: "Port", entityName: "Pads", deviceName: "Pads")
    private static let intensity: ParameterID = VisualParameterIDs.bloomIntensity

    private func makeHarness(lines: [String]) throws -> Harness {
        let suite: String = "MIDIHotplugCoordinatorTests-" + UUID().uuidString
        let defaults: UserDefaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.set(true, forKey: AppSettings.midiEnabledKey)
        defaults.set(lines, forKey: MIDIMappingCoordinator.mappingsKey)
        let settings = AppSettings(defaults: defaults, systemReduceMotion: false)
        let log = Log()
        let endpoints = ScriptedMIDIEndpointProvider(records: [Self.keys])
        let system = ScriptedMIDISourceSystem(records: [Self.keys])
        let scheduler = ManualMIDIScheduler()
        let discovery = MIDIDiscoveryCoordinator(
            settings: settings, discovery: MIDIEndpointDiscovery(provider: endpoints, scheduler: scheduler.scheduler),
            announce: { (text: String) -> Void in log.discoveryAnnouncements.append(text) })
        _ = scheduler.runAll()
        let inputProvider = ScriptedMIDISourceInputProvider(system: system, scheduler: scheduler.scheduler)
        let input = MIDIInputCoordinator(service: MIDIInputService(provider: inputProvider), discovery: discovery,
                                         drivesDisplayLink: false)
        let mappings = MIDIMappingCoordinator(
            registry: MIDIMappingCoordinator.visualRegistry(), applied: MIDIMappingCoordinator.appliedIDs, input: input,
            discovery: discovery, defaults: defaults,
            announce: { (_: String) -> Void in },
            clock: { () -> UInt64 in log.now },
            scheduler: { (_: UInt64, _: @escaping @MainActor () -> Void) -> (@MainActor () -> Void) in { () -> Void in } })
        mappings.applyValues = { (values: [ParameterID: Double]) -> Void in log.applied.append(values) }
        let actions = MIDINoteActionPerformer.Actions(
            nextCue: { () -> Void in log.actions.append("next") },
            previousCue: { () -> Void in log.actions.append("previous") },
            isBlackoutRequested: { () -> Bool in log.blackedOut },
            setBlackout: { (on: Bool) -> Void in
                log.blackedOut = on
                log.actions.append(on ? "blackout" : "restore")
            })
        mappings.connectNoteActions(MIDINoteActionPerformer(actions: actions))
        mappings.open()
        return Harness(defaults: defaults, suite: suite, endpoints: endpoints, system: system, scheduler: scheduler,
                       discovery: discovery, inputProvider: inputProvider, input: input, mappings: mappings, log: log)
    }

    private func cleanUp(_ h: Harness) {
        h.mappings.close()
        h.defaults.removePersistentDomain(forName: h.suite)
    }

    /// Sends from a source and drains; returns how many times the system delivered the bytes (live connections).
    @discardableResult
    private func send(_ h: Harness, _ bytes: [UInt8], from number: Int32 = keysID) -> Int {
        h.log.now += 100_000_000   // beyond MIDI-008's 30 ms repeat window
        let deliveries: Int = h.inputProvider.send(bytes, from: number, timestamp: h.log.now)
        h.input.drain()
        return deliveries
    }

    private func unplug(_ h: Harness, _ number: Int32 = keysID) {
        h.system.unplug(uniqueIDs: [number])
        h.endpoints.unplug(uniqueIDs: [number])
    }

    private func plug(_ h: Harness, _ record: MIDIEndpointRecord = keys) {
        h.system.plug([record])
        h.endpoints.plug([record])
    }

    // MARK: S5 — a mapped control after a reconnect

    func testAMappedCCAndNoteWorkOnceAfterAReconnect() throws {
        let h: Harness = try makeHarness(lines: ["cc:0:7=effect.bloom.intensity", "note:0:60=cue.next"])
        defer { cleanUp(h) }
        XCTAssertTrue(h.input.isReceiving)
        XCTAssertEqual(send(h, [0xB0, 0x07, 0x7F]), 1)
        XCTAssertEqual(h.mappings.liveValues, [Self.intensity: 1])

        unplug(h)
        _ = h.scheduler.runAll()
        XCTAssertEqual(h.system.liveConnections(uniqueID: Self.keysID), 0)
        XCTAssertEqual(send(h, [0xB0, 0x07, 0x00]), 0, "unplugged: nothing arrives")
        plug(h)
        _ = h.scheduler.runAll()
        XCTAssertEqual(h.system.liveConnections(uniqueID: Self.keysID), 1, "one live listener after the replug")
        XCTAssertEqual(h.system.totalConnections, 1)

        let appliedBefore: Int = h.log.applied.count
        XCTAssertEqual(send(h, [0xB0, 0x07, 0x00]), 1, "delivered once")
        XCTAssertEqual(h.mappings.liveValues, [Self.intensity: 0], "the mapping still works")
        XCTAssertEqual(h.log.applied.count, appliedBefore + 1, "one change per message: no double trigger")
        XCTAssertEqual(send(h, [0x90, 0x3C, 0x64, 0x80, 0x3C, 0x00]), 1)
        XCTAssertEqual(h.log.actions, ["next"], "a mapped note fires once")
    }

    // MARK: R5 — quick replug

    func testAQuickReplugRepairsTheListenerAndReleasesAHeldKey() throws {
        let h: Harness = try makeHarness(lines: ["note:0:61=blackout;mode=hold"])
        defer { cleanUp(h) }
        let refreshes: Int = h.discovery.discovery.refreshCount
        send(h, [0x90, 0x3D, 0x64])
        XCTAssertTrue(h.log.blackedOut)

        unplug(h)   // the note-off is lost with the cable
        plug(h)
        _ = h.scheduler.runAll()
        XCTAssertEqual(h.discovery.discovery.refreshCount, refreshes + 1, "discovery refreshed once")
        XCTAssertEqual(h.discovery.list.count, 1, "discovery's list is unchanged")
        XCTAssertEqual(h.system.liveConnections(uniqueID: Self.keysID), 1, "the input reattached by itself")

        h.input.drain()
        XCTAssertFalse(h.log.blackedOut, "the held key is released")
        XCTAssertEqual(h.log.actions, ["blackout", "restore"])
        XCTAssertEqual(send(h, [0x90, 0x3D, 0x64]), 1)
        XCTAssertEqual(h.log.actions, ["blackout", "restore", "blackout"], "a new press acts once")
    }

    // MARK: R6 — reconnect announcement

    func testAReturningDeviceIsAnnouncedReconnected() throws {
        let h: Harness = try makeHarness(lines: [])
        defer { cleanUp(h) }
        XCTAssertTrue(h.log.discoveryAnnouncements.isEmpty, "the first list is silent")
        unplug(h)
        _ = h.scheduler.runAll()
        plug(h)
        _ = h.scheduler.runAll()
        plug(h, Self.pads)
        _ = h.scheduler.runAll()
        XCTAssertEqual(h.log.discoveryAnnouncements, ["MIDI device disconnected: Keys", "MIDI device reconnected: Keys",
                                                      "MIDI device connected: Pads"])

        // After a stop, a device first listed after the restart is new again.
        h.discovery.setEnabled(false)
        unplug(h)
        h.discovery.setEnabled(true)
        _ = h.scheduler.runAll()
        plug(h)
        _ = h.scheduler.runAll()
        XCTAssertEqual(h.log.discoveryAnnouncements.last, "MIDI device connected: Keys")
    }

    func testAnnouncementTextsForSeveralDevices() {
        let list: MIDIEndpointList = MIDIEndpointList.make(from: [Self.keys, Self.pads])
        let changes: [MIDIEndpointChange] = list.endpoints.map { (e: MIDIEndpoint) -> MIDIEndpointChange in .appeared(e) }
        let update = MIDIDiscoveryUpdate(endpoints: list, changes: changes, isInitial: false)
        let both: Set<MIDIEndpointID> = Set(list.endpoints.map { (e: MIDIEndpoint) -> MIDIEndpointID in e.id })
        XCTAssertEqual(MIDIDiscoveryCoordinator.announcement(for: update, seen: both), "2 MIDI devices reconnected")
        XCTAssertEqual(MIDIDiscoveryCoordinator.announcement(for: update), "2 MIDI devices connected")
    }
}
