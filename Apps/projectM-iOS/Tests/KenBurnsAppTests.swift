// KenBurnsAppTests.swift — MED-007-T12, T13 (app): the Ken Burns setting's store and edits, the scene, cue and undo
// round trips, the slideshow dwell, and the setting reaching a real Photo visual's layer (movement, Reduce Motion,
// dwell). Each test has its own defaults suite; no wall clock.
import Compositor
import Foundation
import ImageLayer
import LibraryBackup
import Metal
import SceneFormat
import XCTest
@testable import projectM_iOS

@MainActor
final class KenBurnsAppTests: XCTestCase {
    private var suite = ""
    private var defaults: UserDefaults!

    override func setUp() async throws {
        suite = "KenBurnsAppTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }

    final class SpokenBox { var texts: [String] = [] }

    private func coordinator(_ spoken: SpokenBox = SpokenBox()) -> KenBurnsCoordinator {
        KenBurnsCoordinator(store: KenBurnsStore(defaults: defaults), announce: { (t: String) -> Void in spoken.texts.append(t) })
    }

    /// MED-007-R9, R11: off by default; on saves Zoom in; edits clamp and persist; off keeps the draft.
    func testEditsClampSaveAndSurviveARelaunch() {
        let spoken = SpokenBox()
        let c = coordinator(spoken)
        var changes = 0
        c.onChange = { () -> Void in changes += 1 }
        XCTAssertFalse(c.isEnabled)
        XCTAssertEqual(c.summary, "Off")
        XCTAssertNil(defaults.object(forKey: KenBurnsStore.key), "nothing stored while off")
        c.setEnabled(true)
        XCTAssertEqual(c.motion, KenBurnsPreset.zoomIn.motion())
        XCTAssertEqual(c.summary, "Zoom in, 10 s")
        XCTAssertEqual(spoken.texts, ["Ken Burns on."])
        c.setPreset(.panRightToLeft)
        c.setDurationSeconds(500)
        c.setEasing(.linear)
        XCTAssertEqual(c.motion?.durationMilliseconds, 60_000, "clamped to 60 s")
        XCTAssertEqual(c.summary, "Pan right to left, 60 s")
        c.setPreset(.custom)
        XCTAssertEqual(c.preset, .custom, "Custom shows the current rectangles for editing")
        c.setZoom(9, of: .end)
        c.setPosition(x: 2, y: -1, of: .end)
        let end = try? XCTUnwrap(c.motion?.end)
        XCTAssertEqual(end, KenBurnsRect(validatingX: 0.75, y: 0, width: 0.25, height: 0.25), "zoom 4× at most, position clamped")
        XCTAssertEqual(changes, 6, "one change per committed edit (choosing Custom changes nothing)")

        let relaunched = coordinator()
        XCTAssertEqual(relaunched.motion, c.motion, "survives a relaunch")
        relaunched.setEnabled(false)
        XCTAssertNil(defaults.object(forKey: KenBurnsStore.key), "off removes the key")
        XCTAssertEqual(relaunched.draft, c.motion, "the movement is kept for turning it on again")
        relaunched.setEnabled(true)
        XCTAssertEqual(relaunched.motion, c.motion)

        defaults.set(Data("{\"start\":1}".utf8), forKey: KenBurnsStore.key)
        XCTAssertNil(coordinator().motion, "unreadable data reads as off")
    }

    /// MED-007-R10: autosave, cue and undo states carry the movement; an absent field turns it off; other visuals'
    /// documents leave it.
    func testSceneCueAndUndoRoundTrips() throws {
        let motion = KenBurnsMotion(start: KenBurnsPreset.panLeft, end: KenBurnsPreset.zoomedCentre, durationMilliseconds: 7_000,
                                    easing: .linear)
        let c = coordinator()
        let registry = try SceneArchiveService.appRegistry()

        var inputs = SceneAutosaveFixtures.inputs(visual: .photo)
        inputs.photoID = UUID()
        inputs.kenBurns = motion
        let captured = SceneAutosaveCapture.document(inputs, carry: SceneAutosaveFixtures.carry, liveBindings: nil).document
        XCTAssertEqual(captured.assets[SceneAutosaveCapture.photoKey]?.photoKenBurns, motion)
        let decoded = try SceneDocument.decode(captured.encoded()).document
        let values = SceneAutosaveCapture.restoredValues(decoded, live: SceneLiveState(stack: LayerStack()), registry: registry)
        let restore = try XCTUnwrap(values.slideshow, "a photo layer's fields are restored")
        XCTAssertEqual(restore.kenBurns, motion)
        c.restore(restore.kenBurns)
        XCTAssertEqual(c.motion, motion)
        XCTAssertEqual(c.preset, .custom)

        // A show cue carries it too.
        let look = ShowLook(visual: .photo, bars: 64, orientation: .vertical, spacing: 0.2, glowEnabled: false, glowIntensity: 0.5,
                            glowRadius: 0.5, glowThreshold: 0.5, text: inputs.text, photoID: UUID(), videoID: nil,
                            kenBurns: KenBurnsPreset.zoomOut.motion())
        let cue = ShowSceneSnapshot.document(look, id: UUID().uuidString, name: "Cue")
        let apply = ShowSceneSnapshot.apply(of: cue, warnings: [], registry: registry)
        c.restore(try XCTUnwrap(apply.slideshow).kenBurns)
        XCTAssertEqual(c.preset, .zoomOut)

        // A photo scene without the field turns it off; scenes of other visuals have no photo layer.
        inputs.kenBurns = nil
        let plainPhoto = SceneAutosaveCapture.document(inputs, carry: SceneAutosaveFixtures.carry, liveBindings: nil).document
        XCTAssertNil(plainPhoto.assets[SceneAutosaveCapture.photoKey]?.extra[SceneKenBurns.key], "off writes no field")
        c.restore(try XCTUnwrap(SceneSlideshowBridge.restore(in: plainPhoto)).kenBurns)
        XCTAssertFalse(c.isEnabled)
        let spectrum = SceneAutosaveCapture.document(SceneAutosaveFixtures.inputs(visual: .circularSpectrum),
                                                     carry: SceneAutosaveFixtures.carry, liveBindings: nil).document
        XCTAssertNil(SceneSlideshowBridge.restore(in: spectrum))
    }

    /// MED-007-R8: Time mode lasts the seconds; Beats mode beats × period with a grid, else the seconds.
    func testSlideDwell() throws {
        let time = SlideshowSettings(enabled: true, slides: [UUID(), UUID()], mode: .time, seconds: 8, beats: 4)
        XCTAssertEqual(KenBurnsCoordinator.slideDwellNanoseconds(time, grid: nil), 8_000_000_000)
        let beats = time.with(mode: .beats)
        let grid = try XCTUnwrap(SlideshowBeatGrid(periodNanoseconds: 500_000_000, anchorNanoseconds: 0))
        XCTAssertEqual(KenBurnsCoordinator.slideDwellNanoseconds(beats, grid: grid), 2_000_000_000, "4 beats at 120 BPM")
        XCTAssertEqual(KenBurnsCoordinator.slideDwellNanoseconds(beats, grid: nil), 8_000_000_000, "no reliable tempo: the seconds")
        XCTAssertEqual(KenBurnsCoordinator.slideDwellNanoseconds(time, grid: grid), 8_000_000_000, "Time mode ignores the grid")
    }

    /// MED-007-T13: the movement, Reduce Motion and the dwell reach a real Photo visual's layer; equal values never restart.
    func testTheSettingReachesThePhotoLayer() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device in this simulator") }
        let host = try PhotoVisualHost.make(device: device, reader: nil, barCount: .b32)
        let motion = try XCTUnwrap(KenBurnsPreset.zoomIn.motion())
        KenBurnsCoordinator.apply(motion, reduceMotion: false, duration: 3_000_000_000, to: host.photo)
        XCTAssertEqual(host.photo.kenBurns, motion)
        XCTAssertEqual(host.photo.kenBurnsDurationNanoseconds, 3_000_000_000)
        XCTAssertFalse(host.photo.reduceMotion)
        let before = host.photo.renderDependencies
        KenBurnsCoordinator.apply(motion, reduceMotion: false, duration: 3_000_000_000, to: host.photo)
        XCTAssertEqual(host.photo.renderDependencies.parameterGeneration, before.parameterGeneration, "equal values change nothing")
        KenBurnsCoordinator.apply(motion, reduceMotion: true, duration: nil, to: host.photo)
        XCTAssertTrue(host.photo.reduceMotion)
        XCTAssertFalse(host.photo.isKenBurnsMoving, "Reduce Motion holds the start")
        XCTAssertNil(host.photo.kenBurnsDurationNanoseconds)
        KenBurnsCoordinator.apply(nil, reduceMotion: true, duration: nil, to: host.photo)
        XCTAssertNil(host.photo.kenBurns)
    }

    /// MED-007-R9: the key is one the app stores, reset by the UI tests, backed up, erased with Settings.
    func testTheKeyIsInEveryList() {
        XCTAssertTrue(AppSettings.allKeys.contains(KenBurnsStore.key), "the UI tests' reset clears it")
        XCTAssertTrue(LibrarySettingsPolicyProbe.included(KenBurnsStore.key), "backed up with the settings")
    }
}


private enum LibrarySettingsPolicyProbe {
    static func included(_ key: String) -> Bool {
        LibrarySettingsPolicy.isIncluded(key) && LibraryErasePolicy.settingKeys(.settings).contains(key)
            && !LibraryErasePolicy.settingKeys(.media).contains(key)
    }
}
