// ShowKeyframeAcceptanceTests.swift — SHOW-008-T08, T09: the roadmap acceptance "At keyframe timestamps values match
// stored samples exactly" through the app's live path (SHOW-008-S3; contract specs/246-show-008-keyframe-tracks/
// contracts/show-keyframe-tracks.md K5, K6): a `ShowCoordinator` over a temporary store, SHOW-002's driver on a
// `ShowManualClock`, SHOW-007's transport, and the keyframe coordinator with a recorder of every applied output.
// `tick()` and `sample()` are called by the test; no task runs and nothing waits on the wall clock.
import Foundation
import ParameterGraph
import SceneFormat
import ShowControl
import ShowStorage
import TextLayer
import VisualGenerators
import VisualParameters
import XCTest
@testable import projectM_iOS

@MainActor
final class ShowKeyframeAcceptanceTests: XCTestCase {
    private let glow: ParameterID = VisualParameterIDs.bloomIntensity

    private var show: ShowCoordinator!
    private var driver: ShowAutoAdvanceCoordinator!
    private var transport: ShowTransportCoordinator!
    private var keyframes: ShowKeyframeCoordinator!
    private var clock: ShowManualClock!
    private var settings: AppSettings!
    private var applied: [ShowTrackOutput] = []

    /// Three cues with 30 s dwells (a 1:30 timeline).
    override func setUp() async throws {
        let suite = "SHOW008-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        settings = AppSettings(defaults: defaults, systemReduceMotion: false)
        show = ShowCoordinator(store: ShowStore(directory: url), registry: try SceneArchiveService.appRegistry())
        show.applyScene = { (_: SceneDocument, _: [SceneIssue]) -> [String] in [] }
        show.sceneLock = settings.sceneLock
        for n in 1...3 {
            let look = ShowLook(visual: .circularSpectrum, bars: 64, orientation: .horizontal, spacing: 0.5, glowEnabled: true,
                                glowIntensity: 0.7, glowRadius: 0.03, glowThreshold: 0.4, text: TextOverlaySpec(message: ""),
                                photoID: nil, videoID: nil)
            XCTAssertTrue(show.addScene(ShowSceneSnapshot.document(look, id: UUID().uuidString, name: "Cue \(n)"), label: "Cue \(n)"))
        }
        for cue in show.list.cues { XCTAssertTrue(show.setDwell(cue.id, to: try ShowCueDwell(seconds: 30))) }
        clock = ShowManualClock()
        driver = ShowAutoAdvanceCoordinator(show: show, clock: clock, runsLoop: false)
        transport = ShowTransportCoordinator(show: show, driver: driver, defaults: defaults)
        keyframes = ShowKeyframeCoordinator(show: show, transport: transport, runsLoop: false)
        applied = []
        keyframes.apply = { [unowned self] (output: ShowTrackOutput) -> Void in self.applied.append(output) }
    }

    /// Glow intensity: 0.2 at 0:00 (Linear) → 0.9 at 0:30 (Hold) → 0.4 at 1:00 (Ease) → 0.7 at 1:15.
    private let stored: [ShowKeyframe] = [
        ShowKeyframe(time: 0, value: .number(0.2), interpolation: .linear),
        ShowKeyframe(time: 30_000, value: .number(0.9), interpolation: .hold),
        ShowKeyframe(time: 60_000, value: .number(0.4), interpolation: .ease),
        ShowKeyframe(time: 75_000, value: .number(0.7000000000000001), interpolation: .linear),
    ]

    private func storeGlowTrack() throws {
        let track = try ShowKeyframeTrack(id: UUID(), parameter: glow, keyframes: stored)
        XCTAssertTrue(show.setKeyframeTracks(try ShowKeyframeTracks(tracks: [track])))
    }

    private func glowNow() -> Double? { keyframes.output.numbers[glow] }

    // K5, S3: a seek to each keyframe time applies exactly the stored value, once; a repeated seek applies nothing.
    func testSeekToEachKeyframeTimeAppliesTheStoredValueExactlyOnce() throws {
        try storeGlowTrack()
        show.next()
        for keyframe in stored.reversed() {   // backwards, so every seek moves
            let before: Int = applied.count
            transport.seek(to: .milliseconds(keyframe.time))
            XCTAssertEqual(applied.count, before + 1, "one apply for the seek to \(keyframe.time) ms")
            XCTAssertEqual(applied.last?.numbers[glow]?.bitPattern, keyframe.value.number?.bitPattern, "exact at \(keyframe.time) ms")
            transport.seek(to: .milliseconds(keyframe.time))
            keyframes.sample()
            XCTAssertEqual(applied.count, before + 1, "a repeated seek applies nothing")
        }
    }

    // R4, S3: playing across the keys with the injected clock is deterministic and exact at every key.
    func testPlayingAcrossKeysIsDeterministicAndExactAtKeys() throws {
        try storeGlowTrack()
        func play() -> [Double] {
            var values: [Double] = []
            transport.seek(to: .zero)   // cue 1 with 30 s left (from Standby or from cue 3)
            for _ in 0..<(80 * 4) {   // 250 ms frames to 1:20
                clock.advance(by: .milliseconds(250))
                driver.tick()
                keyframes.sample()
                values.append(glowNow() ?? .nan)
            }
            return values
        }
        let first: [Double] = play()
        let second: [Double] = play()
        XCTAssertEqual(first.map(\.bitPattern), second.map(\.bitPattern), "same clock, same values")
        for keyframe in stored where keyframe.time > 0 {
            let frame: Int = keyframe.time / 250 - 1
            XCTAssertEqual(first[frame].bitPattern, keyframe.value.number?.bitPattern, "exact at \(keyframe.time) ms while playing")
        }
        XCTAssertEqual(first[59], 0.2 + (0.9 - 0.2) * 0.5, accuracy: 1e-12)   // 0:15 linear midpoint
        XCTAssertEqual(first[199], 0.9)   // 0:50 held
        XCTAssertEqual(show.list.activeIndex, 2, "the cues advanced with the clock")
    }

    // R6: at Standby the output is empty (manual values); MIDI/OSC live values win over track numbers (R5).
    func testStandbyReleasesTheParametersAndLiveValuesWin() throws {
        try storeGlowTrack()
        keyframes.sample()
        XCTAssertTrue(keyframes.output.isEmpty, "Standby: no track values")
        show.next()
        transport.seek(to: .seconds(30))
        XCTAssertEqual(glowNow(), 0.9)
        XCTAssertEqual(keyframes.output.numbers(overlaidBy: [glow: 0.33])[glow], 0.33, "MIDI/OSC wins")
        XCTAssertEqual(keyframes.output.numbers(overlaidBy: [VisualParameterIDs.bloomRadius: 0.02]).count, 2)
    }

    // K6, R8: Add Keyframe at Playhead (current value, replaces at the same time), clamping, and the lock.
    func testEditsAddAtPlayheadClampAndAreRefusedWhileLocked() throws {
        keyframes.currentValue = { (_: ShowKeyframeTarget) -> ShowKeyframeValue in .number(0.55) }
        let target = try XCTUnwrap(keyframes.target(for: glow))
        let id = try XCTUnwrap(keyframes.addTrack(target))
        XCTAssertNil(keyframes.addTrack(target), "one track per parameter")
        XCTAssertEqual(keyframes.addKeyframeAtPlayhead(track: id), 0, "Standby: 0:00")
        show.next()
        transport.seek(to: .milliseconds(12_345))
        XCTAssertEqual(keyframes.addKeyframeAtPlayhead(track: id), 12_345)
        XCTAssertEqual(show.list.tracks.track(id)?.keyframes.map(\.value), [.number(0.55), .number(0.55)])
        XCTAssertTrue(keyframes.setValue(.number(7), track: id, time: 12_345))
        XCTAssertEqual(show.list.tracks.track(id)?.keyframes.last?.value, .number(1), "clamped to the registry range")
        XCTAssertEqual(glowNow(), 1, "an edit resamples at once")
        XCTAssertEqual(keyframes.addKeyframeAtPlayhead(track: id), 12_345)
        XCTAssertEqual(show.list.tracks.track(id)?.keyframes.count, 2, "the same time is replaced, not duplicated")

        settings.sceneLock.lock()
        XCTAssertNil(keyframes.addKeyframeAtPlayhead(track: id))
        XCTAssertFalse(keyframes.setInterpolation(.hold, track: id, time: 0))
        XCTAssertFalse(keyframes.removeTrack(id))
        XCTAssertEqual(show.list.tracks.track(id)?.keyframes.count, 2)
        settings.sceneLock.unlock()
        XCTAssertTrue(keyframes.removeKeyframe(track: id, time: 0))
    }

    // US2, R7: a Visual Colour track is exact at its keys, and the colour-blind-safe palette wins.
    func testColourTrackIsExactAtKeysAndColourBlindSafeWins() throws {
        let blue = try XCTUnwrap(ShowKeyframeColor(red: 0.05, green: 0.1, blue: 0.6))
        let magenta = try XCTUnwrap(ShowKeyframeColor(red: 0.9, green: 0.1, blue: 0.7, alpha: 0.5))
        let track = try ShowKeyframeTrack(id: UUID(), parameter: ShowKeyframeTarget.visualColorID, keyframes: [
            ShowKeyframe(time: 0, value: .color(blue)), ShowKeyframe(time: 30_000, value: .color(magenta)),
        ])
        XCTAssertTrue(show.setKeyframeTracks(try ShowKeyframeTracks(tracks: [track])))
        show.next()
        transport.seek(to: .seconds(30))
        XCTAssertEqual(keyframes.output.color?.components.map(\.bitPattern), magenta.components.map(\.bitPattern))
        transport.seek(to: .seconds(15))
        let mid = try XCTUnwrap(keyframes.output.color)
        let expected: Double = ShowKeyframeColor.encode((ShowKeyframeColor.decode(0.05) + ShowKeyframeColor.decode(0.9)) / 2)
        XCTAssertEqual(mid.red, expected, accuracy: 1e-12)
        XCTAssertNotNil(AppCoordinator.trackPalette(mid, colorBlindSafe: false))
        XCTAssertNil(AppCoordinator.trackPalette(mid, colorBlindSafe: true), "ACC-003 wins")
        XCTAssertNil(AppCoordinator.trackPalette(nil, colorBlindSafe: false))
    }

    // Targets: the four live glow parameters from the registry, then Visual Colour.
    func testTargetsAreTheLiveGlowParametersAndVisualColour() {
        let ids: [ParameterID] = keyframes.targets.map(\.id)
        XCTAssertEqual(Set(ids), ShowKeyframeTarget.liveIDs.union([ShowKeyframeTarget.visualColorID]))
        XCTAssertEqual(ids.last, ShowKeyframeTarget.visualColorID)
        XCTAssertEqual(ShowKeyframeCoordinator.rowText(ShowKeyframe(time: 30_000, value: .number(0.9))), "0:30, 0.90, Linear")
        XCTAssertEqual(ShowKeyframeCoordinator.timeText(75_250), "1:15.250")
    }
}
