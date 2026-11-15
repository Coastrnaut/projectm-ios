// MIDI-010-T07 (MIDI-010-R5, R6, R7, S5): Follow MIDI clock in the app with a scripted MIDI system (discovery and input),
// a manual clock and `drain()` standing in for the display link; every pulse carries an explicit timestamp. The path
// from MIDI bytes to `TempoCoordinator.snapshot` is the app's real code.
// * Toggle on: a fake source's 24-PPQN clock at 120 BPM makes the snapshot report 120 ± 0.1 from MIDI clock.
// * Toggle off: the same clock leaves the snapshot unchanged (nothing reads it).
// * A tap while the clock sets the tempo announces the notice; losing the clock falls back to the tapped tempo.
import PerformanceControl
import XCTest
@testable import projectM_iOS

@MainActor
final class MIDIClockCoordinatorTests: XCTestCase {
    @MainActor private final class Log {
        var announcements: [String] = []
        var now: UInt64 = 5_000_000_000
        var tapNow: UInt64 = 1_000_000_000
    }

    private struct Harness {
        let defaults: UserDefaults
        let suite: String
        let inputProvider: ScriptedMIDIInputProvider
        let input: MIDIInputCoordinator
        let tempo: TempoCoordinator
        let clock: MIDIClockCoordinator
        let log: Log
    }

    private static let keysID: Int32 = 0x6010
    private static let records: [MIDIEndpointRecord] = [
        MIDIEndpointRecord(uniqueID: keysID, direction: .source, displayName: "Drums", endpointName: "Port",
                           entityName: "Drums", deviceName: "Drums"),
    ]
    /// 60 s / (24 × 120) in nanoseconds.
    private static let period120: Double = 60e9 / 2_880

    private func makeHarness(following: Bool) throws -> Harness {
        let suite: String = "MIDIClockCoordinatorTests-" + UUID().uuidString
        let defaults: UserDefaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.set(true, forKey: AppSettings.midiEnabledKey)
        if following { defaults.set(true, forKey: MIDIClockCoordinator.followKey) }
        let settings = AppSettings(defaults: defaults, systemReduceMotion: false)
        let endpoints = ScriptedMIDIEndpointProvider(records: Self.records)
        let scheduler = ManualMIDIScheduler()
        let discovery = MIDIDiscoveryCoordinator(settings: settings,
                                                 discovery: MIDIEndpointDiscovery(provider: endpoints, scheduler: scheduler.scheduler))
        _ = scheduler.runAll()
        let inputProvider = ScriptedMIDIInputProvider()
        let input = MIDIInputCoordinator(service: MIDIInputService(provider: inputProvider), discovery: discovery,
                                         drivesDisplayLink: false)
        let log = Log()
        let tempo = TempoCoordinator(clock: { () -> UInt64 in
                                         log.tapNow += 500_000_000
                                         return log.tapNow
                                     },
                                     stateClock: { () -> UInt64 in log.now },
                                     announce: { (text: String) -> Void in log.announcements.append(text) })
        let clock = MIDIClockCoordinator(input: input, tempo: tempo, defaults: defaults,
                                         now: { () -> UInt64 in log.now }, runsTicker: false)
        return Harness(defaults: defaults, suite: suite, inputProvider: inputProvider, input: input, tempo: tempo,
                       clock: clock, log: log)
    }

    private func cleanUp(_ h: Harness) {
        h.clock.setFollowing(false)
        h.defaults.removePersistentDomain(forName: h.suite)
    }

    /// Sends `count` clock pulses at 120 BPM from the harness's time, draining every 8 pulses (about 30 Hz).
    private func sendClock(_ h: Harness, count: Int) {
        let start: UInt64 = h.log.now
        for i in 0..<count {
            let time: UInt64 = start + UInt64((Double(i) * Self.period120).rounded())
            h.log.now = time
            h.inputProvider.send([0xF8], timestamp: time)
            if i % 8 == 7 { h.input.drain() }
        }
        h.input.drain()
        h.log.now = start + UInt64((Double(count) * Self.period120).rounded())
    }

    func testTheSnapshotFollowsTheClockWhileFollowing() throws {
        let h: Harness = try makeHarness(following: true)
        defer { cleanUp(h) }
        XCTAssertTrue(h.input.isReceiving, "following makes the input receive")
        XCTAssertTrue(h.inputProvider.send([0xFA], timestamp: h.log.now))
        h.input.drain()
        sendClock(h, count: 48)
        XCTAssertEqual(h.tempo.snapshot.origin, .midiClock)
        XCTAssertEqual(h.tempo.snapshot.bpm ?? 0, 120, accuracy: 0.1)
        XCTAssertNotNil(h.tempo.snapshot.anchorNanoseconds, "Start gives the grid a phase")
        XCTAssertEqual(h.tempo.readout, .midiClock(bpm: h.tempo.snapshot.bpm ?? 0))
        XCTAssertEqual(MIDIClockCoordinator.statusText(h.clock.status, isListening: true), "MIDI clock: 120.0 BPM")
        XCTAssertEqual(h.clock.statusText, "MIDI clock: 120.0 BPM")
    }

    func testTheClockIsIgnoredWhileNotFollowing() throws {
        let h: Harness = try makeHarness(following: false)
        defer { cleanUp(h) }
        XCTAssertFalse(h.input.isReceiving, "nothing needs the input")
        h.clock.setFollowing(true)
        h.clock.setFollowing(false)   // on and off again: the input stops, the stored value is removed
        XCTAssertNil(h.defaults.object(forKey: MIDIClockCoordinator.followKey))
        XCTAssertFalse(h.input.isReceiving)
        let before: TempoSnapshot = h.tempo.snapshot
        sendClock(h, count: 48)
        XCTAssertEqual(h.tempo.snapshot, before)
        XCTAssertEqual(h.tempo.snapshot.origin, TempoOrigin.none)
        XCTAssertEqual(h.clock.status, .noClock)
    }

    func testATapWhileTheClockLeadsAnnouncesAndLosingTheClockFallsBackToIt() throws {
        let h: Harness = try makeHarness(following: true)
        defer { cleanUp(h) }
        for _ in 0..<4 { h.tempo.tap() }   // 120 BPM by tap (500 ms apart)
        XCTAssertEqual(h.tempo.snapshot.origin, .manual)
        h.log.announcements = []
        h.inputProvider.send([0xFA], timestamp: h.log.now)
        sendClock(h, count: 48)
        XCTAssertEqual(h.tempo.snapshot.origin, .midiClock)
        h.tempo.tap()
        XCTAssertEqual(h.log.announcements, [TempoCoordinator.midiClockNotice])
        XCTAssertEqual(h.tempo.snapshot.origin, .midiClock, "the clock keeps the tempo")
        h.log.now += 600_000_000   // 0.6 s without a pulse
        h.clock.tick()
        XCTAssertEqual(h.clock.status, .noClock)
        XCTAssertEqual(h.tempo.snapshot.origin, .manual, "falls back to the tapped tempo")
        XCTAssertEqual(h.tempo.snapshot.bpm ?? 0, 120, accuracy: 0.01)
    }

    func testStatusTexts() {
        XCTAssertEqual(MIDIClockCoordinator.statusText(.locked(bpm: 174.46), isListening: true), "MIDI clock: 174.5 BPM")
        XCTAssertEqual(MIDIClockCoordinator.statusText(.stopped, isListening: true), "MIDI clock: stopped")
        XCTAssertEqual(MIDIClockCoordinator.statusText(.outOfRange(bpm: 400), isListening: true), "MIDI clock: out of range")
        XCTAssertEqual(MIDIClockCoordinator.statusText(.acquiring, isListening: true), "MIDI clock: measuring")
        XCTAssertEqual(MIDIClockCoordinator.statusText(.noClock, isListening: true), "No MIDI clock")
        XCTAssertEqual(MIDIClockCoordinator.statusText(.locked(bpm: 120), isListening: false), "Turn on Listen for MIDI devices")
        XCTAssertEqual(TempoCoordinator.accessibilityValue(.midiClock(bpm: 120)), "120 BPM, MIDI clock")
        XCTAssertEqual(TempoCoordinator.stateText(.midiClock(bpm: 120)), "MIDI clock")
        XCTAssertEqual(SceneHUDContent.tempoSourceName(.midiClock(bpm: 120)), "MIDI clock")
    }
}
