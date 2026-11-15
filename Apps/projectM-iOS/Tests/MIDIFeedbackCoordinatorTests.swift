// MIDI-009-T08, T11, T13: MIDI feedback in the app with the scripted MIDI system (a fake controller with an input and an
// output of the same device), a recording output as the mock destination, a manual clock and `drain()` standing in for
// the display link, so nothing depends on wall time (owner rule 7).
// * A base value change of a feedback mapping reaches the paired destination once; no paired destination, no value or
//   no `fb=1`: nothing (S7, R11).
// * Controller input is not echoed, a device's echo of a sent value changes nothing, panic drops pending feedback (S3;
//   R7, R8, R10).
// * The switch saves `fb=1` at once, announces, adds no Undo step and sends the current value once (R12).
import ParameterGraph
import PerformanceControl
import VisualParameters
import XCTest
@testable import projectM_iOS

@MainActor
final class MIDIFeedbackCoordinatorTests: XCTestCase {
    @MainActor private final class Log {
        var now: UInt64 = 1_000_000_000
        var announcements: [String] = []
        var base: [ParameterID: Double] = [:]
    }

    private struct Harness {
        let defaults: UserDefaults
        let suite: String
        let inputProvider: ScriptedMIDIInputProvider
        let input: MIDIInputCoordinator
        let mappings: MIDIMappingCoordinator
        let output: RecordingMIDIFeedbackOutput
        let log: Log
    }

    private static let intensity: ParameterID = VisualParameterIDs.bloomIntensity
    private static let destinationID: Int32 = 0x0F_B002

    private func makeHarness(lines: [String], withOutputEndpoint: Bool = true) throws -> Harness {
        let suite: String = "MIDIFeedbackCoordinatorTests-" + UUID().uuidString
        let defaults: UserDefaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.set(true, forKey: AppSettings.midiEnabledKey)
        defaults.set(lines, forKey: MIDIMappingCoordinator.mappingsKey)
        let settings = AppSettings(defaults: defaults, systemReduceMotion: false)
        var records: [MIDIEndpointRecord] = [
            MIDIEndpointRecord(uniqueID: 0x0F_B001, direction: .source, displayName: "LED Knobs", endpointName: "Port",
                               entityName: "Entity", deviceName: "LED Knobs"),
            MIDIEndpointRecord(uniqueID: 0x0F_B003, direction: .destination, displayName: "Synth", deviceName: "Synth"),
        ]
        if withOutputEndpoint {
            records.append(MIDIEndpointRecord(uniqueID: Self.destinationID, direction: .destination, displayName: "LED Knobs",
                                              endpointName: "Port", entityName: "Entity", deviceName: "LED Knobs"))
        }
        let scheduler = ManualMIDIScheduler()
        let discovery = MIDIDiscoveryCoordinator(
            settings: settings,
            discovery: MIDIEndpointDiscovery(provider: ScriptedMIDIEndpointProvider(records: records), scheduler: scheduler.scheduler))
        _ = scheduler.runAll()
        let inputProvider = ScriptedMIDIInputProvider()
        let input = MIDIInputCoordinator(service: MIDIInputService(provider: inputProvider), discovery: discovery,
                                         drivesDisplayLink: false)
        let log = Log()
        let mappings = MIDIMappingCoordinator(
            registry: MIDIMappingCoordinator.visualRegistry(), applied: MIDIMappingCoordinator.appliedIDs, input: input,
            discovery: discovery, defaults: defaults,
            announce: { (text: String) -> Void in log.announcements.append(text) },
            clock: { () -> UInt64 in log.now },
            scheduler: { (_: UInt64, _: @escaping @MainActor () -> Void) -> (@MainActor () -> Void) in { () -> Void in } })
        let output = RecordingMIDIFeedbackOutput()
        mappings.feedbackOutput = output
        // The host's base: the manual value with the MIDI live values in place (as `glow.applying(externalValues)`).
        mappings.feedbackValues = { [weak mappings] () -> [ParameterID: Double] in
            var values: [ParameterID: Double] = log.base
            values.merge(mappings?.liveValues ?? [:]) { (_: Double, live: Double) -> Double in live }
            return values
        }
        mappings.open()
        return Harness(defaults: defaults, suite: suite, inputProvider: inputProvider, input: input, mappings: mappings,
                       output: output, log: log)
    }

    private func cleanUp(_ h: Harness) {
        h.mappings.close()
        h.defaults.removePersistentDomain(forName: h.suite)
    }

    /// One display tick, 40 ms after the previous one, with `bytes` from the controller (if any).
    private func tick(_ h: Harness, _ bytes: [UInt8] = []) {
        h.log.now += 40_000_000
        if !bytes.isEmpty { h.inputProvider.send(bytes, timestamp: h.log.now) }
        h.input.drain()
    }

    private static func code(_ value: Double, line: String) throws -> UInt8 {
        let binding = try XCTUnwrap(MIDIControlBinding(storageLine: line))
        let descriptor = try XCTUnwrap(MIDIMappingCoordinator.visualRegistry().descriptor(for: binding.target))
        return UInt8(try XCTUnwrap(MIDIFeedbackQuantizer.code(for: value, binding: binding, descriptor: descriptor)))
    }

    private static func range() throws -> (minimum: Double, maximum: Double) {
        let descriptor = try XCTUnwrap(MIDIMappingCoordinator.visualRegistry().descriptor(for: intensity))
        guard case let .continuous(minimum, maximum, _, _, _) = descriptor.kind else { throw XCTSkip("not continuous") }
        return (minimum, maximum)
    }

    // MARK: S7 — the mock destination receives feedback

    func testABaseValueChangeReachesThePairedDestinationOnce() throws {
        let line = "cc:0:7=effect.bloom.intensity;fb=1"
        let h: Harness = try makeHarness(lines: [line])
        defer { cleanUp(h) }
        let (minimum, maximum) = try Self.range()
        h.log.base[Self.intensity] = minimum
        tick(h)
        XCTAssertEqual(h.output.sends.count, 1, "the current state once")
        XCTAssertEqual(h.output.sends.first?.destinations, [.unique(Self.destinationID)], "only the paired output")
        XCTAssertEqual(h.output.messages, [MIDIFeedbackMessage(channel: 0, controller: 7, value: 0)])
        let middle: Double = minimum + (maximum - minimum) * 0.6
        h.log.base[Self.intensity] = middle   // a scene, the slider or OSC changed the glow
        tick(h)
        XCTAssertEqual(h.output.messages.last, MIDIFeedbackMessage(channel: 0, controller: 7, value: try Self.code(middle, line: line)))
        for _ in 0..<5 { tick(h) }
        XCTAssertEqual(h.output.messages.count, 2, "no change, nothing more")
    }

    func testNothingIsSentWithoutAPairedDestinationAValueOrTheFlag() throws {
        let unpaired: Harness = try makeHarness(lines: ["cc:0:7=effect.bloom.intensity;fb=1"], withOutputEndpoint: false)
        defer { cleanUp(unpaired) }
        unpaired.log.base[Self.intensity] = 0.5
        for _ in 0..<3 { tick(unpaired) }
        XCTAssertTrue(unpaired.output.sends.isEmpty, "an input-only controller gets nothing (and the Synth is not paired)")

        let noValue: Harness = try makeHarness(lines: ["cc:0:7=effect.bloom.intensity;fb=1"])
        defer { cleanUp(noValue) }
        for _ in 0..<3 { tick(noValue) }
        XCTAssertTrue(noValue.output.sends.isEmpty, "no native visual: no value, nothing sent")

        let off: Harness = try makeHarness(lines: ["cc:0:7=effect.bloom.intensity"])
        defer { cleanUp(off) }
        off.log.base[Self.intensity] = 0.5
        for _ in 0..<3 { tick(off) }
        XCTAssertTrue(off.output.sends.isEmpty, "feedback is opt-in")
    }

    // MARK: S3 — no echo, no loop, panic

    func testControllerInputIsNotEchoed() throws {
        let line = "cc:0:7=effect.bloom.intensity;fb=1"
        let h: Harness = try makeHarness(lines: [line])
        defer { cleanUp(h) }
        let (minimum, _) = try Self.range()
        h.log.base[Self.intensity] = minimum
        tick(h)
        XCTAssertEqual(h.output.messages.count, 1)
        for value in stride(from: UInt8(10), through: 120, by: 10) { tick(h, [0xB0, 0x07, value]) }   // the user turns the knob
        for _ in 0..<5 { tick(h) }
        XCTAssertEqual(h.output.messages.count, 1, "the controller already shows its own values")
        XCTAssertNotNil(h.mappings.liveValues[Self.intensity], "the knob drove the glow")
    }

    func testADevicesEchoOfASentValueIsDroppedAndPanicDropsPendingFeedback() throws {
        let line = "cc:0:7=effect.bloom.intensity;fb=1"
        let h: Harness = try makeHarness(lines: [line])
        defer { cleanUp(h) }
        let (minimum, maximum) = try Self.range()
        h.log.base[Self.intensity] = maximum
        tick(h)
        XCTAssertEqual(h.output.messages, [MIDIFeedbackMessage(channel: 0, controller: 7, value: 127)])
        tick(h, [0xB0, 0x07, 0x7F])   // the device echoes what it received
        XCTAssertTrue(h.mappings.liveValues.isEmpty, "the echo was dropped, not applied")
        h.log.base[Self.intensity] = minimum
        h.mappings.panic()
        for _ in 0..<5 { tick(h) }
        XCTAssertEqual(h.output.messages.count, 1, "panic: the pending change is not sent")
        XCTAssertEqual(h.log.announcements.last, MIDIMappingCoordinator.panicText)
    }

    // MARK: R12 — the switch

    func testTheSwitchSavesAnnouncesAddsNoUndoAndSendsTheCurrentValueOnce() throws {
        let h: Harness = try makeHarness(lines: ["cc:0:7=effect.bloom.intensity;hires=1"])
        defer { cleanUp(h) }
        let (_, maximum) = try Self.range()
        h.log.base[Self.intensity] = maximum
        tick(h)
        XCTAssertTrue(h.output.sends.isEmpty, "off by default")
        h.mappings.setFeedback(true, for: Self.intensity)
        XCTAssertEqual(h.defaults.stringArray(forKey: MIDIMappingCoordinator.mappingsKey), ["cc:0:7=effect.bloom.intensity;hires=1;fb=1"])
        XCTAssertEqual(h.log.announcements.last, "Glow intensity feedback on.")
        XCTAssertFalse(h.mappings.canUndo, "the switch is not an Undo step")
        XCTAssertEqual(h.mappings.rows.first { (row: MIDIMappingRow) -> Bool in row.parameter == Self.intensity }?.curveSummary,
                       "Linear, 14-bit, feedback")
        tick(h)
        XCTAssertEqual(h.output.messages, [MIDIFeedbackMessage(channel: 0, controller: 7, value: 127),
                                           MIDIFeedbackMessage(channel: 0, controller: 39, value: 127)], "14-bit: coarse then fine")
        h.mappings.setFeedback(false, for: Self.intensity)
        XCTAssertEqual(h.log.announcements.last, "Glow intensity feedback off.")
        h.log.base[Self.intensity] = 0
        for _ in 0..<3 { tick(h) }
        XCTAssertEqual(h.output.messages.count, 2, "off: nothing more")
    }
}
