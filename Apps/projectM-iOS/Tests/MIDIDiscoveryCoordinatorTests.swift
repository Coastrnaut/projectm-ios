// MIDI-001-T12, T14: MIDI discovery in the app with a scripted MIDI system and a manual scheduler
// (MIDI-001-R7-R11; contracts/midi-discovery.md C3). No CoreMIDI, no clock: refreshes run inside
// `runAll()` on the test's (main) thread, so updates reach the coordinator synchronously.
import PerformanceControl
import XCTest
@testable import projectM_iOS

@MainActor
final class MIDIDiscoveryCoordinatorTests: XCTestCase {
    private struct Harness {
        let settings: AppSettings
        let defaults: UserDefaults
        let suite: String
        let provider: ScriptedMIDIEndpointProvider
        let scheduler: ManualMIDIScheduler
        let coordinator: MIDIDiscoveryCoordinator
        let spoken: SpokenLog
    }

    private final class SpokenLog {
        var texts: [String] = []
    }

    private func makeHarness(records: [MIDIEndpointRecord] = [], enabled: Bool? = nil, active: Bool = true) throws -> Harness {
        let suite: String = "MIDIDiscoveryCoordinatorTests-" + UUID().uuidString
        let defaults: UserDefaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        if let enabled { defaults.set(enabled, forKey: AppSettings.midiEnabledKey) }
        let settings = AppSettings(defaults: defaults, systemReduceMotion: false)
        let provider = ScriptedMIDIEndpointProvider(records: records)
        let scheduler = ManualMIDIScheduler()
        let discovery = MIDIEndpointDiscovery(provider: provider, scheduler: scheduler.scheduler)
        let spoken = SpokenLog()
        let coordinator = MIDIDiscoveryCoordinator(settings: settings, discovery: discovery, appIsActive: active,
                                                   announce: { (text: String) -> Void in spoken.texts.append(text) })
        return Harness(settings: settings, defaults: defaults, suite: suite, provider: provider, scheduler: scheduler,
                       coordinator: coordinator, spoken: spoken)
    }

    private func cleanUp(_ h: Harness) { h.defaults.removePersistentDomain(forName: h.suite) }

    private func keys(_ base: Int32, _ name: String = "Keys") -> [MIDIEndpointRecord] {
        [MIDIEndpointRecord(uniqueID: base, direction: .source, displayName: name, entityName: name, deviceName: name),
         MIDIEndpointRecord(uniqueID: base + 1, direction: .destination, displayName: name, entityName: name, deviceName: name)]
    }

    // MARK: R7, R8 — off by default, enabled and active only

    func testOffByDefaultTouchesNothing() throws {
        let h: Harness = try makeHarness(records: keys(10))
        defer { cleanUp(h) }
        XCTAssertFalse(h.settings.midiEnabled, "fresh install: off (MIDI-001-R8)")
        XCTAssertEqual(h.provider.startCount, 0, "the MIDI system is not touched while off")
        XCTAssertEqual(h.coordinator.statusText, "Off")
        XCTAssertTrue(h.coordinator.rows.isEmpty)
    }

    func testListensOnlyWhileEnabledAndActiveAndClearsOnLeaving() throws {
        let h: Harness = try makeHarness(records: keys(20))
        defer { cleanUp(h) }
        h.coordinator.setEnabled(true)
        h.scheduler.runAll()
        XCTAssertEqual(h.coordinator.state, .listening)
        XCTAssertEqual(h.coordinator.rows.count, 2)
        XCTAssertEqual(h.coordinator.statusText, "Listening — 2 devices")
        XCTAssertTrue(h.spoken.texts.isEmpty, "the first list is silent (spec Clarifications)")

        h.coordinator.sceneBecame(active: false)
        XCTAssertEqual(h.coordinator.state, .off)
        XCTAssertTrue(h.coordinator.rows.isEmpty, "the list is dropped in the background")
        XCTAssertEqual(h.coordinator.statusText, MIDIDiscoveryCoordinator.backgroundText)
        XCTAssertFalse(h.provider.isForwarding)

        h.coordinator.sceneBecame(active: true)
        h.scheduler.runAll()
        XCTAssertEqual(h.coordinator.rows.count, 2)
        h.coordinator.setEnabled(false)
        XCTAssertEqual(h.coordinator.statusText, "Off")
        XCTAssertTrue(h.coordinator.rows.isEmpty)
        XCTAssertTrue(h.spoken.texts.isEmpty, "returning to the foreground announces nothing")
    }

    func testStoredToggleStartsDiscoveryAtLaunch() throws {
        let h: Harness = try makeHarness(records: keys(30), enabled: true)
        defer { cleanUp(h) }
        h.scheduler.runAll()
        XCTAssertEqual(h.coordinator.rows.count, 2)
        let inactive: Harness = try makeHarness(records: keys(30), enabled: true, active: false)
        defer { cleanUp(inactive) }
        XCTAssertEqual(inactive.provider.startCount, 0, "not in the background")
    }

    // MARK: R11 — announcements

    func testAppearancesAndDisappearancesAreAnnouncedOncePerDevice() throws {
        let h: Harness = try makeHarness(enabled: true)
        defer { cleanUp(h) }
        h.scheduler.runAll()
        h.provider.plug(keys(40))
        h.scheduler.runAll()
        XCTAssertEqual(h.spoken.texts, ["MIDI device connected: Keys"], "input and output count as one device")
        h.provider.plug(keys(50, "Pad") + [MIDIEndpointRecord(uniqueID: 60, direction: .source, displayName: "Synth App", isVirtual: true)])
        h.scheduler.runAll()
        XCTAssertEqual(h.spoken.texts.last, "2 MIDI devices connected")
        h.provider.setRecords(keys(50, "Pad") + keys(70, "Drums"))
        h.scheduler.runAll()
        XCTAssertEqual(h.spoken.texts.last, "MIDI device connected: Drums. 2 MIDI devices disconnected")
        let count: Int = h.spoken.texts.count
        h.provider.rename(uniqueID: 50, to: "Pad 2")
        h.provider.setOffline(uniqueID: 70, true)
        h.scheduler.runAll()
        XCTAssertEqual(h.spoken.texts.count, count, "renames and online changes are not announced")
    }

    func testAnnouncementTexts() {
        let endpoint = MIDIEndpoint(id: .unique(1), direction: .source, name: "Keys", isOnline: true, isVirtual: false,
                                    transport: .local, deviceName: "Keys")
        let initial = MIDIDiscoveryUpdate(endpoints: .empty, changes: [.appeared(endpoint)], isInitial: true)
        XCTAssertNil(MIDIDiscoveryCoordinator.announcement(for: initial))
        let gone = MIDIDiscoveryUpdate(endpoints: .empty, changes: [.disappeared(endpoint)], isInitial: false)
        XCTAssertEqual(MIDIDiscoveryCoordinator.announcement(for: gone), "MIDI device disconnected: Keys")
    }

    // MARK: R8, R9 — status and rows

    func testStatusTexts() {
        XCTAssertEqual(MIDIDiscoveryCoordinator.statusText(for: .off, enabled: false, count: 0), "Off")
        XCTAssertEqual(MIDIDiscoveryCoordinator.statusText(for: .off, enabled: true, count: 0), MIDIDiscoveryCoordinator.backgroundText)
        XCTAssertEqual(MIDIDiscoveryCoordinator.statusText(for: .listening, enabled: true, count: 0), "Listening — no MIDI devices")
        XCTAssertEqual(MIDIDiscoveryCoordinator.statusText(for: .listening, enabled: true, count: 1), "Listening — 1 device")
        XCTAssertEqual(MIDIDiscoveryCoordinator.statusText(for: .listening, enabled: true, count: 12), "Listening — 12 devices")
        XCTAssertEqual(MIDIDiscoveryCoordinator.statusText(for: .unavailable(code: -1), enabled: true, count: 0),
                       "MIDI isn't available on this device.")
    }

    func testRowsNameDetailAndLabel() {
        let list: MIDIEndpointList = .make(from: keys(80) + keys(90) + [
            MIDIEndpointRecord(uniqueID: 95, direction: .destination, displayName: "Synth App", isVirtual: true),
            MIDIEndpointRecord(uniqueID: 96, direction: .source, displayName: "Old Pad", isOffline: true),
        ])
        let rows: [MIDIEndpointRow] = MIDIDiscoveryCoordinator.rows(for: list)
        XCTAssertEqual(rows.map { (r: MIDIEndpointRow) -> String in r.accessibilityLabel }, [
            "Keys, Input", "Keys (2), Input", "Old Pad, Input, Offline",
            "Keys, Output", "Keys (2), Output", "Synth App, Output, Virtual",
        ])
        XCTAssertEqual(rows[0].id, "midi:80")
    }

    func testUnavailableIsShownAndNotRetried() throws {
        let h: Harness = try makeHarness()
        defer { cleanUp(h) }
        h.provider.failStart(code: -10_830)
        h.coordinator.setEnabled(true)
        XCTAssertEqual(h.coordinator.statusText, MIDIDiscoveryCoordinator.unavailableText)
        XCTAssertEqual(h.scheduler.pendingCount, 0)
        h.provider.failStart(code: nil)
        h.coordinator.setEnabled(false)
        h.coordinator.setEnabled(true)   // off and on tries again
        h.scheduler.runAll()
        XCTAssertEqual(h.coordinator.state, .listening)
    }

    // MARK: R10 — only the toggle is stored

    func testOnlyTheToggleIsStored() throws {
        let h: Harness = try makeHarness()
        defer { cleanUp(h) }
        let before: Set<String> = Set(h.defaults.persistentDomain(forName: h.suite)?.keys.map { (k: String) -> String in k } ?? [])
        h.coordinator.setEnabled(true)
        h.provider.plug(keys(100, "Secret Studio Keys"))
        h.scheduler.runAll()
        let after: [String: Any] = h.defaults.persistentDomain(forName: h.suite) ?? [:]
        let added: Set<String> = Set(after.keys).subtracting(before)
        XCTAssertEqual(added, [AppSettings.midiEnabledKey])
        XCTAssertTrue(AppSettings.allKeys.contains(AppSettings.midiEnabledKey))
        let values: String = after.values.map { (v: Any) -> String in String(describing: v) }.joined(separator: " ")
        XCTAssertFalse(values.contains("Secret"), "no device name is stored")
    }
}
