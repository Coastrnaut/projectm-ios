// MIDI-005-T07, T09, T11: 14-bit mappings in the app with the scripted MIDI system (a fake source), a manual clock and
// a manual timeout scheduler; `drain()` stands in for the display link, so nothing depends on wall time.
// * A 14-bit mapping drives Glow intensity with fine resolution (values between two 7-bit steps; S6); a coarse-only
//   controller still reaches both ends (S3).
// * Learn detects CC n + CC n+32 in the learning batch or within 500 ms and stores `hires=1`; CC n alone stays 7-bit;
//   a fine message after the window marks nothing (S4).
// * The switch saves at once, announces, adds no Undo step and is unavailable on CC ≥ 32 (R6).
import ParameterGraph
import PerformanceControl
import VisualParameters
import XCTest
@testable import projectM_iOS

@MainActor
final class MIDIHighResolutionCoordinatorTests: XCTestCase {
    @MainActor private final class Log {
        var now: UInt64 = 1_000_000_000
        var announcements: [String] = []
        var applied: [[ParameterID: Double]] = []
    }

    private struct Harness {
        let defaults: UserDefaults
        let suite: String
        let inputProvider: ScriptedMIDIInputProvider
        let input: MIDIInputCoordinator
        let mappings: MIDIMappingCoordinator
        let log: Log
    }

    private static let intensity: ParameterID = VisualParameterIDs.bloomIntensity

    private func makeHarness(lines: [String] = []) throws -> Harness {
        let suite: String = "MIDIHighResolutionCoordinatorTests-" + UUID().uuidString
        let defaults: UserDefaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.set(true, forKey: AppSettings.midiEnabledKey)
        if !lines.isEmpty { defaults.set(lines, forKey: MIDIMappingCoordinator.mappingsKey) }
        let settings = AppSettings(defaults: defaults, systemReduceMotion: false)
        let records: [MIDIEndpointRecord] = [
            MIDIEndpointRecord(uniqueID: 0x14B1, direction: .source, displayName: "Fine Faders", endpointName: "Port",
                               entityName: "Entity", deviceName: "Device"),
        ]
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
        mappings.applyValues = { (values: [ParameterID: Double]) -> Void in log.applied.append(values) }
        mappings.open()
        return Harness(defaults: defaults, suite: suite, inputProvider: inputProvider, input: input, mappings: mappings, log: log)
    }

    private func cleanUp(_ h: Harness) {
        h.mappings.close()
        h.defaults.removePersistentDomain(forName: h.suite)
    }

    /// One display tick's batch, `advance` nanoseconds after the previous one.
    private func send(_ h: Harness, _ bytes: [UInt8], advance: UInt64 = 10_000_000) {
        h.log.now += advance
        h.inputProvider.send(bytes, timestamp: h.log.now)
        h.input.drain()
    }

    private func stored(_ h: Harness) -> [String] {
        h.defaults.stringArray(forKey: MIDIMappingCoordinator.mappingsKey) ?? []
    }

    private static func range() throws -> (minimum: Double, maximum: Double) {
        let descriptor = try XCTUnwrap(MIDIMappingCoordinator.visualRegistry().descriptor(for: intensity))
        guard case let .continuous(minimum, maximum, _, _, _) = descriptor.kind else { throw XCTSkip("not continuous") }
        return (minimum, maximum)
    }

    // MARK: S6 — fine resolution in the live value

    func testA14BitMappingDrivesTheParameterBetweenTwo7BitSteps() throws {
        let h: Harness = try makeHarness(lines: ["cc:0:7=effect.bloom.intensity;hires=1"])
        defer { cleanUp(h) }
        let (minimum, maximum) = try Self.range()
        let span: Double = maximum - minimum
        send(h, [0xB0, 0x07, 0x40, 0xB0, 0x27, 0x00])   // MSB 0x40, LSB 0x00 → 8192/16383
        let base: Double = try XCTUnwrap(h.mappings.liveValues[Self.intensity])
        XCTAssertEqual(base, minimum + 8192.0 / 16383.0 * span, accuracy: 1e-9)
        send(h, [0xB0, 0x27, 0x40])                     // LSB 0x40: half a 7-bit step higher
        let fine: Double = try XCTUnwrap(h.mappings.liveValues[Self.intensity])
        XCTAssertEqual(fine, minimum + Double(0x40 * 128 + 0x40) / 16383.0 * span, accuracy: 1e-9)
        let step7: Double = span / 127
        XCTAssertGreaterThan(fine, base)
        XCTAssertLessThan(fine - base, step7, "the value moved by less than one 7-bit step")
        XCTAssertEqual(h.log.applied.last?[Self.intensity], fine, "pushed to the native host")
        send(h, [0xB0, 0x07, 0x7F, 0xB0, 0x27, 0x7F])
        XCTAssertEqual(h.mappings.liveValues[Self.intensity], maximum, "127/127 is exactly the maximum")
        XCTAssertEqual(stored(h), ["cc:0:7=effect.bloom.intensity;hires=1"], "only the flag is stored, never a value")
    }

    // MARK: S3 — a coarse-only controller

    func testACoarseOnlyControllerOnA14BitMappingReachesBothEnds() throws {
        let h: Harness = try makeHarness(lines: ["cc:0:7=effect.bloom.intensity;hires=1"])
        defer { cleanUp(h) }
        let (minimum, maximum) = try Self.range()
        send(h, [0xB0, 0x07, 0x7F])
        XCTAssertEqual(h.mappings.liveValues[Self.intensity], maximum)
        send(h, [0xB0, 0x07, 0x00])
        XCTAssertEqual(h.mappings.liveValues[Self.intensity], minimum)
    }

    // MARK: S4 — learn detects the pair

    func testLearnDetectsTheFineControllerInTheLearningBatchOrWithin500ms() throws {
        let h: Harness = try makeHarness()
        defer { cleanUp(h) }
        h.mappings.startLearning(Self.intensity)
        send(h, [0xB0, 0x07, 0x40, 0xB0, 0x27, 0x10])   // coarse and fine in one batch
        XCTAssertEqual(stored(h), ["cc:0:7=effect.bloom.intensity;hires=1"])
        XCTAssertEqual(h.mappings.statusText, "Glow intensity uses 14-bit control (CC 7 and CC 39).")
        XCTAssertEqual(h.log.announcements.suffix(2), ["Glow intensity mapped to CC 7 on channel 1.",
                                                       "Glow intensity uses 14-bit control (CC 7 and CC 39)."])
        XCTAssertTrue(h.mappings.liveValues.isEmpty, "the learning gesture applies no value")
        XCTAssertTrue(h.mappings.canUndo, "the learn is the Undo step")
        h.mappings.undo()
        XCTAssertEqual(stored(h), [], "one Undo removes the 14-bit mapping")

        h.mappings.startLearning(Self.intensity)
        send(h, [0xB2, 0x05, 0x40])                     // channel 3, CC 5
        send(h, [0xB2, 0x25, 0x00], advance: 400_000_000)   // its fine part 400 ms later
        XCTAssertEqual(stored(h), ["cc:2:5=effect.bloom.intensity;hires=1"])
    }

    func testASingleControllerOrALateFineMessageStays7Bit() throws {
        let h: Harness = try makeHarness()
        defer { cleanUp(h) }
        h.mappings.startLearning(Self.intensity)
        send(h, [0xB0, 0x07, 0x40])
        send(h, [0xB0, 0x07, 0x41])
        XCTAssertEqual(stored(h), ["cc:0:7=effect.bloom.intensity"], "CC 7 alone stays 7-bit")
        send(h, [0xB0, 0x27, 0x10], advance: 600_000_000)   // after the 500 ms window
        XCTAssertEqual(stored(h), ["cc:0:7=effect.bloom.intensity"], "too late: nothing marked")
        XCTAssertFalse(h.log.announcements.contains { (text: String) -> Bool in text.contains("14-bit") })
    }

    // MARK: R6 — the switch

    func testTheSwitchSavesAnnouncesAndIsOnlyForCoarseControllers() throws {
        let h: Harness = try makeHarness(lines: ["cc:0:7=effect.bloom.intensity;invert=1",
                                                 "cc:0:50=" + VisualParameterIDs.bloomRadius.rawValue])
        defer { cleanUp(h) }
        XCTAssertTrue(h.mappings.canUseHighResolution(for: Self.intensity))
        XCTAssertFalse(h.mappings.canUseHighResolution(for: VisualParameterIDs.bloomRadius), "CC 50 has no fine part")
        XCTAssertFalse(h.mappings.canUseHighResolution(for: VisualParameterIDs.bloomKnee), "not mapped")

        h.mappings.setHighResolution(true, for: Self.intensity)
        XCTAssertEqual(stored(h).first, "cc:0:7=effect.bloom.intensity;invert=1;hires=1")
        XCTAssertEqual(h.mappings.rows.first { (row: MIDIMappingRow) -> Bool in row.parameter == Self.intensity }?.curveSummary,
                       "Linear, inverted, 14-bit")
        h.mappings.setHighResolution(true, for: Self.intensity)   // unchanged: nothing announced
        h.mappings.setHighResolution(true, for: VisualParameterIDs.bloomRadius)   // CC 50: ignored
        XCTAssertEqual(stored(h).last, "cc:0:50=" + VisualParameterIDs.bloomRadius.rawValue)
        h.mappings.setHighResolution(false, for: Self.intensity)
        XCTAssertEqual(stored(h).first, "cc:0:7=effect.bloom.intensity;invert=1")
        XCTAssertEqual(h.log.announcements, ["Glow intensity 14-bit control on.", "Glow intensity 14-bit control off."])
        XCTAssertFalse(h.mappings.canUndo, "the switch is not an Undo step")
    }
}
