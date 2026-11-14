// MIDI-002-T13, T15, T16: the MIDI Monitor in the app with a scripted MIDI system (discovery and input), a
// manual scheduler and a manual clock; `drain()` stands in for the display link, so nothing depends on wall time.
// * The row's acceptance (S1, S2): injected control change and note messages render the expected texts, and no
//   entry, counter, status text, input state, log line or stored setting contains the source's name or number.
// * Receiving only while listening and open (R1); sources follow plug and unplug (R2); the monitor row and the
//   listening-off text (R15); the 64-entry cap, pause, resume and clear (R8, R9); close drops everything.
import OSLog
import PerformanceControl
import XCTest
@testable import projectM_iOS

@MainActor
final class MIDIMonitorCoordinatorTests: XCTestCase {
    private final class ManualClock {
        var now: UInt64 = 1_000_000_000
    }

    private struct Harness {
        let settings: AppSettings
        let defaults: UserDefaults
        let suite: String
        let endpoints: ScriptedMIDIEndpointProvider
        let scheduler: ManualMIDIScheduler
        let discovery: MIDIDiscoveryCoordinator
        let inputProvider: ScriptedMIDIInputProvider
        let input: MIDIInputCoordinator
        let monitor: MIDIMonitorCoordinator
        let clock: ManualClock
    }

    /// The distinctive source the privacy scan looks for (research MIDI-002-D6).
    static let secretName = "Secret Keys"
    static let secretID: Int32 = 0x5EC2E7

    private static let secretRecords: [MIDIEndpointRecord] = [
        MIDIEndpointRecord(uniqueID: secretID, direction: .source, displayName: secretName, endpointName: "Secret Port",
                           entityName: "Secret Entity", deviceName: "Secret Device"),
        MIDIEndpointRecord(uniqueID: secretID + 1, direction: .destination, displayName: secretName,
                           endpointName: "Secret Port", entityName: "Secret Entity", deviceName: "Secret Device"),
    ]

    private func makeHarness(records: [MIDIEndpointRecord] = secretRecords, enabled: Bool = true) throws -> Harness {
        let suite: String = "MIDIMonitorCoordinatorTests-" + UUID().uuidString
        let defaults: UserDefaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.set(enabled, forKey: AppSettings.midiEnabledKey)
        let settings = AppSettings(defaults: defaults, systemReduceMotion: false)
        let endpoints = ScriptedMIDIEndpointProvider(records: records)
        let scheduler = ManualMIDIScheduler()
        let discovery = MIDIDiscoveryCoordinator(settings: settings,
                                                 discovery: MIDIEndpointDiscovery(provider: endpoints, scheduler: scheduler.scheduler))
        _ = scheduler.runAll()
        let inputProvider = ScriptedMIDIInputProvider()
        let input = MIDIInputCoordinator(service: MIDIInputService(provider: inputProvider), discovery: discovery,
                                         drivesDisplayLink: false)
        let clock = ManualClock()
        let monitor = MIDIMonitorCoordinator(input: input, discovery: discovery,
                                             clock: { () -> UInt64 in clock.now })
        discovery.monitor = monitor
        return Harness(settings: settings, defaults: defaults, suite: suite, endpoints: endpoints, scheduler: scheduler,
                       discovery: discovery, inputProvider: inputProvider, input: input, monitor: monitor, clock: clock)
    }

    private func cleanUp(_ h: Harness) {
        h.monitor.close()
        h.defaults.removePersistentDomain(forName: h.suite)
    }

    /// Sends bytes `seconds` after the monitor's origin and drains (one display tick).
    private func send(_ h: Harness, _ bytes: [UInt8], at seconds: Double = 0.5) {
        let offset: UInt64 = UInt64(seconds * 1_000_000_000)
        h.inputProvider.send(bytes, timestamp: h.clock.now + offset)
        h.input.drain()
    }

    private func labels(_ h: Harness) -> [String] {
        h.monitor.entries.map { (entry: MIDIMonitorEntry) -> String in entry.accessibilityLabel }
    }

    // MARK: S1 — the acceptance: injected CC and notes render correctly

    func testInjectedControlChangeAndNotesRenderTheExpectedTexts() throws {
        let h: Harness = try makeHarness()
        defer { cleanUp(h) }
        h.monitor.open()
        XCTAssertTrue(h.input.isReceiving)
        XCTAssertEqual(h.monitor.statusText, "Waiting for MIDI messages")

        send(h, [0xB0, 0x07, 0x64], at: 12.4)
        let cc: MIDIMonitorEntry = try XCTUnwrap(h.monitor.entries.first)
        XCTAssertEqual([cc.text.type, cc.text.channel, cc.text.number, cc.text.value, cc.time],
                       ["Control change", "Ch 1", "CC 7", "100", "12.40 s"])
        XCTAssertEqual(cc.accessibilityLabel, "Control change, channel 1, controller 7, value 100")

        send(h, [0x99, 0x3C, 0x7F, 0x3C, 0x00], at: 13.05)   // ch 10 note on, then velocity 0 by running status
        XCTAssertEqual(labels(h), ["Note off, channel 10, note 60 C4, velocity 0",
                                   "Note on, channel 10, note 60 C4, velocity 127",
                                   "Control change, channel 1, controller 7, value 100"], "newest first")
        XCTAssertEqual(h.monitor.entries[1].text.number, "60 C4")
        XCTAssertEqual(h.monitor.entries[0].time, "13.05 s")
        XCTAssertEqual(h.monitor.statusText, "Receiving")

        send(h, [0xE0, 0x00, 0x40, 0xF8, 0xF8, 0xFE])
        XCTAssertEqual(h.monitor.entries.first?.accessibilityLabel, "Pitch bend, channel 1, value 8192")
        XCTAssertEqual(h.monitor.summaryText, "Clock 2 · Active sensing 1 · Dropped 0", "clock and sensing are only counted")
    }

    // MARK: S2 — without recording identifiers

    func testNoIdentifierIsRecordedAnywhere() throws {
        let start = Date()
        let h: Harness = try makeHarness()
        defer { cleanUp(h) }
        h.monitor.open()
        XCTAssertEqual(h.inputProvider.connectedSources, [.unique(Self.secretID)], "the secret source is connected")
        send(h, [0xB0, 0x07, 0x64, 0x90, 0x3C, 0x64, 0x80, 0x3C, 0x00, 0xF0, 0x01, 0x02, 0xF7])
        XCTAssertEqual(h.monitor.entries.count, 4)

        var haystack: [String] = []
        for entry in h.monitor.entries {
            haystack += [entry.text.type, entry.text.channel, entry.text.number, entry.text.value, entry.text.spoken,
                         entry.time, String(reflecting: entry)]
        }
        haystack += [h.monitor.statusText, h.monitor.summaryText, String(reflecting: h.input.state),
                     String(reflecting: h.monitor.inputState)]
        for (key, value) in h.defaults.dictionaryRepresentation() { haystack += [key, String(describing: value)] }
        for (key, value) in UserDefaults.standard.dictionaryRepresentation() { haystack += [key, String(describing: value)] }
        haystack += try Self.processLog(since: start)

        let needles: [String] = ["secret", "5ec2e7", String(Self.secretID), MIDIEndpointID.unique(Self.secretID).description]
        for text in haystack {
            let lowered: String = text.lowercased()
            for needle in needles {
                XCTAssertFalse(lowered.contains(needle.lowercased()), "identifier \(needle) recorded in: \(text.prefix(120))")
            }
        }
        let added: Set<String> = Set(h.defaults.dictionaryRepresentation().keys)
            .subtracting(UserDefaults.standard.dictionaryRepresentation().keys)
        XCTAssertTrue(added.isSubset(of: Set(AppSettings.allKeys)), "the monitor adds no stored setting: \(added)")
    }

    /// This process's unified log entries since `date` (research MIDI-002-D6).
    private static func processLog(since date: Date) throws -> [String] {
        let store: OSLogStore = try OSLogStore(scope: .currentProcessIdentifier)
        let position: OSLogPosition = store.position(date: date)
        let entries: AnySequence<OSLogEntry> = try store.getEntries(at: position)
        return entries.map { (entry: OSLogEntry) -> String in entry.composedMessage }
    }

    func testCloseDropsEverythingAndReopensEmpty() throws {
        let h: Harness = try makeHarness()
        defer { cleanUp(h) }
        h.monitor.open()
        send(h, [0xB0, 0x07, 0x64, 0xF8])
        h.monitor.close()
        XCTAssertTrue(h.monitor.entries.isEmpty)
        XCTAssertFalse(h.input.isReceiving, "closing the only client stops receiving")
        XCTAssertTrue(h.inputProvider.connectedSources.isEmpty)
        h.monitor.open()
        XCTAssertTrue(h.monitor.entries.isEmpty, "reopened empty (MIDI-002-R8)")
        XCTAssertEqual(h.monitor.summaryText, "Clock 0 · Active sensing 0 · Dropped 0")
    }

    // MARK: R1, R2, R15

    func testReceivesOnlyWhileListeningAndOpen() throws {
        let h: Harness = try makeHarness(enabled: false)
        defer { cleanUp(h) }
        XCTAssertNotNil(h.discovery.monitor, "the MIDI section offers the monitor (MIDI-002-R15)")
        h.monitor.open()
        XCTAssertFalse(h.input.isReceiving, "listening off: nothing received")
        XCTAssertEqual(h.inputProvider.openCount, 0, "the MIDI input is not touched")
        XCTAssertEqual(h.monitor.statusText, MIDIMonitorCoordinator.offText)

        h.discovery.setEnabled(true)
        _ = h.scheduler.runAll()
        XCTAssertTrue(h.input.isReceiving)
        h.discovery.sceneBecame(active: false)
        XCTAssertFalse(h.input.isReceiving, "background: stopped")
        XCTAssertFalse(h.inputProvider.send([0xB0, 1, 1], timestamp: 1))
        h.discovery.sceneBecame(active: true)
        _ = h.scheduler.runAll()
        XCTAssertTrue(h.input.isReceiving)
        h.discovery.setEnabled(false)
        XCTAssertFalse(h.input.isReceiving, "toggle off while open: stopped at once")
        XCTAssertEqual(h.monitor.statusText, MIDIMonitorCoordinator.offText)
    }

    func testSourcesFollowPlugAndUnplugAndNeverIncludeOutputs() throws {
        let h: Harness = try makeHarness(records: [])
        defer { cleanUp(h) }
        h.monitor.open()
        XCTAssertTrue(h.input.isReceiving)
        XCTAssertTrue(h.inputProvider.connectedSources.isEmpty)
        h.endpoints.plug(Self.secretRecords)
        _ = h.scheduler.runAll()
        XCTAssertEqual(h.inputProvider.connectedSources, [.unique(Self.secretID)], "the input only, not the output")
        h.endpoints.setOffline(uniqueID: Self.secretID, true)
        _ = h.scheduler.runAll()
        XCTAssertTrue(h.inputProvider.connectedSources.isEmpty, "an offline input is not connected")
        h.endpoints.setOffline(uniqueID: Self.secretID, false)
        h.endpoints.unplug(uniqueIDs: [Self.secretID, Self.secretID + 1])
        _ = h.scheduler.runAll()
        XCTAssertTrue(h.inputProvider.connectedSources.isEmpty)
    }

    // MARK: R8, R9 — cap, pause, clear

    func testKeepsTheNewest64() throws {
        let h: Harness = try makeHarness()
        defer { cleanUp(h) }
        h.monitor.open()
        var bytes: [UInt8] = [0xB0]
        for value in 0..<70 { bytes += [0x01, UInt8(value)] }
        send(h, bytes)
        XCTAssertEqual(h.monitor.entries.count, MIDIMonitorCoordinator.entryLimit)
        XCTAssertEqual(h.monitor.entries.first?.text.value, "69", "newest first")
        XCTAssertEqual(h.monitor.entries.last?.text.value, "6")
    }

    func testPauseFreezesResumeAddsOnlyNewAndClearEmpties() throws {
        let h: Harness = try makeHarness()
        defer { cleanUp(h) }
        h.monitor.open()
        send(h, [0xB0, 0x07, 0x01])
        h.monitor.togglePause()
        XCTAssertEqual(h.monitor.statusText, "Paused")
        send(h, [0xB0, 0x07, 0x02, 0x07, 0x03])
        XCTAssertEqual(h.monitor.entries.count, 1, "frozen while paused")
        XCTAssertEqual(h.monitor.summaryText, "Clock 0 · Active sensing 0 · Dropped 0 · While paused 2")
        h.monitor.togglePause()
        send(h, [0xB0, 0x07, 0x04])
        XCTAssertEqual(h.monitor.entries.map { (e: MIDIMonitorEntry) -> String in e.text.value }, ["4", "1"],
                       "only messages after resuming are added")
        h.clock.now += 3_000_000_000
        h.monitor.clear()
        XCTAssertTrue(h.monitor.entries.isEmpty)
        send(h, [0xB0, 0x07, 0x05], at: 0.25)
        XCTAssertEqual(h.monitor.entries.first?.time, "0.25 s", "time restarts at the clear")
    }

    func testDroppedMessagesAreReported() throws {
        let h: Harness = try makeHarness()
        defer { cleanUp(h) }
        h.monitor.open()
        var bytes: [UInt8] = [0xB0]
        for _ in 0..<600 { bytes += [0x01, 0x01] }
        h.inputProvider.send(bytes, timestamp: h.clock.now)
        h.input.drain()
        XCTAssertEqual(h.monitor.summaryText, "Clock 0 · Active sensing 0 · Dropped 88", "512 fit; 88 dropped")
        XCTAssertEqual(h.monitor.entries.count, 64)
    }
}
