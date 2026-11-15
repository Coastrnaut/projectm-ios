// VideoReverseAppTests.swift — MED-005-T13, T16: reverse playback of the stored video in the app (MED-005-R1, R5, R7;
// S2, S4). Each test has its own folder and UserDefaults suite; the stored "video" is an empty `<UUID>.mov` (nothing
// here decodes it; the layer's behaviour is tested in the Compositor package). No wall-clock assertion.
import Foundation
import LibraryBackup
import VideoLayer
import XCTest
@testable import projectM_iOS

@MainActor
final class VideoReverseAppTests: XCTestCase {
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
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("VideoReverseAppTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let suite = "VideoReverseAppTests.\(UUID().uuidString)"
        return Sandbox(root: root, defaults: try XCTUnwrap(UserDefaults(suiteName: suite)), suite: suite)
    }

    // MARK: Store (R7, S4)

    func testReverseIsKeptPerVideoAndForgottenOnRemoveOrANewVideo() throws {
        let sandbox = try makeSandbox()
        defer { sandbox.cleanUp() }
        let first = try sandbox.storedVideo()
        XCTAssertFalse(sandbox.store.isReversed(first.id), "forward by default")
        sandbox.store.setReversed(true, for: first.id)
        XCTAssertTrue(sandbox.store.isReversed(first.id), "kept for its video (a relaunch reads the same defaults)")
        XCTAssertFalse(sandbox.store.isReversed(UUID()), "another video never reads it")
        XCTAssertNil(sandbox.defaults.object(forKey: VideoStore.reverseKey), "a foreign read removes it")
        sandbox.store.setReversed(true, for: first.id)
        sandbox.store.setReversed(false, for: first.id)
        XCTAssertNil(sandbox.defaults.object(forKey: VideoStore.reverseKey), "forward is stored as no key")

        sandbox.store.setReversed(true, for: first.id)
        let second = try sandbox.storedVideo()
        XCTAssertNil(sandbox.defaults.object(forKey: VideoStore.reverseKey), "a new video plays forward")
        sandbox.store.setReversed(true, for: second.id)
        sandbox.store.remove()
        XCTAssertNil(sandbox.defaults.object(forKey: VideoStore.reverseKey), "Remove Video forgets it")

        let third = try sandbox.storedVideo()
        let bad: [Any] = [true, "on", ["id": 7], ["on": third.id.uuidString]]
        for value in bad {
            sandbox.defaults.set(value, forKey: VideoStore.reverseKey)
            XCTAssertFalse(sandbox.store.isReversed(third.id), "\(value) reads as forward")
            XCTAssertNil(sandbox.defaults.object(forKey: VideoStore.reverseKey), "and is removed")
        }
    }

    func testTheKeyIsListedForResetBackupAndErase() {
        XCTAssertEqual(AppSettings.videoReverseKey, VideoStore.reverseKey)
        XCTAssertEqual(VideoStore.reverseKey, "settings.video.reverse")
        XCTAssertTrue(AppSettings.allKeys.contains(VideoStore.reverseKey), "the UI tests' reset clears it")
        XCTAssertEqual(LibraryErasePolicy.videoReverseKey, VideoStore.reverseKey)
        XCTAssertTrue(LibraryErasePolicy.settingKeys(.media).contains(VideoStore.reverseKey), "erased with Photos and videos")
        XCTAssertTrue(LibrarySettingsPolicy.excludedKeys.contains(VideoStore.reverseKey), "never in a backup")
    }

    // MARK: Coordinator (R1, R7)

    func testTheSwitchIsSavedAndAppliedAtOnce() throws {
        let sandbox = try makeSandbox()
        defer { sandbox.cleanUp() }
        let empty = VideoCoordinator(store: sandbox.store, announce: { (_: String) -> Void in })
        empty.setReverse(true)
        XCTAssertFalse(empty.reverse, "no reverse without a video")

        let video = try sandbox.storedVideo()
        let c = VideoCoordinator(store: sandbox.store, announce: { (_: String) -> Void in })
        var applied: [Bool] = []
        c.onReverseChange = { (on: Bool) -> Void in applied.append(on) }
        c.setReverse(true)
        XCTAssertEqual(applied, [true], "applied synchronously")
        XCTAssertTrue(sandbox.store.isReversed(video.id), "saved at once")
        c.setReverse(true)
        XCTAssertEqual(applied.count, 1, "the same value again changes nothing")
        let relaunched = VideoCoordinator(store: sandbox.store, announce: { (_: String) -> Void in })
        XCTAssertTrue(relaunched.reverse, "kept after a relaunch")
        relaunched.remove()
        XCTAssertFalse(relaunched.reverse, "Remove Video returns to forward")
    }

    // MARK: Messages (R5, S2)

    func testUnsupportedClipsShowAndAnnounceTheirSentenceOnce() throws {
        let sandbox = try makeSandbox()
        defer { sandbox.cleanUp() }
        _ = try sandbox.storedVideo()
        var spoken: [String] = []
        let c = VideoCoordinator(store: sandbox.store, announce: { (text: String) -> Void in spoken.append(text) })
        XCTAssertNil(c.reverseCaption, "nothing while forward")
        c.setReverse(true)
        c.reverseStateChanged(.preparing)
        XCTAssertEqual(c.reverseCaption, "Preparing reverse…")
        c.reverseStateChanged(.unsupported(.tooLong))
        let message = "Reverse playback is available for clips up to 30 seconds. This video plays forward."
        XCTAssertEqual(c.reverseCaption, message)
        c.reverseStateChanged(.unsupported(.tooLong))
        XCTAssertEqual(spoken, [message], "announced once")
        c.reverseStateChanged(.playing)
        XCTAssertNil(c.reverseCaption, "no caption while reversing")
        c.reverseStateChanged(.unsupported(.undecodable))
        XCTAssertEqual(c.reverseCaption, "This video can't be played in reverse. It plays forward.")
        c.setReverse(false)
        XCTAssertNil(c.reverseCaption, "Reverse off clears it")
        XCTAssertEqual(c.reverseState, .off)
        c.setReverse(true)
        c.reverseStateChanged(.unsupported(.tooLarge))
        XCTAssertEqual(c.reverseCaption, "Reverse playback is available for clips up to 1080p. This video plays forward.")
        _ = try sandbox.storedVideo()
        let other = VideoCoordinator(store: sandbox.store, announce: { (_: String) -> Void in })
        XCTAssertNil(other.reverseCaption, "a new video plays forward with no message")
    }
}
