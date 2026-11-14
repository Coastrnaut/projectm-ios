// ParameterQuantizerAcceptanceTests.swift — MOD-017-T06, T08 (US1, US2; R2 to R9; S1, S3 to S5): the roadmap acceptance
// "Change requested between beats applies exactly once at next boundary" through the app's real write path
// (`ParameterInspectorTargets.quantizedTarget` over a real `AppSettings`, the app's `connect` wiring, SCN-015's lock
// and a real show over a temporary store). Synthetic 120 BPM grid and injected times; wake-ups off; no wall clock.
import Foundation
import LibraryBackup
import ParameterGraph
import PerformanceControl
import SceneFormat
import ShowControl
import ShowStorage
import TextLayer
import VisualParameters
import XCTest
@testable import projectM_iOS

@MainActor
final class ParameterQuantizerAcceptanceTests: XCTestCase {
    private typealias IDs = VisualParameterIDs
    static let anchor: UInt64 = 10_000_000_000
    static let beat: UInt64 = 500_000_000

    private var defaults: UserDefaults!
    private var settings: AppSettings!
    private var quantizer: ParameterQuantizer!
    private var now: UInt64 = 0
    private var hasCues = false
    private var announced: [String] = []
    private var tempo: TempoSnapshot = .none

    override func setUp() async throws {
        let suite = "MOD017-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        settings = AppSettings(defaults: defaults, systemReduceMotion: false)
        settings.glowEnabled = false
        quantizer = settings.parameterQuantizer
        quantizer.schedulesWakeUps = false
        var source = TempoSource()
        source.updateEstimate(TempoEstimate(bpm: 120, confidence: 1, beatNanoseconds: Self.anchor))
        tempo = source.snapshot
        quantizer.connect(settings: settings,
                          tempo: { [unowned self] () -> TempoSnapshot in self.tempo },
                          hasCues: { [unowned self] () -> Bool in self.hasCues },
                          announce: { [unowned self] (text: String) -> Void in self.announced.append(text) })
        quantizer.clock = { [unowned self] () -> UInt64 in self.now }
    }

    private func glowTarget() throws -> ParameterInspectorTarget {
        try XCTUnwrap(ParameterInspectorTargets.quantizedTarget(for: IDs.bloomEnabled, settings: settings))
    }

    /// Ticks every 10 ms from `start` through `end` and counts how often the glow changed.
    private func ticks(from start: UInt64, through end: UInt64) -> Int {
        var changes = 0
        var last: Bool = settings.glowEnabled
        var t: UInt64 = start
        while t <= end {
            now = t
            quantizer.tick(at: t)
            if settings.glowEnabled != last { changes += 1; last = settings.glowEnabled }
            t += 10_000_000
        }
        return changes
    }

    // MARK: - US1: Beat (S1, S5)

    func testGlowRequestedMidBeatAppliesExactlyOnceAtTheNextBeat() throws {
        quantizer.mode = .beat
        now = Self.anchor + 3 * Self.beat + 220_000_000
        let target: ParameterInspectorTarget = try glowTarget()
        target.set(.boolean(true))
        XCTAssertFalse(settings.glowEnabled, "not applied at the request")
        XCTAssertEqual(target.get(), .boolean(true), "the control shows the requested value")
        XCTAssertEqual(quantizer.queuedText(for: IDs.bloomEnabled), "Queued for the next beat")
        XCTAssertEqual(announced.last, ParameterQuantizer.name(IDs.bloomEnabled) + " queued for the next beat")

        let boundary: UInt64 = Self.anchor + 4 * Self.beat
        XCTAssertEqual(ticks(from: now, through: boundary - 1), 0, "not before the boundary")
        now = boundary
        quantizer.tick(at: boundary)
        XCTAssertTrue(settings.glowEnabled, "applied at the boundary")
        XCTAssertEqual(quantizer.appliedAtBoundary, 1)
        XCTAssertNil(quantizer.queuedText(for: IDs.bloomEnabled), "the indication is gone")
        XCTAssertTrue(announced.last?.hasSuffix(", applied") ?? false)

        settings.glowEnabled = false   // someone else turns it off: later beats must not re-apply the change
        XCTAssertEqual(ticks(from: boundary, through: boundary + 3 * Self.beat), 0, "never again")
        XCTAssertEqual(quantizer.appliedAtBoundary, 1)
    }

    func testLockAtTheBoundaryRefusesAndDropsTheChange() throws {
        quantizer.mode = .beat
        now = Self.anchor + 100_000_000
        try glowTarget().set(.boolean(true))
        settings.sceneLock.lock()
        quantizer.tick(at: Self.anchor + Self.beat)
        XCTAssertFalse(settings.glowEnabled, "a locked scene is never changed (S4)")
        XCTAssertEqual(settings.sceneLock.refusals, 1)
        XCTAssertTrue(quantizer.queue.isEmpty, "dropped, not retried")
        settings.sceneLock.unlock()
        quantizer.tick(at: Self.anchor + 2 * Self.beat)
        XCTAssertFalse(settings.glowEnabled)
    }

    func testContinuousAndNoTempoApplyAtOnce() throws {
        quantizer.mode = .beat
        let intensity: ParameterInspectorTarget = try XCTUnwrap(ParameterInspectorTargets.quantizedTarget(for: IDs.bloomIntensity, settings: settings))
        intensity.set(.continuous(0.25))
        XCTAssertEqual(settings.glowIntensity, 0.25, accuracy: 1e-12, "continuous parameters are never queued (R2)")
        tempo = .none
        try glowTarget().set(.boolean(true))
        XCTAssertTrue(settings.glowEnabled, "no tempo: applied now (R6)")
        XCTAssertTrue(announced.last?.hasSuffix(", applied now, no tempo") ?? false)
        XCTAssertTrue(quantizer.queue.isEmpty)
    }

    // MARK: - US2: Bar and Cue (S1)

    func testBarRequestWaitsForTheBarNotTheBeats() throws {
        quantizer.mode = .bar
        now = Self.anchor + Self.beat + 50_000_000
        let bars: ParameterInspectorTarget = try XCTUnwrap(ParameterInspectorTargets.quantizedTarget(for: IDs.circularSpectrumBarCount, settings: settings))
        let before: Int = settings.circularSpectrumBars
        let requested: Int = before == 64 ? 32 : 64
        bars.set(.enumeration(String(requested)))
        quantizer.tick(at: Self.anchor + 2 * Self.beat)
        quantizer.tick(at: Self.anchor + 3 * Self.beat)
        XCTAssertEqual(settings.circularSpectrumBars, before, "beats inside the bar change nothing")
        quantizer.tick(at: Self.anchor + 4 * Self.beat)
        XCTAssertEqual(settings.circularSpectrumBars, requested)
        settings.circularSpectrumBars = before
        quantizer.tick(at: Self.anchor + 8 * Self.beat)
        XCTAssertEqual(settings.circularSpectrumBars, before, "the next bar does not re-apply it")
    }

    func testCueModeAppliesOnTopOfTheNextCueOnceAndModeChangeClears() throws {
        let folder: URL = FileManager.default.temporaryDirectory.appendingPathComponent("MOD017-show-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let registry: ParameterRegistry = try SceneArchiveService.appRegistry()
        let show = ShowCoordinator(store: ShowStore(directory: folder), registry: registry)
        show.announce = { (_: String) in }
        let settings: AppSettings = self.settings
        let quantizer: ParameterQuantizer = self.quantizer
        show.applyScene = { (document: SceneDocument, warnings: [SceneIssue]) -> [String] in   // as AppCoordinator+Show wires it
            let apply: ShowSceneApply = ShowSceneSnapshot.apply(of: document, warnings: warnings, registry: registry)
            if let glow = apply.parameters[VisualParameterIDs.bloomEnabled]?.boolValue { settings.glowEnabled = glow }
            quantizer.cueApplied()
            return []
        }
        for index in 0..<3 {
            let look = ShowLook(visual: .circularSpectrum, bars: 64, orientation: .horizontal, spacing: 0.5, glowEnabled: false,
                                glowIntensity: 0.7, glowRadius: 0.03, glowThreshold: 0.4, text: TextOverlaySpec(message: ""),
                                photoID: nil, videoID: nil)
            XCTAssertTrue(show.addScene(ShowSceneSnapshot.document(look, id: UUID().uuidString, name: "Cue \(index)"), label: "Cue \(index)"))
        }
        hasCues = show.hasCues
        quantizer.mode = .cue
        try glowTarget().set(.boolean(true))
        XCTAssertEqual(quantizer.queuedText(for: IDs.bloomEnabled), "Queued for the next cue")
        quantizer.tick(at: UInt64.max)
        XCTAssertFalse(settings.glowEnabled, "time alone never applies a cue change")
        show.next()
        XCTAssertTrue(settings.glowEnabled, "applied once, on top of the cue's scene")
        XCTAssertEqual(quantizer.appliedAtBoundary, 1)
        show.next()
        XCTAssertFalse(settings.glowEnabled, "the next cue's scene stands: not re-applied")
        XCTAssertEqual(quantizer.appliedAtBoundary, 1)

        try glowTarget().set(.boolean(true))
        quantizer.mode = .beat
        XCTAssertTrue(quantizer.queue.isEmpty)
        XCTAssertEqual(announced.last, ParameterQuantizer.clearedAnnouncement)
    }

    // MARK: - Settings key (R1)

    func testModeIsStoredAndListedForResetAndBackupPolicy() {
        quantizer.mode = .bar
        XCTAssertEqual(defaults.string(forKey: ParameterQuantizer.key), "bar")
        XCTAssertEqual(ParameterQuantizer(defaults: defaults).mode, .bar, "remembered on the device")
        quantizer.mode = .off
        XCTAssertNil(defaults.object(forKey: ParameterQuantizer.key), "Off removes the key")
        XCTAssertTrue(AppSettings.allKeys.contains(ParameterQuantizer.key), "cleared by -uitestResetNotice")
        XCTAssertTrue(LibrarySettingsPolicy.excludedKeys.contains(ParameterQuantizer.key), "never backed up")
        XCTAssertFalse(LibrarySettingsPolicy.isIncluded(ParameterQuantizer.key))
        XCTAssertTrue(LibraryErasePolicy.erasableKeys.contains(ParameterQuantizer.key), "erased with Settings")
    }
}
