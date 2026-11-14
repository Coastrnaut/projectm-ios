// HapticBeatAcceptanceTests.swift — ACC-007-T07, T10, T11 (specs/238-acc-007-haptic-beat-feedback; S1-S4, C3, C5).
// The roadmap acceptance: "Off setting produces zero haptic calls; high event rate is throttled."
// A fake player records every call; synthetic ANL-016 event streams are delivered on time through an injected
// clock (no wall clock), so every run gives the same pulses. Owner rule 7: each test well under a second.
import AnalysisFeatures
import FlashSafety
import PerformanceControl
import XCTest
@testable import projectM_iOS

@MainActor
private final class FakeHapticPlayer: HapticPlaying {
    var calls: [(strength: HapticPulseStrength, intensity: Double)] = []
    func play(strength: HapticPulseStrength, intensity: Double) { calls.append((strength, intensity)) }
}

/// A mutable clock the coordinator reads.
private final class StepClock: @unchecked Sendable {
    var now: UInt64 = 0
}

@MainActor
final class HapticBeatAcceptanceTests: XCTestCase {
    private static let ms: UInt64 = 1_000_000
    private static let start: UInt64 = 10_000_000_000

    private var player = FakeHapticPlayer()
    private var playersMade = 0
    private let clock = StepClock()
    private var clampValue = SafetyClamp.standard

    private func suite() -> UserDefaults {
        let name = "HapticBeatAcceptanceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: name) }
        return defaults
    }

    private func makeCoordinator(defaults: UserDefaults? = nil, tempo: TempoCoordinator? = nil, supports: Bool = true,
                                 active: Bool = true, lowPower: Bool = false) -> HapticBeatCoordinator {
        let conditions = HapticConditions(supportsHaptics: supports, isAppActive: { () -> Bool in active },
                                          isLowPowerMode: { () -> Bool in lowPower })
        let clock: StepClock = self.clock
        return HapticBeatCoordinator(defaults: defaults ?? suite(), tempo: tempo,
                                     clamp: { [unowned self] () -> SafetyClamp in self.clampValue },
                                     conditions: conditions, clock: { () -> UInt64 in clock.now },
                                     player: { [unowned self] () -> any HapticPlaying in
                                         self.playersMade += 1
                                         return self.player
                                     })
    }

    private func event(_ id: UInt64, _ kind: AnalysisEventKind, at time: UInt64) -> AnalysisEvent {
        AnalysisEvent(id: id, time: AnalysisTimestamp(session: 1, sessionSample: 0, timelineSample: 0, hostNanoseconds: time),
                      eventSample: 0, kind: kind)
    }

    private static let beat: AnalysisEventKind = .beat(bpm: 120, periodSamples: 22_050, confidence: 0.9)
    private static let weakBeat: AnalysisEventKind = .beat(bpm: 120, periodSamples: 22_050, confidence: 0.2)
    private static let kick: AnalysisEventKind = .transient(band: .kick, strength: 6, threshold: 3, level: -12, confidence: 0.8)
    private static let onset: AnalysisEventKind = .onset(strength: 0.8, threshold: 0.4)

    /// A dense stream: 30 events per second for `seconds`, cycling beat, kick, onset; delivered on time.
    /// Returns the bus times of the calls' events.
    @discardableResult
    private func feedDense(_ coordinator: HapticBeatCoordinator, seconds: Int = 60) -> [UInt64] {
        var pulseTimes: [UInt64] = []
        let kinds: [AnalysisEventKind] = [Self.beat, Self.kick, Self.onset]
        for i in 0..<(30 * seconds) {
            let t: UInt64 = Self.start + UInt64(i) * 33_333_333
            clock.now = t
            let before: Int = player.calls.count
            coordinator.handle(event(UInt64(i + 1), kinds[i % 3], at: t))
            if player.calls.count > before { pulseTimes.append(t) }
        }
        return pulseTimes
    }

    // MARK: S1 — Off: zero haptic calls

    func testOffMakesZeroHapticCallsOverADenseStream() {
        let coordinator = makeCoordinator()
        XCTAssertFalse(coordinator.enabled, "off by default")
        feedDense(coordinator)
        XCTAssertEqual(player.calls.count, 0)
        XCTAssertEqual(playersMade, 0, "no haptic generator is even created")
    }

    func testOffInstallsNoTempoObserverAndKeepsTheSlowPoll() {
        let defaults = suite()
        let tempo = TempoCoordinator()
        let coordinator = makeCoordinator(defaults: defaults, tempo: tempo)
        XCTAssertNil(tempo.analysisEventObserver)
        XCTAssertEqual(tempo.currentPollInterval, TempoCoordinator.pollInterval)
        coordinator.enabled = true
        XCTAssertNotNil(tempo.analysisEventObserver)
        XCTAssertEqual(tempo.currentPollInterval, .milliseconds(40))
        XCTAssertEqual(defaults.object(forKey: HapticBeatCoordinator.enabledKey) as? Bool, true)
        coordinator.enabled = false
        XCTAssertNil(tempo.analysisEventObserver, "off removes the observer at once")
        tempo.analysisEventObserver?(event(1, Self.beat, at: Self.start))
        XCTAssertEqual(player.calls.count, 0)
    }

    func testNoHapticHardwareInstallsNothingEvenWhenOn() {
        let tempo = TempoCoordinator()
        let coordinator = makeCoordinator(tempo: tempo, supports: false)
        coordinator.enabled = true
        XCTAssertNil(tempo.analysisEventObserver)
        XCTAssertEqual(tempo.currentPollInterval, TempoCoordinator.pollInterval)
        XCTAssertFalse(coordinator.isAvailable, "the Settings switch is disabled")
    }

    // MARK: S2 — On: a high event rate is throttled

    func testHighEventRateIsThrottled() {
        let coordinator = makeCoordinator()
        coordinator.enabled = true
        coordinator.choice = .kicks
        let times: [UInt64] = feedDense(coordinator)   // kicks at 10 per second, plus beats and onsets
        XCTAssertGreaterThan(times.count, 0)
        for (a, b) in zip(times, times.dropFirst()) {
            XCTAssertGreaterThanOrEqual(b - a, 150 * Self.ms, "never closer than the minimum interval")
        }
        for (i, t) in times.enumerated() where i >= 4 {
            XCTAssertGreaterThanOrEqual(t - times[i - 4], 1_000 * Self.ms, "at most 4 in any 1 s")
        }
        XCTAssertLessThanOrEqual(times.count, 180, "at most 180 in 60 s")
        XCTAssertGreaterThan(coordinator.gate.throttledCount, 0)

        let second = FakeHapticPlayer()
        player = second
        let again = makeCoordinator()
        again.enabled = true
        again.choice = .kicks
        XCTAssertEqual(feedDense(again), times, "deterministic with the injected clock")
    }

    func testLateEventsAreDroppedNotPlayedLate() {
        let coordinator = makeCoordinator()
        coordinator.enabled = true
        clock.now = Self.start + 500 * Self.ms
        coordinator.handle(event(1, Self.beat, at: Self.start))
        XCTAssertEqual(player.calls.count, 0)
        XCTAssertEqual(coordinator.gate.staleCount, 1)
    }

    // MARK: S3 — the choice filters

    func testEachChoicePulsesOnlyOnItsEvents() {
        let stream: [AnalysisEventKind] = [.sessionStarted(.attached), Self.beat, Self.kick, Self.weakBeat, Self.onset, Self.beat,
                                           Self.beat, Self.beat, Self.beat, Self.kick, Self.beat]
        func pulses(_ choice: HapticBeatChoice, _ strength: HapticPulseStrength) -> [Int] {
            player = FakeHapticPlayer()
            let coordinator = makeCoordinator()
            coordinator.enabled = true
            coordinator.choice = choice
            coordinator.strength = strength
            var hits: [Int] = []
            for (i, kind) in stream.enumerated() {
                let t: UInt64 = Self.start + UInt64(i) * 400 * Self.ms
                clock.now = t
                let before: Int = player.calls.count
                coordinator.handle(event(UInt64(i + 1), kind, at: t))
                if player.calls.count > before { hits.append(i) }
            }
            XCTAssertTrue(player.calls.allSatisfy { $0.strength == strength })
            return hits
        }
        XCTAssertEqual(pulses(.beats, .medium), [1, 5, 6, 7, 8, 10], "confident beats only")
        XCTAssertEqual(pulses(.downbeats, .strong), [1, 8], "beats 1 and 5")
        XCTAssertEqual(pulses(.kicks, .light), [2, 9])
    }

    // MARK: S4 — safety and conditions

    func testStrictLowPowerBackgroundAndMissingHardwareMakeNoCalls() {
        clampValue = SafetyClamp(profile: SensorySafetyProfile(preset: .strict), reduceFlashingSetting: false)
        let strict = makeCoordinator()
        strict.enabled = true
        feedDense(strict, seconds: 5)
        XCTAssertEqual(player.calls.count, 0, "Strict")

        clampValue = SafetyClamp(profile: SensorySafetyProfile(preset: .custom, custom: SensorySafetyLimits(
            flashesPerSecond: 3, riseLimitPerSecond: nil, intensityLimit: 0.2)), reduceFlashingSetting: false)
        let custom = makeCoordinator()
        custom.enabled = true
        feedDense(custom, seconds: 5)
        XCTAssertEqual(player.calls.count, 0, "Custom at or below Strict's intensity")

        clampValue = .standard
        for coordinator in [makeCoordinator(lowPower: true), makeCoordinator(active: false), makeCoordinator(supports: false)] {
            coordinator.enabled = true
            feedDense(coordinator, seconds: 5)
        }
        XCTAssertEqual(player.calls.count, 0, "Low Power Mode, background and no hardware")
        XCTAssertEqual(playersMade, 0)
    }

    func testReducedPlaysAtHalfIntensityAndReduceFlashingAloneChangesNothing() {
        clampValue = SafetyClamp(profile: SensorySafetyProfile(preset: .reduced), reduceFlashingSetting: false)
        let reduced = makeCoordinator()
        reduced.enabled = true
        feedDense(reduced, seconds: 2)
        XCTAssertFalse(player.calls.isEmpty)
        XCTAssertTrue(player.calls.allSatisfy { $0.intensity == 0.5 })

        player = FakeHapticPlayer()
        clampValue = SafetyClamp(profile: .standard, reduceFlashingSetting: true)
        let flashing = makeCoordinator()
        flashing.enabled = true
        feedDense(flashing, seconds: 2)
        XCTAssertFalse(player.calls.isEmpty)
        XCTAssertTrue(player.calls.allSatisfy { $0.intensity == 1 })
    }

    // MARK: C5 — storage

    func testPreferencesAreStoredOnChangeAndReadBack() {
        let defaults = suite()
        let coordinator = makeCoordinator(defaults: defaults)
        XCTAssertNil(defaults.object(forKey: HapticBeatCoordinator.enabledKey), "nothing stored until changed")
        XCTAssertEqual(coordinator.choice, .beats)
        XCTAssertEqual(coordinator.strength, .medium)
        coordinator.enabled = true
        coordinator.choice = .downbeats
        coordinator.strength = .light
        let reread = makeCoordinator(defaults: defaults)
        XCTAssertTrue(reread.enabled)
        XCTAssertEqual(reread.choice, .downbeats)
        XCTAssertEqual(reread.strength, .light)
        defaults.set("loud", forKey: HapticBeatCoordinator.strengthKey)
        XCTAssertEqual(makeCoordinator(defaults: defaults).strength, .medium, "unknown → Medium")
    }
}
