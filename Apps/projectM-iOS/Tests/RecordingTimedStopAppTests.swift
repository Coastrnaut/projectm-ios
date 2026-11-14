// RecordingTimedStopAppTests.swift — REC-008-T09, T11 (specs/180-rec-008-timed-stop, contract C3): the length
// setting (default Off, persistence, unknown value, the UI-test reset and launch argument), Record with a 10 s length
// and injected 60 Hz frame times through the real tap (exactly 300 frames at 30 fps, the timed-stop reason and notice,
// X13), the length fixed at start, a countdown not counted, the indicator text, and the stops that win before the
// target (manual, disk guard). The exact file is proven by the FrameRecording fixture (RecordingTimedStopTests).
// Simulator results are never device evidence (Constitution X).
import FrameRecording
import Metal
import XCTest
@testable import projectM_iOS

private struct TimedStopCapabilities: RecordingEncoderCapabilities {
    var maxFramesPerSecond = 60
    var renderLimit: RecordingRenderLimit? = nil
    func canEncode(_ codec: RecordingCodec, width: Int, height: Int) -> Bool { true }
}

/// A 64 × 48 visual fed with injected 60 Hz frame times through the real `VideoRecordingTap`.
@MainActor
private final class TimedStopSource: VideoRecordingSource {
    let recordingDevice: MTLDevice
    let queue: MTLCommandQueue
    var recordingDrawableSize = CGSize(width: 64, height: 48)
    var isPresentingFrames = true
    var videoRecording: VideoRecordingTap?
    private let drawable: MTLTexture

    init(device: MTLDevice) throws {
        recordingDevice = device
        queue = try XCTUnwrap(device.makeCommandQueue())
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: 64, height: 48, mipmapped: false)
        d.usage = [.renderTarget]
        drawable = try XCTUnwrap(device.makeTexture(descriptor: d))
    }

    /// Offers the frame shown at 60 Hz frame `k`.
    func feed(frame k: Int) throws {
        let commands = try XCTUnwrap(queue.makeCommandBuffer())
        let time: UInt64 = 20_000_000_000 + UInt64(k) * 1_000_000_000 / 60
        let tap = videoRecording
        tap?.record(commandBuffer: commands, presentationNanoseconds: time, drawable: drawable) { (texture: MTLTexture) -> Bool in
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = texture
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            guard let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return false }
            encoder.endEncoding()
            return true
        }
        commands.commit()
        commands.waitUntilCompleted()
        tap?.recorder.waitForPendingFrames()
    }
}

private final class TimedStopStorageProbe: StorageProbe, @unchecked Sendable {
    private let lock = NSLock()
    private var value: Int64?
    init(_ value: Int64?) { self.value = value }
    var available: Int64? {
        get { lock.withLock { () -> Int64? in value } }
        set { lock.withLock { () -> Void in value = newValue } }
    }
    func availableBytes(at directory: URL) -> Int64? { available }
}

/// The countdown's clock, advanced by hand (REC-008-R6 with a REC-007 countdown).
@MainActor
private final class TimedStopClock: RecordingCountdownClock {
    final class Step: RecordingCountdownTimer {
        let deadline: Double
        let action: @MainActor () -> Void
        var cancelled = false
        init(deadline: Double, action: @escaping @MainActor () -> Void) {
            self.deadline = deadline
            self.action = action
        }
        func cancel() { cancelled = true }
    }

    var now: Double = 100
    private var steps: [Step] = []

    func schedule(at deadline: Double, _ action: @escaping @MainActor () -> Void) -> any RecordingCountdownTimer {
        let step = Step(deadline: deadline, action: action)
        steps.append(step)
        return step
    }

    func advance(to time: Double) {
        while let next = steps.filter({ (s: Step) -> Bool in !s.cancelled && s.deadline <= time })
            .min(by: { (a: Step, b: Step) -> Bool in a.deadline < b.deadline }) {
            steps.removeAll { (s: Step) -> Bool in s === next }
            now = max(now, next.deadline)
            next.action()
        }
        now = time
    }
}

@MainActor
private final class TimedStopContextBox {
    var value: VideoRecordingCoordinator.Context
    init(_ value: VideoRecordingCoordinator.Context) { self.value = value }
}

@MainActor
final class RecordingTimedStopAppTests: XCTestCase {
    private let plenty: Int64 = 64_000_000_000
    private let low: Int64 = 50_000_000

    private struct Rig {
        let recording: VideoRecordingCoordinator
        let context: TimedStopContextBox
        let source: TimedStopSource
        let probe: TimedStopStorageProbe
        let clock: TimedStopClock
    }

    private func folder(_ name: String) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rec008-\(name)-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func rig(_ length: RecordingTimedStopLength = .ten, countdown: RecordingCountdownLength = .off) throws -> Rig {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device in this simulator") }
        let source = try TimedStopSource(device: device)
        var c = VideoRecordingCoordinator.Context(source: source, visualShown: true, outputLive: true, paused: false)
        c.qualityCapabilities = TimedStopCapabilities()
        c.frameRateChoice = .fps30
        c.timedStop = length
        c.countdown = countdown
        let box = TimedStopContextBox(c)
        let probe = TimedStopStorageProbe(plenty)
        let clock = TimedStopClock()
        let recording = VideoRecordingCoordinator(directory: folder("work"), debugDirectory: folder("out"), checkInterval: nil,
                                                  storageProbe: probe, storageCheckInterval: nil,
                                                  countdownClock: clock) { () -> VideoRecordingCoordinator.Context in
            box.value
        }
        return Rig(recording: recording, context: box, source: source, probe: probe, clock: clock)
    }

    private func suite() -> UserDefaults {
        let name = "RecordingTimedStopAppTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: name) }
        return defaults
    }

    /// Waits (polling the main run loop) until the recording is idle and its file was read back.
    private func waitForFinishedFile(_ recording: VideoRecordingCoordinator) {
        let deadline = Date().addingTimeInterval(10)
        while !(recording.state == .idle && recording.probe.hasPrefix("video")), Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertEqual(recording.state, .idle)
        XCTAssertTrue(recording.probe.hasPrefix("video"), recording.probe)
    }

    // MARK: - Setting (REC-008-R1, R9)

    func testSettingDefaultsToOffPersistsAndReadsUnknownAsOff() {
        let defaults = suite()
        let setting = RecordingTimedStopSetting(defaults: defaults, arguments: [])
        XCTAssertEqual(setting.length, .off)
        XCTAssertNil(defaults.object(forKey: RecordingTimedStopSetting.key), "nothing stored until changed")
        setting.length = .oneMinute
        XCTAssertEqual(defaults.string(forKey: RecordingTimedStopSetting.key), "60")
        XCTAssertEqual(RecordingTimedStopSetting(defaults: defaults, arguments: []).length, .oneMinute, "survives a relaunch")
        defaults.set("7", forKey: RecordingTimedStopSetting.key)
        XCTAssertEqual(RecordingTimedStopSetting(defaults: defaults, arguments: []).length, .off, "unknown → Off")
        XCTAssertEqual(RecordingTimedStopSetting(defaults: defaults, arguments: ["-uitestTimedStop", "10"]).length, .ten)
        XCTAssertEqual(RecordingTimedStopSetting(defaults: defaults, arguments: ["-uitestResetNotice"]).length, .off)
        XCTAssertEqual(RecordingTimedStopLength.allCases.map(\.rawValue), ["off", "10", "30", "60", "300"])
        XCTAssertEqual(RecordingTimedStopLength.allCases.map(\.seconds), [0, 10, 30, 60, 300])
        XCTAssertEqual(RecordingTimedStopLength.allCases.map(\.title), ["Off", "10 seconds", "30 seconds", "1 minute", "5 minutes"])
        XCTAssertEqual(RecordingTimedStopLength.fiveMinutes.stoppedNotice, "Recording stopped after 5 minutes.")
    }

    // MARK: - The timed stop (REC-008-R2, R3, R7, R8)

    func testTenSecondLengthStopsByItselfWithExactlyThreeHundredFrames() throws {
        let r = try rig(.ten)
        r.recording.toggle()
        XCTAssertEqual(r.recording.state, .recording)
        let tap = try XCTUnwrap(r.source.videoRecording)
        XCTAssertEqual(tap.recorder.settings.maxDurationSeconds, 10, "the length is the recording's media limit")
        XCTAssertEqual(tap.recorder.settings.maxFrameRate, 30)
        XCTAssertEqual(r.recording.indicatorText, "0:00 / 0:10")
        XCTAssertEqual(r.recording.indicatorAccessibilityText, "0:00 of 0:10")
        // 10.5 s of 60 Hz frames; the frame at 10.0 s crosses the end: the tap begins the finish and reports the stop.
        for k in 0..<630 where r.recording.state == .recording && r.source.videoRecording != nil {
            try r.source.feed(frame: k)
            if k % 60 == 0 { r.recording.checkContext() }
        }
        waitForFinishedFile(r.recording)
        XCTAssertEqual(r.recording.lastStopReason, .timedStop)
        let notice = try XCTUnwrap(r.recording.notice)
        XCTAssertEqual(notice, "Recording stopped after 10 seconds.")
        let event = StatusEventCatalog.recordingNotice(notice)
        XCTAssertEqual(event.id, "X13")
        XCTAssertEqual(event.announcement, "Recording stopped after 10 seconds.")
        let video = try XCTUnwrap(r.recording.lastRecording)
        // The live writer may drop a frame on a loaded machine (a busy queue or a not-ready encoder; a post-merge
        // run on the simulator wrote 292). Every one of the 300 frames of 30 fps × 10 s is written or counted as
        // dropped. A drop inside the recording leaves an empty slot on REC-006's grid; drops after the last written
        // frame leave no slot, so the file ends at its last frame (a post-merge run wrote 296 with 2 trailing drops:
        // 9.93 s). The end is never past 10 s.
        let dropped = video.statistics.dropped
        XCTAssertEqual(video.frameCount + dropped, 300, "frames + dropped = 30 fps × 10 s; \(video.statistics)")
        XCTAssertLessThanOrEqual(video.droppedFrames, dropped, "every empty slot is a frame the live writer dropped")
        let slots = Double(video.frameCount + video.droppedFrames)
        XCTAssertEqual(video.durationSeconds, slots / 30, accuracy: 1e-9, "the file ends at its last slot")
        XCTAssertLessThanOrEqual(video.durationSeconds, 10 + 1e-9)
        if dropped == 0 { XCTAssertEqual(video.durationSeconds, 10, accuracy: 1e-9) }
        XCTAssertTrue(r.recording.probe.contains("frames=\(video.frameCount) duration="), r.recording.probe)
        XCTAssertEqual(r.recording.elapsedSeconds, 10, accuracy: 1e-9)
        XCTAssertEqual(r.recording.indicatorText, "0:10 / 0:10")
    }

    func testOffKeepsTheTenMinuteLimitAndItsNotice() throws {
        let r = try rig(.off)
        r.recording.toggle()
        XCTAssertEqual(r.source.videoRecording?.recorder.settings.maxDurationSeconds, 600)
        XCTAssertEqual(r.recording.indicatorText, "0:00")
        for k in 0..<6 { try r.source.feed(frame: k) }
        r.recording.stop(.durationReached)   // what the tap reports at the limit
        waitForFinishedFile(r.recording)
        XCTAssertEqual(r.recording.lastStopReason, .durationReached)
        XCTAssertEqual(r.recording.notice, RecordingStopReason.durationReached.notice)
    }

    /// REC-008-R10: a change during the recording never changes it.
    func testTheLengthIsFixedWhenTheRecordingStarts() throws {
        let r = try rig(.ten)
        r.recording.toggle()
        r.context.value.timedStop = .fiveMinutes
        XCTAssertEqual(r.source.videoRecording?.recorder.settings.maxDurationSeconds, 10)
        XCTAssertEqual(r.recording.recordingLength, .ten)
        XCTAssertEqual(r.recording.indicatorText, "0:00 / 0:10")
        for k in 0..<6 { try r.source.feed(frame: k) }
        r.recording.stop(.durationReached)
        waitForFinishedFile(r.recording)
        XCTAssertEqual(r.recording.notice, "Recording stopped after 10 seconds.", "the running recording's length")
    }

    /// REC-008-R6: the length counts from the recording's first frame, not from the countdown.
    func testACountdownIsNotCounted() throws {
        let r = try rig(.ten, countdown: .three)
        r.recording.toggle()
        XCTAssertEqual(r.recording.state, .countingDown(3))
        r.clock.advance(to: 103)
        XCTAssertEqual(r.recording.state, .recording)
        let tap = try XCTUnwrap(r.source.videoRecording)
        XCTAssertEqual(tap.recorder.settings.maxDurationSeconds, 10, "the full length after the countdown")
        XCTAssertEqual(tap.recorder.recordedSeconds, 0, "nothing recorded during the countdown")
        r.clock.advance(to: 104)   // past the 0.5 s start guard
        r.recording.toggle()
        let deadline = Date().addingTimeInterval(10)
        while r.recording.state != .idle, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    }

    // MARK: - Stops before the target (REC-008-R5, S4)

    func testAManualStopBeforeTheTargetWorksNormally() throws {
        let r = try rig(.ten)
        r.recording.toggle()
        for k in 0..<24 { try r.source.feed(frame: k) }   // 0.4 s
        r.recording.toggle()
        waitForFinishedFile(r.recording)
        XCTAssertEqual(r.recording.lastStopReason, .user)
        // The user's own stop has no stop notice; the DEBUG folder mode then says "Recording saved." (never a timed stop).
        XCTAssertEqual(r.recording.notice, "Recording saved.", "no timed-stop notice for the user's own stop")
        let video = try XCTUnwrap(r.recording.lastRecording)
        // The live writer may drop a frame under load; the 12 slots of 0.4 s are accounted for (REC-006-R4).
        XCTAssertEqual(video.frameCount + video.droppedFrames, 12, "frames + dropped slots; \(video.statistics)")
        XCTAssertEqual(video.durationSeconds, 0.4, accuracy: 1e-9)
    }

    func testADiskGuardStopBeforeTheTargetKeepsItsOwnNotice() async throws {
        let r = try rig(.ten)
        r.recording.toggle()
        for k in 0..<24 { try r.source.feed(frame: k) }
        r.probe.available = low
        await r.recording.checkStorage()
        XCTAssertEqual(r.recording.lastStopReason, .lowStorage)
        for _ in 0..<500 where !(r.recording.state == .idle && r.recording.probe.hasPrefix("video")) {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(r.recording.probe.hasPrefix("video"), r.recording.probe)
        XCTAssertEqual(r.recording.notice, RecordingStopReason.lowStorage.notice)
        let video = try XCTUnwrap(r.recording.lastRecording)
        XCTAssertEqual(video.frameCount + video.droppedFrames, 12, "frames + dropped slots (live writer); \(video.statistics)")
    }
}
