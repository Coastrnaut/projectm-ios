// MIDI-003-T09, T11, T12, T14: MIDI learn in the app with a scripted MIDI system (discovery and input), a manual
// clock and a manual timeout scheduler; `drain()` stands in for the display link, so nothing depends on wall time.
// * The row's acceptance (S1): one control change creates one binding and ends learn mode; a second creates nothing.
// * One binding per batch (S2), ineligible messages, Cancel, timeout, listening off (S3, R6), move and replace (S4),
//   values and the stored manual setting (R7, R8), delete, Undo, persistence and the stored form's privacy (S6, R4),
//   announcements (R11), the input client only while needed (R12), the glow under Strict (S5).
import Metal
import ParameterGraph
import PerformanceControl
import VisualEffects
import VisualGenerators
import VisualParameters
import FlashSafety
import LibraryBackup
import XCTest
@testable import projectM_iOS

@MainActor
final class MIDIMappingCoordinatorTests: XCTestCase {
    private final class ManualClock {
        var now: UInt64 = 1_000_000_000
    }

    /// Timers the coordinator scheduled; `fire()` runs the pending ones.
    @MainActor private final class ManualTimeouts {
        var pending: [(id: Int, work: @MainActor () -> Void)] = []
        var cancelled: Set<Int> = []
        private var next = 0

        func schedule(_ nanoseconds: UInt64, _ work: @escaping @MainActor () -> Void) -> (@MainActor () -> Void) {
            next += 1
            let id: Int = next
            pending.append((id, work))
            return { [weak self] () -> Void in self?.cancelled.insert(id) }
        }

        var live: Int { pending.filter { (entry: (id: Int, work: @MainActor () -> Void)) -> Bool in !cancelled.contains(entry.id) }.count }

        func fire() {
            let due = pending
            pending = []
            for entry in due where !cancelled.contains(entry.id) { entry.work() }
        }
    }

    private struct Harness {
        let settings: AppSettings
        let defaults: UserDefaults
        let suite: String
        let discovery: MIDIDiscoveryCoordinator
        let inputProvider: ScriptedMIDIInputProvider
        let input: MIDIInputCoordinator
        let mappings: MIDIMappingCoordinator
        let clock: ManualClock
        let timeouts: ManualTimeouts
        let announcements: AnnouncementLog
        let applied: AppliedLog
    }

    @MainActor private final class AnnouncementLog { var texts: [String] = [] }
    @MainActor private final class AppliedLog { var values: [[ParameterID: Double]] = [] }

    static let secretName = "Secret Keys"
    static let secretID: Int32 = 0x5EC2E7
    private static let intensity: ParameterID = VisualParameterIDs.bloomIntensity
    private static let radius: ParameterID = VisualParameterIDs.bloomRadius

    private static let secretRecords: [MIDIEndpointRecord] = [
        MIDIEndpointRecord(uniqueID: secretID, direction: .source, displayName: secretName, endpointName: "Secret Port",
                           entityName: "Secret Entity", deviceName: "Secret Device"),
    ]

    private func makeHarness(enabled: Bool = true, suite existing: String? = nil) throws -> Harness {
        let suite: String = existing ?? "MIDIMappingCoordinatorTests-" + UUID().uuidString
        let defaults: UserDefaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.set(enabled, forKey: AppSettings.midiEnabledKey)
        let settings = AppSettings(defaults: defaults, systemReduceMotion: false)
        let endpoints = ScriptedMIDIEndpointProvider(records: Self.secretRecords)
        let scheduler = ManualMIDIScheduler()
        let discovery = MIDIDiscoveryCoordinator(settings: settings,
                                                 discovery: MIDIEndpointDiscovery(provider: endpoints, scheduler: scheduler.scheduler))
        _ = scheduler.runAll()
        let inputProvider = ScriptedMIDIInputProvider()
        let input = MIDIInputCoordinator(service: MIDIInputService(provider: inputProvider), discovery: discovery,
                                         drivesDisplayLink: false)
        let clock = ManualClock()
        let timeouts = ManualTimeouts()
        let announcements = AnnouncementLog()
        let applied = AppliedLog()
        let mappings = MIDIMappingCoordinator(
            registry: MIDIMappingCoordinator.visualRegistry(), applied: MIDIMappingCoordinator.appliedIDs, input: input,
            discovery: discovery, defaults: defaults,
            announce: { (text: String) -> Void in announcements.texts.append(text) },
            clock: { () -> UInt64 in clock.now },
            scheduler: { (nanoseconds: UInt64, work: @escaping @MainActor () -> Void) -> (@MainActor () -> Void) in
                timeouts.schedule(nanoseconds, work)
            })
        mappings.applyValues = { (values: [ParameterID: Double]) -> Void in applied.values.append(values) }
        mappings.open()
        return Harness(settings: settings, defaults: defaults, suite: suite, discovery: discovery, inputProvider: inputProvider,
                       input: input, mappings: mappings, clock: clock, timeouts: timeouts, announcements: announcements,
                       applied: applied)
    }

    private func cleanUp(_ h: Harness) {
        h.mappings.close()
        h.defaults.removePersistentDomain(forName: h.suite)
    }

    private func send(_ h: Harness, _ bytes: [UInt8]) {
        h.clock.now += 10_000_000
        h.inputProvider.send(bytes, timestamp: h.clock.now)
        h.input.drain()
    }

    private func controls(_ h: Harness) -> [String] {
        h.mappings.bindings.storageLines
    }

    // MARK: S1 — the acceptance

    func testOneControlChangeCreatesOneBindingAndExitsLearnMode() throws {
        let h: Harness = try makeHarness()
        defer { cleanUp(h) }
        XCTAssertFalse(h.mappings.isInputClientRegistered, "no client without learning or bindings (R12)")
        h.mappings.startLearning(Self.intensity)
        XCTAssertTrue(h.mappings.isLearning)
        XCTAssertTrue(h.input.isReceiving, "learning receives")
        XCTAssertEqual(h.mappings.statusText, "Move a control on your MIDI device to map Glow intensity…")

        send(h, [0xB0, 0x07, 0x64])   // CC 7, channel 1, value 100
        XCTAssertEqual(controls(h), ["cc:0:7=effect.bloom.intensity"])
        XCTAssertFalse(h.mappings.isLearning, "learn mode exits")
        XCTAssertEqual(h.mappings.statusText, "Glow intensity mapped to CC 7 on channel 1.")
        XCTAssertEqual(h.announcements.texts, ["Move a control on your MIDI device to map Glow intensity.",
                                               "Glow intensity mapped to CC 7 on channel 1."])
        XCTAssertTrue(h.mappings.liveValues.isEmpty, "the learning message applies no value")
        XCTAssertEqual(h.timeouts.live, 0, "the timeout is cancelled")
        let row = try XCTUnwrap(h.mappings.rows.first { (row: MIDIMappingRow) -> Bool in row.parameter == Self.intensity })
        XCTAssertEqual(row.control, "CC 7 · Ch 1")
        XCTAssertEqual(row.accessibilityLabel, "Glow intensity, CC 7, channel 1")

        send(h, [0xB0, 0x08, 0x40])   // a second control change
        XCTAssertEqual(controls(h), ["cc:0:7=effect.bloom.intensity"], "a second CC creates nothing new")
        XCTAssertTrue(h.mappings.isInputClientRegistered, "bindings keep the client (R12)")
    }

    func testABatchOfSeveralControlChangesCreatesOneBinding() throws {
        let h: Harness = try makeHarness()
        defer { cleanUp(h) }
        h.mappings.startLearning(Self.radius)
        h.inputProvider.send([0xB0, 0x14, 0x10, 0xB0, 0x15, 0x20, 0xB3, 0x16, 0x30], timestamp: h.clock.now)
        h.input.drain()
        XCTAssertEqual(controls(h), ["cc:0:20=effect.bloom.radius"])
        XCTAssertFalse(h.mappings.isLearning)
    }

    // MARK: Values (R7, R8)

    func testBoundValuesDriveTheLiveValueAndLeaveTheManualSettingAlone() throws {
        let h: Harness = try makeHarness()
        defer { cleanUp(h) }
        let manual: Double = h.settings.glowIntensity
        h.mappings.startLearning(Self.intensity)
        send(h, [0xB0, 0x07, 0x00])
        send(h, [0xB0, 0x07, 0x7F])
        XCTAssertEqual(h.mappings.liveValues, [Self.intensity: 1])
        XCTAssertEqual(h.applied.values.last, [Self.intensity: 1])
        send(h, [0xB0, 0x07, 0x00, 0xB0, 0x07, 0x7F, 0xB0, 0x07, 0x00])
        XCTAssertEqual(h.mappings.liveValues, [Self.intensity: 0], "the newest value in a batch wins")
        XCTAssertEqual(h.settings.glowIntensity, manual, "the stored manual setting is unchanged")
        XCTAssertEqual(h.defaults.stringArray(forKey: MIDIMappingCoordinator.mappingsKey), ["cc:0:7=effect.bloom.intensity"],
                       "only the binding is stored, never a value")
    }

    // MARK: S3 — never the wrong message; cancel; timeout; listening off

    func testIneligibleMessagesKeepLearning() throws {
        let h: Harness = try makeHarness()
        defer { cleanUp(h) }
        h.mappings.startLearning(Self.intensity)
        let noise: [UInt8] = [0x90, 0x3C, 0x64, 0x80, 0x3C, 0x00, 0xE0, 0x00, 0x40, 0xD0, 0x10, 0xC0, 0x05,
                              0xF0, 0x01, 0xF7, 0xF8, 0xFE, 0xFA, 0xFC, 0xB0, 0x79, 0x00, 0xB0, 0x7B, 0x00]
        send(h, noise)
        XCTAssertTrue(h.mappings.isLearning)
        XCTAssertTrue(controls(h).isEmpty)
    }

    func testCancelAndTimeoutEndLearningWithoutABinding() throws {
        let h: Harness = try makeHarness()
        defer { cleanUp(h) }
        h.mappings.startLearning(Self.intensity)
        h.mappings.cancelLearning()
        XCTAssertFalse(h.mappings.isLearning)
        XCTAssertEqual(h.mappings.statusText, MIDIMappingCoordinator.cancelledText)
        XCTAssertFalse(h.mappings.isInputClientRegistered)

        h.mappings.startLearning(Self.intensity)
        h.clock.now += MIDILearnSession<ParameterID>.timeoutNanoseconds
        h.timeouts.fire()
        XCTAssertFalse(h.mappings.isLearning)
        XCTAssertTrue(controls(h).isEmpty)
        XCTAssertEqual(h.mappings.statusText, MIDIMappingCoordinator.timedOutText)
        XCTAssertEqual(h.announcements.texts.last, MIDIMappingCoordinator.timedOutText, "the timeout is announced")
        XCTAssertFalse(h.mappings.isInputClientRegistered)
    }

    func testListeningOffEndsLearningAndDisablesLearn() throws {
        let h: Harness = try makeHarness()
        defer { cleanUp(h) }
        h.mappings.startLearning(Self.intensity)
        h.discovery.setEnabled(false)
        XCTAssertFalse(h.mappings.isLearning)
        XCTAssertFalse(h.mappings.canLearn)
        XCTAssertEqual(h.mappings.statusText, MIDIMappingCoordinator.stoppedText)
        h.mappings.startLearning(Self.intensity)
        XCTAssertFalse(h.mappings.isLearning, "Learn needs listening")

        let off: Harness = try makeHarness(enabled: false)
        defer { cleanUp(off) }
        XCTAssertEqual(off.mappings.statusText, MIDIMappingCoordinator.offText)
    }

    // MARK: S4 — move and replace; delete and Undo

    func testMovingAControlAndRelearningAParameterKeepOneBindingEach() throws {
        let h: Harness = try makeHarness()
        defer { cleanUp(h) }
        h.mappings.startLearning(Self.intensity)
        send(h, [0xB0, 0x07, 0x10])
        send(h, [0xB0, 0x07, 0x7F])
        XCTAssertEqual(h.mappings.liveValues, [Self.intensity: 1])
        h.mappings.startLearning(Self.radius)
        send(h, [0xB0, 0x07, 0x10])
        XCTAssertEqual(controls(h), ["cc:0:7=effect.bloom.radius"])
        XCTAssertEqual(h.mappings.statusText, "Glow radius mapped to CC 7 on channel 1 (moved from Glow intensity).")
        XCTAssertTrue(h.mappings.liveValues.isEmpty, "the parameter the control left returns to its manual value")
        h.mappings.startLearning(Self.radius)
        send(h, [0xB0, 0x09, 0x10])
        XCTAssertEqual(controls(h), ["cc:0:9=effect.bloom.radius"])
    }

    func testDeleteAndUndo() throws {
        let h: Harness = try makeHarness()
        defer { cleanUp(h) }
        h.mappings.startLearning(Self.intensity)
        send(h, [0xB0, 0x07, 0x10])
        send(h, [0xB0, 0x07, 0x7F])
        h.mappings.deleteMapping(Self.intensity)
        XCTAssertTrue(controls(h).isEmpty)
        XCTAssertTrue(h.mappings.liveValues.isEmpty)
        XCTAssertEqual(h.applied.values.last, [:], "deleting returns the parameter to its manual value at once")
        XCTAssertNil(h.defaults.object(forKey: MIDIMappingCoordinator.mappingsKey))
        XCTAssertTrue(h.mappings.canUndo)
        h.mappings.undo()
        XCTAssertEqual(controls(h), ["cc:0:7=effect.bloom.intensity"])
        XCTAssertEqual(h.defaults.stringArray(forKey: MIDIMappingCoordinator.mappingsKey), ["cc:0:7=effect.bloom.intensity"])
        XCTAssertFalse(h.mappings.canUndo, "one step")
        h.mappings.undo()   // nothing to undo: no change
        XCTAssertEqual(controls(h).count, 1)
        h.mappings.deleteMapping(Self.intensity)
        h.mappings.close()
        XCTAssertFalse(h.mappings.canUndo, "leaving the screen forgets Undo")
    }

    // MARK: S6 — persistence and privacy of the stored form

    func testMappingsSurviveARelaunchAndStoreNoIdentifier() throws {
        let h: Harness = try makeHarness()
        defer { cleanUp(h) }
        h.mappings.startLearning(Self.intensity)
        send(h, [0xB2, 0x07, 0x10])   // channel 3
        h.mappings.startLearning(Self.radius)
        send(h, [0xB0, 0x0A, 0x10])
        XCTAssertEqual(h.inputProvider.connectedSources, [.unique(Self.secretID)], "the secret source sent them")

        let relaunched: Harness = try makeHarness(suite: h.suite)
        XCTAssertEqual(relaunched.mappings.bindings, h.mappings.bindings)
        XCTAssertTrue(relaunched.mappings.isInputClientRegistered, "stored bindings receive at launch")
        XCTAssertTrue(relaunched.mappings.liveValues.isEmpty, "live values start empty")
        relaunched.mappings.close()

        // FILE-005: a backup carries the list; restored into fresh defaults it loads the same bindings.
        let backedUp: [String: LibrarySettingValue] = LibrarySettingsBridge.read(h.defaults)
        XCTAssertEqual(backedUp[MIDIMappingCoordinator.mappingsKey], .strings(h.mappings.bindings.storageLines))
        let restored: Harness = try makeHarness()
        defer { cleanUp(restored) }
        LibrarySettingsBridge.apply(backedUp, to: restored.defaults)
        let afterRestore: Harness = try makeHarness(suite: restored.suite)
        XCTAssertEqual(afterRestore.mappings.bindings, h.mappings.bindings)
        afterRestore.mappings.close()
        // FILE-011: the Settings category erases the list.
        LibrarySettingsBridge.remove(LibraryErasePolicy.settingKeys(.settings), from: restored.defaults)
        XCTAssertNil(restored.defaults.object(forKey: MIDIMappingCoordinator.mappingsKey))
        let afterErase: Harness = try makeHarness(suite: restored.suite)
        XCTAssertTrue(afterErase.mappings.bindings.isEmpty)
        afterErase.mappings.close()

        var haystack: [String] = h.mappings.bindings.storageLines + [h.mappings.statusText] + h.announcements.texts
        haystack += h.mappings.rows.map { (row: MIDIMappingRow) -> String in row.accessibilityLabel }
        for (key, value) in h.defaults.dictionaryRepresentation() { haystack += [key, String(describing: value)] }
        let needles: [String] = ["secret", "5ec2e7", String(Self.secretID), MIDIEndpointID.unique(Self.secretID).description]
        for text in haystack {
            for needle in needles {
                XCTAssertFalse(text.lowercased().contains(needle.lowercased()), "identifier \(needle) recorded in: \(text.prefix(120))")
            }
        }
    }

    func testOnlyTheGlowParametersAreLearnable() {
        let registry: ParameterRegistry = MIDIMappingCoordinator.visualRegistry()
        let ids: [ParameterID] = MIDILearnCatalog.learnable(in: registry, applied: MIDIMappingCoordinator.appliedIDs).map(\.id)
        XCTAssertEqual(ids, [VisualParameterIDs.bloomIntensity, VisualParameterIDs.bloomRadius,
                             VisualParameterIDs.bloomThreshold, VisualParameterIDs.bloomKnee])
    }

    // MARK: S5 — the glow under Strict (ACC-012)

    func testAMappedGlowIntensityIsCappedByStrict() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device in this simulator") }
        let host = try NativeSpectrumHost.make(device: device, reader: nil, barCount: .b32,
                                               glow: BloomParameters(enabled: true, intensity: 0.5))
        let unchanged: BloomParameters = host.effectiveGlow
        host.externalValues = [:]
        XCTAssertEqual(host.effectiveGlow, unchanged, "no external value: the FX-001 path")

        let h: Harness = try makeHarness()
        defer { cleanUp(h) }
        h.mappings.applyValues = { (values: [ParameterID: Double]) -> Void in host.externalValues = values }
        h.mappings.startLearning(Self.intensity)
        send(h, [0xB0, 0x07, 0x10])
        send(h, [0xB0, 0x07, 0x7F])
        XCTAssertEqual(host.effectiveGlow.intensity, 1, "Standard: the control reaches the top of the range")
        XCTAssertEqual(host.glow.intensity, 0.5, "the manual glow is unchanged")

        host.safetyClamp = SafetyClamp(profile: SensorySafetyProfile(preset: .strict), reduceFlashingSetting: false)
        let cap: Float = BloomParameters.intensityRange.upperBound * Float(SensorySafetyLimits.strict.intensityLimit)
        XCTAssertEqual(host.effectiveGlow.intensity, cap, accuracy: 1e-6, "Strict caps the mapped value")
        XCTAssertEqual(host.bloomParameters?.intensity ?? -1, cap, accuracy: 1e-6, "the bloom renders the capped value")

        // A host made after the values arrived gets them through the same push AppCoordinator does on creation.
        let later = try NativeSpectrumHost.make(device: device, reader: nil, barCount: .b32,
                                                glow: BloomParameters(enabled: true, intensity: 0.5))
        later.externalValues = h.mappings.liveValues
        XCTAssertEqual(later.effectiveGlow.intensity, 1)
        h.mappings.deleteMapping(Self.intensity)
        XCTAssertEqual(host.effectiveGlow.intensity, cap > 0.5 ? 0.5 : cap, accuracy: 1e-6, "back to the manual value, capped")
    }
}
