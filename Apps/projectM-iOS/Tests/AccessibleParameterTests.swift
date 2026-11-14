// AccessibleParameterTests.swift — ACC-005-T04, T10, T13 (specs/115-acc-005-voiceover-parameter-
// editing; contract C1; S1, S3, S4).
//
// * Formatter: the exact spoken strings per unit (C1.2).
// * Stepper: on-grid ±1 step, off-grid to the next grid value, clamps and ends.
// * Catalog: the glow follows the MOD-001 registry; identifiers and labels are the existing ones.
// * Table test: through each section's own `ParameterTarget` (the one its view uses), one increment
//   and one decrement change the real setting by exactly one step, and a fresh setting on the same
//   UserDefaults suite reads the stepped value (persisted).
// * End lane: ten end swipes within one second are announced once (fake clock, no wall clock).
// Each test makes its own UserDefaults suite and removes it; nothing is mutated in setUp/tearDown.
import AudioCore
import Foundation
import ParameterGraph
import TextLayer
import VideoLayer
import VisualParameters
import XCTest
@testable import projectM_iOS

@MainActor
private final class FakeClock {
    var now: Double = 100
}

@MainActor
final class AccessibleParameterTests: XCTestCase {
    private typealias Catalog = AccessibleParameterCatalog

    // MARK: Formatter (C1.2, S3)

    func testSpokenValuesNameTheirUnit() {
        XCTAssertEqual(SpokenValueFormatter.text(0.5, unit: .percent(decimals: 0)), "50 percent")
        XCTAssertEqual(SpokenValueFormatter.text(0.025, unit: .percent(decimals: 1)), "2.5 percent")
        XCTAssertEqual(SpokenValueFormatter.text(6, unit: .signedDecibels), "plus 6 decibels")
        XCTAssertEqual(SpokenValueFormatter.text(0, unit: .balance), "centered")   // AUD-010-R8
        XCTAssertEqual(SpokenValueFormatter.text(-0.3, unit: .balance), "30 percent left")
        XCTAssertEqual(SpokenValueFormatter.text(0, unit: .signedDecibels), "0 decibels")
        XCTAssertEqual(SpokenValueFormatter.text(-1, unit: .signedDecibels), "minus 1 decibel")
        XCTAssertEqual(SpokenValueFormatter.text(-12, unit: .signedDecibels), "minus 12 decibels")
        XCTAssertEqual(SpokenValueFormatter.text(-50, unit: .decibelsFullScale), "minus 50 decibels full scale")
        XCTAssertEqual(SpokenValueFormatter.text(180, unit: .milliseconds), "180 milliseconds")
        XCTAssertEqual(SpokenValueFormatter.text(1, unit: .milliseconds), "1 millisecond")
        XCTAssertEqual(SpokenValueFormatter.text(1.5, unit: .seconds), "1.5 seconds")
        XCTAssertEqual(SpokenValueFormatter.text(0.25, unit: .seconds), "0.25 seconds")
        XCTAssertEqual(VideoLoopControls.spokenText(1.5), "1.5 seconds", "MED-003 speaks through the same formatter")
    }

    // MARK: Stepper (R4, R7)

    func testStepsFollowTheGridFromTheMinimum() {
        let spec = AccessibleParameterSpec(id: "x", label: "X", range: 0.1...1, step: 0.05, unit: .percent(decimals: 0))
        XCTAssertEqual(ParameterStepper.step(0.7, .increment, spec: spec), ParameterStepResult(value: 0.75, end: nil))
        XCTAssertEqual(ParameterStepper.step(0.7, .decrement, spec: spec), ParameterStepResult(value: 0.65, end: nil))
        XCTAssertEqual(ParameterStepper.step(0.72, .increment, spec: spec).value, 0.75, "off the grid: the next value above")
        XCTAssertEqual(ParameterStepper.step(0.72, .decrement, spec: spec).value, 0.7, "off the grid: the next value below")
        XCTAssertEqual(ParameterStepper.step(0.1, .increment, spec: spec).value, 0.15, "no floating-point noise")
    }

    func testValuesClampAndEndsAreReported() {
        let spec = AccessibleParameterSpec(id: "x", label: "X", range: 0...0.23, step: 0.1, unit: .seconds)
        XCTAssertEqual(ParameterStepper.step(0.2, .increment, spec: spec), ParameterStepResult(value: 0.23, end: nil),
                       "an off-grid maximum is reachable")
        XCTAssertEqual(ParameterStepper.step(0.23, .increment, spec: spec), ParameterStepResult(value: 0.23, end: .maximum))
        XCTAssertEqual(ParameterStepper.step(0, .decrement, spec: spec), ParameterStepResult(value: 0, end: .minimum))
        XCTAssertEqual(ParameterStepper.step(5, .increment, spec: spec).end, .maximum, "a stored value past the end stays an end")
        let end = ParameterStepper.step(250, .increment, spec: Catalog.latencyOffset)
        XCTAssertEqual(AccessibleParameterAdjuster.endText(end, spec: Catalog.latencyOffset), "Maximum, 250 milliseconds")
        let start = ParameterStepper.step(-12, .decrement, spec: Catalog.inputTrim)
        XCTAssertEqual(AccessibleParameterAdjuster.endText(start, spec: Catalog.inputTrim), "Minimum, minus 12 decibels")
        XCTAssertNil(AccessibleParameterAdjuster.endText(ParameterStepper.step(0, .increment, spec: Catalog.inputTrim),
                                                         spec: Catalog.inputTrim))
    }

    // MARK: Catalog (R5, R6, R9)

    func testCatalogFollowsTheRegistryAndKeepsIdentifiers() throws {
        let glow: [(AccessibleParameterSpec, ParameterID)] = [(Catalog.glowIntensity, VisualParameterIDs.bloomIntensity),
                                                            (Catalog.glowRadius, VisualParameterIDs.bloomRadius),
                                                            (Catalog.glowThreshold, VisualParameterIDs.bloomThreshold)]
        for (spec, parameter) in glow {
            let registry = try XCTUnwrap(Catalog.registryRange(parameter))
            XCTAssertEqual(spec.range, registry.range, spec.id)
            let multiple: Double = spec.step / registry.hint
            XCTAssertEqual(multiple, multiple.rounded(), accuracy: 1e-9, "\(spec.id): a whole multiple of the registry hint")
        }
        XCTAssertEqual(Catalog.glowIntensity.step, 0.05, accuracy: 1e-12)
        XCTAssertEqual(Catalog.glowRadius.step, 0.005, accuracy: 1e-12)
        XCTAssertEqual(Catalog.glowRadius.range, 0.005...0.06)
        let ownStep: Set<String> = ["inputTrimSlider", "noiseGateThresholdSlider", "latencyOffsetSlider", "videoLoopIn", "videoLoopOut"]
        for spec in Catalog.all where !ownStep.contains(spec.id) {
            XCTAssertLessThanOrEqual(spec.stepCount, 25, "\(spec.id): at most 25 swipes end to end")
        }
        XCTAssertEqual(Catalog.all.map(\.id), ["glowIntensitySlider", "glowRadiusSlider", "glowThresholdSlider", "textSizeSlider",
                                               "textOutlineSlider", "inputTrimSlider", "noiseGateThresholdSlider",
                                               "latencyOffsetSlider", "videoLoopIn", "videoLoopOut", "playbackBalanceSlider"])
        XCTAssertEqual(Catalog.all.map(\.label), ["Intensity", "Radius", "Threshold", "Size", "Outline", "Input trim",
                                                  "Gate threshold", "Visual delay", "Loop in", "Loop out", "Balance"])
        XCTAssertEqual(Catalog.inputTrim.step, 1)
        XCTAssertEqual(Catalog.latencyOffset.step, LatencyOffsetSetting.step)
    }

    // MARK: Table test (S1)

    private struct Row {
        let spec: AccessibleParameterSpec
        let start: Double
        let target: ParameterTarget
        /// A fresh object on the same storage, read through the same target (a relaunch).
        let relaunched: @MainActor () -> Double
    }

    private func suite() throws -> (UserDefaults, String) {
        let name = "AccessibleParameterTests.\(UUID().uuidString)"
        return (try XCTUnwrap(UserDefaults(suiteName: name)), name)
    }

    func testEveryControlStepsTheRealSettingByOneStepAndPersists() throws {
        let (defaults, name) = try suite()
        defer { defaults.removePersistentDomain(forName: name) }
        let videoRoot = FileManager.default.temporaryDirectory.appendingPathComponent("AccessibleParameterTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: videoRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: videoRoot) }

        let settings = AppSettings(defaults: defaults, systemReduceMotion: false)
        let texts = TextOverlayCoordinator(store: TextOverlayStore(defaults: defaults))
        let trim = InputTrimSetting(defaults: defaults)
        let gate = NoiseGateSetting(defaults: defaults)
        let delay = LatencyOffsetSetting(defaults: defaults)
        let balance = PlaybackBalanceSetting(defaults: defaults)   // AUD-010
        let videoStore = VideoStore(directory: videoRoot, defaults: defaults)
        let id = UUID()
        let url = videoRoot.appendingPathComponent("\(id.uuidString).mov")
        try Data().write(to: url)
        videoStore.makeCurrent(StoredVideo(id: id, url: url))
        let duration: Int64 = 2_000_000_000
        func videoCoordinator() -> VideoCoordinator {
            let c = VideoCoordinator(store: videoStore, announce: { (_: String) -> Void in })
            c.loopSettle = .seconds(60)
            c.durationNanoseconds = duration
            return c
        }
        let videos = videoCoordinator()
        let loopSpec: (AccessibleParameterSpec) -> AccessibleParameterSpec = { (spec: AccessibleParameterSpec) in spec.withRange(0...2) }

        let rows: [Row] = [
            Row(spec: Catalog.glowIntensity, start: 0.5, target: SettingsView.glowTarget(settings, \.glowIntensity),
                relaunched: { SettingsView.glowTarget(AppSettings(defaults: defaults, systemReduceMotion: false), \.glowIntensity).get() }),
            Row(spec: Catalog.glowRadius, start: 0.02, target: SettingsView.glowTarget(settings, \.glowRadius),
                relaunched: { SettingsView.glowTarget(AppSettings(defaults: defaults, systemReduceMotion: false), \.glowRadius).get() }),
            Row(spec: Catalog.glowThreshold, start: 0.7, target: SettingsView.glowTarget(settings, \.glowThreshold),
                relaunched: { SettingsView.glowTarget(AppSettings(defaults: defaults, systemReduceMotion: false), \.glowThreshold).get() }),
            Row(spec: Catalog.textSize, start: 0.08, target: SettingsView.textTarget(texts, \.size),
                relaunched: { SettingsView.textTarget(TextOverlayCoordinator(store: TextOverlayStore(defaults: defaults)), \.size).get() }),
            Row(spec: Catalog.textOutline, start: 0.06, target: SettingsView.textTarget(texts, \.outlineWidth),
                relaunched: { SettingsView.textTarget(TextOverlayCoordinator(store: TextOverlayStore(defaults: defaults)), \.outlineWidth).get() }),
            Row(spec: Catalog.inputTrim, start: 0, target: InputTrimSection.target(trim),
                relaunched: { InputTrimSection.target(InputTrimSetting(defaults: defaults)).get() }),
            Row(spec: Catalog.noiseGateThreshold, start: -50, target: NoiseGateSection.target(gate),
                relaunched: { NoiseGateSection.target(NoiseGateSetting(defaults: defaults)).get() }),
            Row(spec: Catalog.latencyOffset, start: 100, target: LatencyOffsetSection.target(delay, mode: .inAppPlayback),
                relaunched: { LatencyOffsetSection.target(LatencyOffsetSetting(defaults: defaults), mode: .inAppPlayback).get() }),
            Row(spec: loopSpec(Catalog.videoLoopIn), start: 0.5, target: VideoLoopControls.inTarget(videos),
                relaunched: { VideoLoopControls.inTarget(videoCoordinator()).get() }),
            Row(spec: loopSpec(Catalog.videoLoopOut), start: 1.5, target: VideoLoopControls.outTarget(videos),
                relaunched: { VideoLoopControls.outTarget(videoCoordinator()).get() }),
            Row(spec: Catalog.playbackBalance, start: -0.3, target: PlaybackBalanceSection.target(balance),
                relaunched: { PlaybackBalanceSection.target(PlaybackBalanceSetting(defaults: defaults)).get() }),
        ]
        XCTAssertEqual(rows.map(\.spec.id), Catalog.all.map(\.id), "every control of the catalog is in the table")

        for row in rows {
            row.target.set(row.start)
            XCTAssertEqual(row.target.get(), row.start, accuracy: 1e-9, "\(row.spec.id): start")
            let up = AccessibleParameterAdjuster.adjust(row.spec, target: row.target, direction: .increment)
            XCTAssertTrue(up.moved, row.spec.id)
            XCTAssertEqual(row.target.get(), row.start + row.spec.step, accuracy: 1e-9, "\(row.spec.id): one step up")
            XCTAssertEqual(row.relaunched(), row.start + row.spec.step, accuracy: 1e-9, "\(row.spec.id): persisted")
            let down = AccessibleParameterAdjuster.adjust(row.spec, target: row.target, direction: .decrement)
            XCTAssertTrue(down.moved, row.spec.id)
            XCTAssertEqual(row.target.get(), row.start, accuracy: 1e-9, "\(row.spec.id): one step down")
            XCTAssertEqual(row.relaunched(), row.start, accuracy: 1e-9, "\(row.spec.id): persisted after the decrement")
        }
        XCTAssertEqual(Double(trim.control.decibels), 0, "the trim reaches the analysis control")
    }

    func testDelayStepsOnlyThePickedSourceAndReachesTheActiveControl() throws {
        let (defaults, name) = try suite()
        defer { defaults.removePersistentDomain(forName: name) }
        let delay = LatencyOffsetSetting(defaults: defaults)
        delay.activeMode = .microphone
        let target = LatencyOffsetSection.target(delay, mode: .microphone)
        _ = AccessibleParameterAdjuster.adjust(Catalog.latencyOffset, target: target, direction: .increment)
        XCTAssertEqual(delay.milliseconds(for: .microphone), 5)
        XCTAssertEqual(delay.milliseconds(for: .inAppPlayback), 0, "other sources keep their value")
        XCTAssertEqual(delay.control.targetFrames, LatencyOffset.frames(milliseconds: 5), "applied to the running delay")
    }

    // MARK: End lane (R7, S4)

    func testABurstOfEndSwipesIsAnnouncedOnce() {
        let clock = FakeClock()
        var posted: [String] = []
        var scheduled: [(Double, @MainActor () -> Void)] = []
        let announcer = AccessibilityAnnouncer(post: { (text: String) in posted.append(text) },
                                               now: { () -> Double in clock.now },
                                               schedule: { (delay: Double, action: @escaping @MainActor () -> Void) in
                                                   scheduled.append((delay, action))
                                               })
        let spec = Catalog.latencyOffset
        let target = ParameterTarget(get: { () -> Double in 250 }, set: { (_: Double) -> Void in XCTFail("no write at the end") })
        for _ in 0..<10 {
            let result = AccessibleParameterAdjuster.adjust(spec, target: target, direction: .increment)
            if let text = AccessibleParameterAdjuster.endText(result, spec: spec) { announcer.announce(text, kind: .parameter) }
            clock.now += 0.09
        }
        for (_, action) in scheduled { action() }   // the window closes: the identical repeat is dropped
        XCTAssertEqual(posted, ["Maximum, 250 milliseconds"])
        XCTAssertTrue(AnnouncementKind.allCases.contains(.parameter))
    }
}
