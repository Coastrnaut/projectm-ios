// VideoSpeedTests.swift — MED-004-T12, T18: the stored video's playback speed in the app (MED-004-R3,
// R6 to R8; S4, S5). Each test has its own folder and UserDefaults suite; the stored "video" is an empty
// `<UUID>.mov` (nothing here decodes it). No wall-clock assertion.
import Foundation
import LibraryBackup
import SceneFormat
import VideoLayer
import XCTest
@testable import projectM_iOS

@MainActor
final class VideoSpeedTests: XCTestCase {
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
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("VideoSpeedTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let suite = "VideoSpeedTests.\(UUID().uuidString)"
        return Sandbox(root: root, defaults: try XCTUnwrap(UserDefaults(suiteName: suite)), suite: suite)
    }

    private func speed(_ percent: Int) throws -> VideoPlaybackSpeed { try XCTUnwrap(VideoPlaybackSpeed(percent: percent)) }

    // MARK: Store (R6, S5)

    func testSpeedIsKeptPerVideoAndForgottenOnRemoveOrANewVideo() throws {
        let sandbox = try makeSandbox()
        defer { sandbox.cleanUp() }
        let first = try sandbox.storedVideo()
        XCTAssertEqual(sandbox.store.speed(for: first.id), .normal, "1× without a saved speed")
        sandbox.store.setSpeed(try speed(50), for: first.id)
        XCTAssertEqual(sandbox.store.speed(for: first.id), try speed(50), "kept for its video (a relaunch reads the same defaults)")
        XCTAssertEqual(sandbox.store.speed(for: UUID()), .normal, "another video never reads it")
        XCTAssertNil(sandbox.defaults.object(forKey: VideoStore.speedKey), "a foreign read removes it")

        sandbox.store.setSpeed(try speed(200), for: first.id)
        sandbox.store.setSpeed(.normal, for: first.id)
        XCTAssertNil(sandbox.defaults.object(forKey: VideoStore.speedKey), "1× is stored as no key")

        sandbox.store.setSpeed(try speed(150), for: first.id)
        let second = try sandbox.storedVideo()
        XCTAssertNil(sandbox.defaults.object(forKey: VideoStore.speedKey), "a new video plays at 1×")
        sandbox.store.setSpeed(try speed(25), for: second.id)
        sandbox.store.remove()
        XCTAssertNil(sandbox.defaults.object(forKey: VideoStore.speedKey), "Remove Video forgets it")

        let third = try sandbox.storedVideo()
        let bad: [[String: Any]] = [["id": third.id.uuidString, "percent": 33], ["id": third.id.uuidString, "percent": "50"],
                                    ["id": third.id.uuidString], ["percent": 50]]
        for value in bad {
            sandbox.defaults.set(value, forKey: VideoStore.speedKey)
            XCTAssertEqual(sandbox.store.speed(for: third.id), .normal, "\(value) reads as 1×")
            XCTAssertNil(sandbox.defaults.object(forKey: VideoStore.speedKey), "and is removed")
        }
    }

    func testTheKeyIsListedForResetBackupAndErase() {
        XCTAssertEqual(AppSettings.videoSpeedKey, VideoStore.speedKey)
        XCTAssertTrue(AppSettings.allKeys.contains(VideoStore.speedKey), "the UI tests' reset clears it")
        XCTAssertEqual(LibraryErasePolicy.videoSpeedKey, VideoStore.speedKey)
        XCTAssertTrue(LibraryErasePolicy.settingKeys(.media).contains(VideoStore.speedKey), "erased with Photos and videos")
        XCTAssertTrue(LibrarySettingsPolicy.excludedKeys.contains(VideoStore.speedKey), "never in a backup")
    }

    // MARK: Coordinator (R4, R8)

    func testAPickIsSavedAndAppliedAtOnce() throws {
        let sandbox = try makeSandbox()
        defer { sandbox.cleanUp() }
        let empty = VideoCoordinator(store: sandbox.store, announce: { (_: String) -> Void in })
        empty.setSpeed(try speed(50))
        XCTAssertEqual(empty.speed, .normal, "no speed without a video")

        let video = try sandbox.storedVideo()
        let c = VideoCoordinator(store: sandbox.store, announce: { (_: String) -> Void in })
        var applied: [VideoPlaybackSpeed] = []
        c.onSpeedChange = { (s: VideoPlaybackSpeed) -> Void in applied.append(s) }
        c.setSpeed(try speed(50))
        XCTAssertEqual(applied, [try speed(50)], "applied synchronously, no settle delay")
        XCTAssertEqual(sandbox.store.speed(for: video.id), try speed(50), "saved at once")
        XCTAssertEqual(c.sceneSpeedPercent, 50)
        c.setSpeed(try speed(50))
        XCTAssertEqual(applied.count, 1, "the same speed again changes nothing")
        let relaunched = VideoCoordinator(store: sandbox.store, announce: { (_: String) -> Void in })
        XCTAssertEqual(relaunched.speed, try speed(50), "kept after a relaunch")
        relaunched.setSpeed(.normal)
        XCTAssertNil(relaunched.sceneSpeedPercent, "1× writes no scene field")
        relaunched.remove()
        XCTAssertEqual(relaunched.speed, .normal, "Remove Video returns to 1×")
    }

    func testSpeedsAreShownAndSpokenInWords() {
        let shown: [String] = VideoPlaybackSpeed.all.map { (s: VideoPlaybackSpeed) -> String in VideoSpeedControls.shortText(s) }
        XCTAssertEqual(shown, ["0.25×", "0.5×", "0.75×", "1×", "1.25×", "1.5×", "2×"])
        let spoken: [String] = VideoPlaybackSpeed.all.map { (s: VideoPlaybackSpeed) -> String in VideoSpeedControls.spokenText(s) }
        XCTAssertEqual(spoken, ["Quarter speed", "Half speed", "Three-quarter speed", "Normal speed", "1.25 times", "1.5 times", "Double speed"])
    }

    // MARK: Independence from the audio source (R3, S4)

    /// The speed path never reaches audio: the video layer's module imports no audio or capture module
    /// and plays no sound, and the app hands the speed only to the Video visual's host.
    func testSpeedNeverReachesTheAudioSource() throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let videoLayer = repo.appendingPathComponent("Packages/Compositor/Sources/VideoLayer", isDirectory: true)
        let files = try FileManager.default.contentsOfDirectory(at: videoLayer, includingPropertiesForKeys: nil)
            .filter { (u: URL) -> Bool in u.pathExtension == "swift" }
        XCTAssertGreaterThan(files.count, 5)
        let forbiddenImports: [String] = ["AudioCore", "CaptureKit", "AVFAudio", "AudioToolbox", "CoreAudio", "MediaPlayer"]
        let forbiddenAPIs: [String] = ["AVAudio", "AVPlayer", "AVAudioSession", "audioMix"]
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for name in forbiddenImports { XCTAssertFalse(text.contains("import " + name), "\(file.lastPathComponent) imports \(name)") }
            for api in forbiddenAPIs { XCTAssertFalse(text.contains(api), "\(file.lastPathComponent) uses \(api)") }
        }
        // Every place the app sets a playback speed is the Video visual's host.
        let coordinators = repo.appendingPathComponent("Apps/projectM-iOS/Coordinators", isDirectory: true)
        var setters: [String] = []
        for file in try FileManager.default.contentsOfDirectory(at: coordinators, includingPropertiesForKeys: nil) {
            let text = try String(contentsOf: file, encoding: .utf8)
            for line in text.split(separator: "\n") where line.contains("playbackSpeed =") { setters.append(String(line)) }
        }
        XCTAssertEqual(setters.count, 3, "host creation, a new video, a change: \(setters)")
        for line in setters {
            XCTAssertTrue(line.contains("host.playbackSpeed =") || line.contains("videoVisual?.playbackSpeed ="), line)
        }
    }

    // MARK: Scenes, undo states and cues (R7, S5)

    func testScenesAndCuesCarryTheSpeedForTheStoredVideo() throws {
        let sandbox = try makeSandbox()
        defer { sandbox.cleanUp() }
        let video = try sandbox.storedVideo()
        let registry = try SceneArchiveService.appRegistry()

        var inputs = SceneAutosaveFixtures.inputs(visual: .video)
        inputs.videoID = video.id
        inputs.videoSpeedPercent = 200
        let captured = SceneAutosaveCapture.document(inputs, carry: SceneAutosaveFixtures.carry, liveBindings: nil).document
        XCTAssertEqual(captured.assets[SceneAutosaveCapture.videoKey]?.videoSpeedPercent, 200)
        let folder = SceneAutosaveFixtures.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try SceneAutosaveStore(directory: folder).save(captured.encoded())
        let load = SceneAutosaveStore(directory: folder).load(registry: registry, assets: nil)
        let document = try XCTUnwrap(load.document)
        let values = SceneAutosaveCapture.restoredValues(document, live: try XCTUnwrap(load.result).state, registry: registry)
        XCTAssertEqual(values.videoStoreID, video.id.uuidString)
        XCTAssertEqual(values.videoSpeedPercent, 200)
        var normal = inputs
        normal.videoSpeedPercent = nil
        let plain = SceneAutosaveCapture.document(normal, carry: SceneAutosaveFixtures.carry, liveBindings: nil).document
        XCTAssertNil(plain.assets[SceneAutosaveCapture.videoKey]?.extra[SceneAsset.videoSpeedKey], "1× writes no field")

        let look = ShowLook(visual: .video, bars: 64, orientation: .vertical, spacing: 0.2, glowEnabled: false, glowIntensity: 0.5,
                            glowRadius: 0.5, glowThreshold: 0.5, text: inputs.text, photoID: nil, videoID: video.id,
                            videoLoop: nil, videoSpeedPercent: 25)
        let cue = ShowSceneSnapshot.document(look, id: UUID().uuidString, name: "Cue")
        let apply = ShowSceneSnapshot.apply(of: cue, warnings: [], registry: registry)
        XCTAssertEqual(apply.videoStoreID, video.id.uuidString)
        XCTAssertEqual(apply.videoSpeedPercent, 25)

        let c = VideoCoordinator(store: sandbox.store, announce: { (_: String) -> Void in })
        var applied: [VideoPlaybackSpeed] = []
        c.onSpeedChange = { (s: VideoPlaybackSpeed) -> Void in applied.append(s) }
        c.restoreSpeed(storeID: UUID().uuidString, speedPercent: 200)
        XCTAssertEqual(c.speed, .normal, "another video's speed is ignored")
        c.restoreSpeed(storeID: video.id.uuidString, speedPercent: 200)
        XCTAssertEqual(c.speed, try speed(200))
        XCTAssertEqual(applied, [try speed(200)], "applied at once")
        c.restoreSpeed(storeID: nil, speedPercent: nil)
        XCTAssertEqual(c.speed, try speed(200), "a scene without a video changes nothing")
        c.restoreSpeed(storeID: video.id.uuidString, speedPercent: 33)
        XCTAssertEqual(c.speed, .normal, "a value outside the safe set plays at 1×")
        c.restoreSpeed(storeID: video.id.uuidString, speedPercent: 75)
        c.restoreSpeed(storeID: video.id.uuidString, speedPercent: nil)
        XCTAssertEqual(c.speed, .normal, "the stored video without a speed plays at 1×")
    }
}
