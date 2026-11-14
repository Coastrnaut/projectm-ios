// VideoLoopTests.swift — MED-003-T12, T17: the stored video's loop region in the app (MED-003-R7 to
// R10; S5). Each test has its own folder and UserDefaults suite; the stored "video" is an empty
// `<UUID>.mov` (nothing here decodes it). No wall-clock assertion: the settle delay is only checked
// as "not applied synchronously", then `commitLoop()` applies.
import Foundation
import SceneFormat
import VideoLayer
import XCTest
@testable import projectM_iOS

@MainActor
final class VideoLoopTests: XCTestCase {
    private struct Sandbox {
        let root: URL
        let defaults: UserDefaults
        let suite: String
        var store: VideoStore { VideoStore(directory: root, defaults: defaults) }

        /// An empty stored copy made current.
        func storedVideo() throws -> StoredVideo {
            let id = UUID()
            let url = root.appendingPathComponent("\(id.uuidString).mov")
            try Data().write(to: url)
            let video = StoredVideo(id: id, url: url)
            store.makeCurrent(video)
            return video
        }

        func cleanUp() {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: suite)
        }
    }

    private func makeSandbox() throws -> Sandbox {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("VideoLoopTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let suite = "VideoLoopTests.\(UUID().uuidString)"
        return Sandbox(root: root, defaults: try XCTUnwrap(UserDefaults(suiteName: suite)), suite: suite)
    }

    private func coordinator(_ sandbox: Sandbox) -> VideoCoordinator {
        let c = VideoCoordinator(store: sandbox.store, announce: { (_: String) -> Void in })
        c.loopSettle = .seconds(60)   // only commitLoop applies in these tests
        return c
    }

    private let duration: Int64 = 2_000_000_000

    // MARK: Store (R7)

    func testRegionIsKeptPerVideoAndForgottenOnRemoveOrANewVideo() throws {
        let sandbox = try makeSandbox()
        defer { sandbox.cleanUp() }
        let first = try sandbox.storedVideo()
        let region = VideoLoopRegion(inMilliseconds: 500, outMilliseconds: 1500)
        sandbox.store.setLoopRegion(region, for: first.id)
        XCTAssertEqual(sandbox.store.loopRegion(for: first.id), region, "kept for its video (a relaunch reads the same defaults)")
        XCTAssertNil(sandbox.store.loopRegion(for: UUID()), "another video never reads it")
        XCTAssertNil(sandbox.defaults.object(forKey: VideoStore.loopKey), "a foreign read removes it")

        sandbox.store.setLoopRegion(region, for: first.id)
        _ = try sandbox.storedVideo()   // a new current video
        XCTAssertNil(sandbox.defaults.object(forKey: VideoStore.loopKey), "a new video plays whole")

        let third = try sandbox.storedVideo()
        sandbox.store.setLoopRegion(region, for: third.id)
        sandbox.store.remove()
        XCTAssertNil(sandbox.defaults.object(forKey: VideoStore.loopKey), "Remove Video forgets it")

        sandbox.defaults.set(["id": third.id.uuidString, "inMilliseconds": 900, "outMilliseconds": 100], forKey: VideoStore.loopKey)
        XCTAssertNil(sandbox.store.loopRegion(for: third.id), "malformed reads as none")
        XCTAssertTrue(AppSettings.allKeys.contains(VideoStore.loopKey), "-uitestResetNotice clears it")
    }

    // MARK: Coordinator (R9, R10)

    func testSliderEditsClampSaveAtOnceAndApplyOnCommit() throws {
        let sandbox = try makeSandbox()
        defer { sandbox.cleanUp() }
        let video = try sandbox.storedVideo()
        let c = coordinator(sandbox)
        var applied: [VideoLoopRegion?] = []
        c.onLoopRegionChange = { (r: VideoLoopRegion?) -> Void in applied.append(r) }
        XCTAssertNil(c.effectiveLoop, "no controls until the duration is known")
        c.durationNanoseconds = duration
        XCTAssertEqual(c.effectiveLoop, VideoLoopRegion.whole(duration: duration))

        c.setLoop(inSeconds: 0.5)
        XCTAssertEqual(c.loopRegion, VideoLoopRegion(inMilliseconds: 500, outMilliseconds: 2000))
        XCTAssertEqual(sandbox.store.loopRegion(for: video.id), c.loopRegion, "saved at once")
        XCTAssertTrue(applied.isEmpty, "the player is told only once the edit settles")

        c.setLoop(outSeconds: 0.6)   // shorter than 0.25 s: in moves back
        XCTAssertEqual(c.loopRegion, VideoLoopRegion(inMilliseconds: 350, outMilliseconds: 600))
        c.setLoop(outSeconds: 5)     // past the end
        XCTAssertEqual(c.loopRegion, VideoLoopRegion(inMilliseconds: 350, outMilliseconds: 2000))
        c.setLoop(inSeconds: 1.9)    // too close to the end: in moves back to end − 0.25 s
        XCTAssertEqual(c.loopRegion, VideoLoopRegion(inMilliseconds: 1750, outMilliseconds: 2000))
        c.commitLoop()
        c.commitLoop()
        XCTAssertEqual(applied, [VideoLoopRegion(inMilliseconds: 1750, outMilliseconds: 2000)], "one update per settled edit")

        c.setLoop(inSeconds: 0)      // the whole file is saved as none
        XCTAssertNil(c.loopRegion)
        c.setLoop(inSeconds: 1)
        c.resetLoop()
        XCTAssertNil(c.loopRegion)
        XCTAssertNil(sandbox.store.loopRegion(for: video.id))
        XCTAssertEqual(applied.last ?? nil, nil, "Reset applies the whole file at once")

        c.setLoop(inSeconds: 1.2)
        c.commitLoop()
        let relaunched = coordinator(sandbox)
        XCTAssertEqual(relaunched.loopRegion, VideoLoopRegion(inMilliseconds: 1200, outMilliseconds: 2000), "kept after a relaunch")
        relaunched.remove()
        XCTAssertNil(relaunched.loopRegion)
    }

    func testTimesAreSpokenAsSeconds() {
        XCTAssertEqual(VideoLoopControls.spokenText(1.5), "1.5 seconds")
        XCTAssertEqual(VideoLoopControls.shortText(0.25), "0.25 s")
        XCTAssertEqual(VideoLoopControls.seconds(1_750_000_000), 1.75)
    }

    // MARK: Scenes and cues (R8, S5)

    func testScenesAndCuesCarryTheRegionForTheStoredVideo() throws {
        let sandbox = try makeSandbox()
        defer { sandbox.cleanUp() }
        let video = try sandbox.storedVideo()
        let loop = SceneVideoLoop(inMilliseconds: 500, outMilliseconds: 1500)
        let registry = try SceneArchiveService.appRegistry()

        // Autosave capture → save → load → restore.
        var inputs = SceneAutosaveFixtures.inputs(visual: .video)
        inputs.videoID = video.id
        inputs.videoLoop = loop
        let captured = SceneAutosaveCapture.document(inputs, carry: SceneAutosaveFixtures.carry, liveBindings: nil).document
        XCTAssertEqual(captured.assets[SceneAutosaveCapture.videoKey]?.videoLoop, loop)
        let folder = SceneAutosaveFixtures.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try SceneAutosaveStore(directory: folder).save(captured.encoded())
        let load = SceneAutosaveStore(directory: folder).load(registry: registry, assets: nil)
        let document = try XCTUnwrap(load.document)
        let values = SceneAutosaveCapture.restoredValues(document, live: try XCTUnwrap(load.result).state, registry: registry)
        XCTAssertEqual(values.videoStoreID, video.id.uuidString)
        XCTAssertEqual(values.videoLoop, loop)
        var whole = inputs
        whole.videoLoop = nil
        let plain = SceneAutosaveCapture.document(whole, carry: SceneAutosaveFixtures.carry, liveBindings: nil).document
        XCTAssertNil(plain.assets[SceneAutosaveCapture.videoKey]?.extra["loop"], "the whole file writes no field")

        // Show cue capture → apply.
        let look = ShowLook(visual: .video, bars: 64, orientation: .vertical, spacing: 0.2, glowEnabled: false, glowIntensity: 0.5,
                            glowRadius: 0.5, glowThreshold: 0.5, text: inputs.text, photoID: nil, videoID: video.id, videoLoop: loop)
        let cue = ShowSceneSnapshot.document(look, id: UUID().uuidString, name: "Cue")
        let apply = ShowSceneSnapshot.apply(of: cue, warnings: [], registry: registry)
        XCTAssertEqual(apply.videoStoreID, video.id.uuidString)
        XCTAssertEqual(apply.videoLoop, loop)

        // Applying: only for the stored video; a scene without a loop is the whole file.
        let c = coordinator(sandbox)
        c.durationNanoseconds = duration
        var applied: [VideoLoopRegion?] = []
        c.onLoopRegionChange = { (r: VideoLoopRegion?) -> Void in applied.append(r) }
        c.restoreLoop(storeID: UUID().uuidString, loop: loop)
        XCTAssertNil(c.loopRegion, "another video's region is ignored")
        c.restoreLoop(storeID: video.id.uuidString, loop: loop)
        XCTAssertEqual(c.loopRegion, VideoLoopRegion(inMilliseconds: 500, outMilliseconds: 1500))
        XCTAssertEqual(applied, [VideoLoopRegion(inMilliseconds: 500, outMilliseconds: 1500)], "applied at once")
        c.restoreLoop(storeID: nil, loop: nil)
        XCTAssertNotNil(c.loopRegion, "a scene without a video changes nothing")
        c.restoreLoop(storeID: video.id.uuidString, loop: nil)
        XCTAssertNil(c.loopRegion, "the stored video without a loop plays whole")
    }
}
