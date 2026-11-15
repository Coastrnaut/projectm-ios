// ShowKeyframeEasingAcceptanceTests.swift — SHOW-009-T07, T08 (specs/283-show-009-keyframe-easing; contract E7, E8): a
// playing show applies the eased values through SHOW-008's live path. A `ShowCoordinator` over a temporary store,
// SHOW-002's driver on a `ShowManualClock`, SHOW-007's transport and the keyframe coordinator with a recorder; `tick()`
// and `sample()` are called by the test, so nothing waits on the wall clock.
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
final class ShowKeyframeEasingAcceptanceTests: XCTestCase {
    private let glow: ParameterID = VisualParameterIDs.bloomIntensity

    private var show: ShowCoordinator!
    private var driver: ShowAutoAdvanceCoordinator!
    private var transport: ShowTransportCoordinator!
    private var keyframes: ShowKeyframeCoordinator!
    private var clock: ShowManualClock!

    /// Three cues with 30 s dwells (a 1:30 timeline).
    override func setUp() async throws {
        let suite = "SHOW009-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let settings = AppSettings(defaults: defaults, systemReduceMotion: false)
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
    }

    /// 0.2 at 0:00 (Cubic) → 0.9 at 0:30 (Linear) → 0.4 at 1:00 (Hold: a cut) → 0.7 at 1:15.
    private let stored: [ShowKeyframe] = [
        ShowKeyframe(time: 0, value: .number(0.2), interpolation: .cubic),
        ShowKeyframe(time: 30_000, value: .number(0.9), interpolation: .linear),
        ShowKeyframe(time: 60_000, value: .number(0.4), interpolation: .hold),
        ShowKeyframe(time: 75_000, value: .number(0.7000000000000001), interpolation: .linear),
    ]

    // E7, R7: playing with the manual clock applies the eased values: Cubic midpoint and quarter, the Hold cut, exact keys.
    func testAPlayingShowAppliesEasedValues() throws {
        let track = try ShowKeyframeTrack(id: UUID(), parameter: glow, keyframes: stored)
        XCTAssertTrue(show.setKeyframeTracks(try ShowKeyframeTracks(tracks: [track])))
        transport.seek(to: .zero)
        var values: [Double] = []
        for _ in 0..<(80 * 4) {   // 250 ms frames to 1:20
            clock.advance(by: .milliseconds(250))
            driver.tick()
            keyframes.sample()
            values.append(keyframes.output.numbers[glow] ?? .nan)
        }
        func at(_ ms: Int) -> Double { values[ms / 250 - 1] }
        XCTAssertEqual(at(15_000), 0.2 + 0.7 * 0.5, accuracy: 1e-12, "Cubic midpoint (two-key shape: a single Cubic segment)")
        XCTAssertEqual(at(7_500), 0.2 + 0.7 * 0.15625, accuracy: 1e-9, "Cubic quarter point 3u² − 2u³")
        XCTAssertEqual(at(45_000), 0.9, "a Hold key holds the segment arriving at it")
        XCTAssertEqual(at(59_750), 0.9)
        for keyframe in stored where keyframe.time > 0 {
            XCTAssertEqual(at(keyframe.time).bitPattern, keyframe.value.number?.bitPattern, "exact at \(keyframe.time) ms while playing")
        }
        for (i, value) in values.enumerated() {
            let expected: Double? = track.value(at: .milliseconds((i + 1) * 250))?.number
            XCTAssertEqual(value.bitPattern, expected?.bitPattern, "frame \(i) is the pure evaluation")
        }
    }

    // E8, clarify: Add Keyframe at Playhead keeps the mode of a keyframe it replaces; a new one is Linear.
    func testAddAtPlayheadKeepsTheReplacedKeyframesMode() throws {
        keyframes.currentValue = { (_: ShowKeyframeTarget) -> ShowKeyframeValue in .number(0.55) }
        let target = try XCTUnwrap(keyframes.target(for: glow))
        let id = try XCTUnwrap(keyframes.addTrack(target))
        XCTAssertEqual(keyframes.addKeyframeAtPlayhead(track: id), 0)
        XCTAssertEqual(show.list.tracks.track(id)?.keyframes.first?.interpolation, .linear)
        XCTAssertTrue(keyframes.setInterpolation(.cubic, track: id, time: 0))
        XCTAssertEqual(keyframes.addKeyframeAtPlayhead(track: id), 0)
        XCTAssertEqual(show.list.tracks.track(id)?.keyframes.map(\.interpolation), [.cubic])
        XCTAssertEqual(ShowKeyframeCoordinator.rowText(try XCTUnwrap(show.list.tracks.track(id)?.keyframes.first)), "0:00, 0.55, Cubic")
    }
}
