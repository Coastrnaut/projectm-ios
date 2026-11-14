// RecordingAudioAppTests.swift — REC-004-T16: the "Include microphone audio" setting, the decision the
// recording coordinator makes from the app's source mode, its status texts and events, and the audio's
// early end (source switch, new session, consent withdrawn), with a fake visual and a real normalized
// ring as the recording tap. Files are read back with AVFoundation. Simulator results are never device
// evidence (Constitution X); the alignment itself is proven by the FrameRecording fixture.
import AudioCore
import FrameRecording
import Metal
import UIKit
import XCTest
@testable import projectM_iOS

/// A visual the test feeds by hand: offscreen 64 × 48 frames stamped on the uptime clock (like the
/// display link), so the tap's audio and the frames share one clock.
@MainActor
private final class ClockedRecordingSource: VideoRecordingSource {
    let recordingDevice: MTLDevice
    let queue: MTLCommandQueue
    var recordingDrawableSize = CGSize(width: 64, height: 48)
    var isPresentingFrames = true
    var videoRecording: VideoRecordingTap?
    private var lastNanoseconds: UInt64 = 0

    init(device: MTLDevice) throws {
        recordingDevice = device
        queue = try XCTUnwrap(device.makeCommandQueue())
    }

    /// One frame, at least one 30 fps interval after the previous one on the uptime clock.
    func feed() throws {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: 64, height: 48, mipmapped: false)
        d.usage = [.renderTarget]
        let drawable = try XCTUnwrap(recordingDevice.makeTexture(descriptor: d))
        let commands = try XCTUnwrap(queue.makeCommandBuffer())
        let now = max(MonotonicClock.nowNanoseconds(), lastNanoseconds + 34_000_000)
        lastNanoseconds = now
        videoRecording?.record(commandBuffer: commands, presentationNanoseconds: now, drawable: drawable) { (texture: MTLTexture) -> Bool in
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = texture
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor = MTLClearColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
            guard let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return false }
            encoder.endEncoding()
            return true
        }
        commands.commit()
        commands.waitUntilCompleted()
        videoRecording?.recorder.waitForPendingFrames()
    }
}

@MainActor
private final class AudioContextBox {
    var value: VideoRecordingCoordinator.Context
    init(_ value: VideoRecordingCoordinator.Context) { self.value = value }
}

@MainActor
final class RecordingAudioAppTests: XCTestCase {
    private func suite() -> UserDefaults {
        let name = "RecordingAudioAppTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: name) }
        return defaults
    }

    private func device() throws -> MTLDevice {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device in this simulator") }
        return device
    }

    private func tempDirectory(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("rec004-\(name)-\(UUID().uuidString)", isDirectory: true)
    }

    private func waitUntil(_ description: String, timeout: TimeInterval = 10, _ condition: @escaping @MainActor () -> Bool) {
        let done = expectation(description: description)
        var fulfilled = false
        let timer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { (_: Timer) in
            MainActor.assumeIsolated {
                if !fulfilled, condition() {
                    fulfilled = true
                    done.fulfill()
                }
            }
        }
        wait(for: [done], timeout: timeout)
        timer.invalidate()
    }

    /// A context with a real normalized ring as the recording tap.
    private func context(_ source: ClockedRecordingSource, ring: NormalizedPCMRing, mode: AudioSourceMode?,
                         includeMicrophone: Bool = false, granted: Bool = false) -> AudioContextBox {
        AudioContextBox(.init(source: source, visualShown: true, outputLive: true, paused: false, audioMode: mode,
                              microphoneGranted: granted, includeMicrophone: includeMicrophone, audioTap: ring.recordingTap,
                              setAudioTapArmed: { (armed: Bool) -> Void in
                                  if armed { ring.armRecordingTap() } else { ring.disarmRecordingTap() }
                              }))
    }

    private func makeCoordinator(_ box: AudioContextBox) -> VideoRecordingCoordinator {
        VideoRecordingCoordinator(directory: tempDirectory("work"), debugDirectory: tempDirectory("out"), checkInterval: nil,
                                  storageCheckInterval: nil) { box.value }
    }

    /// Records `frames` frames, writing 10 ms of a 0.5 tone to the ring before each.
    private func record(_ recording: VideoRecordingCoordinator, source: ClockedRecordingSource, ring: NormalizedPCMRing,
                        frames: Int = 12, between: ((Int) -> Void)? = nil) throws {
        recording.toggle()
        XCTAssertEqual(recording.state, .recording)
        let tone = [Float](repeating: 0.5, count: 441 * 2)
        for frame in 0..<frames {
            between?(frame)
            ring.write(tone, frames: 441)
            try source.feed()
        }
        recording.stop(.user)
        waitUntil("read back") { recording.probe.hasPrefix("video") || recording.probe.hasPrefix("failed") }
    }

    // MARK: - Setting (REC-004-R3)

    func testSettingDefaultsOffAndPersists() {
        let defaults = suite()
        let setting = RecordingAudioSetting(defaults: defaults)
        XCTAssertFalse(setting.includeMicrophone)
        XCTAssertNil(defaults.object(forKey: RecordingAudioSetting.includeMicrophoneKey), "nothing stored until changed")
        setting.includeMicrophone = true
        XCTAssertTrue(RecordingAudioSetting(defaults: defaults).includeMicrophone, "a new store reads the saved value")
        defaults.set("yes", forKey: RecordingAudioSetting.includeMicrophoneKey)
        XCTAssertFalse(RecordingAudioSetting(defaults: defaults).includeMicrophone, "not a Bool → off")
        XCTAssertEqual(RecordingAudioSetting.includeMicrophoneKey, "settings.recording.includeMicrophone")
    }

    // MARK: - Decision from the app's modes (REC-004-R1, R2)

    func testModesMapToTheDecision() {
        typealias C = VideoRecordingCoordinator
        XCTAssertEqual(C.audioKind(.inAppPlayback), .inAppPlayback)
        XCTAssertEqual(C.audioKind(.microphone), .microphone)
        XCTAssertEqual(C.audioKind(.systemAppCapture), .systemCapture)
        XCTAssertNil(C.audioKind(nil))
        func decision(_ mode: AudioSourceMode?, mic: Bool, granted: Bool) -> RecordingAudioDecision {
            C.audioDecision(for: .init(source: nil, visualShown: true, outputLive: true, paused: false, audioMode: mode,
                                       microphoneGranted: granted, includeMicrophone: mic))
        }
        XCTAssertEqual(decision(.inAppPlayback, mic: false, granted: false).statusText, "Recording includes app audio.")
        XCTAssertEqual(decision(.systemAppCapture, mic: true, granted: true).statusText,
                       "Recording has no audio: other apps' audio is never recorded.")
        XCTAssertEqual(decision(.microphone, mic: false, granted: true), .exclude(.microphoneSettingOff))
        XCTAssertEqual(decision(.microphone, mic: true, granted: false), .exclude(.microphonePermissionMissing))
        XCTAssertEqual(decision(.microphone, mic: true, granted: true), .include(.microphone))
        XCTAssertEqual(decision(nil, mic: true, granted: true).statusText, "Recording has no audio.")
    }

    func testStatusEventsAreOnTheRecordingLane() {   // REC-004-R9
        let start = StatusEventCatalog.recordingAudio(.include(.appAudio))
        XCTAssertEqual(start.id, "X9a")
        XCTAssertEqual(start.kind, .recording)
        XCTAssertEqual(start.announcement, "Recording includes app audio.")
        XCTAssertEqual(start.cause, .user)
        let ended = StatusEventCatalog.recordingAudioEnded()
        XCTAssertEqual(ended.id, "X9b")
        XCTAssertEqual(ended.announcement, "Recording audio ended.")
        XCTAssertEqual(ended.cause, .system)
    }

    // MARK: - Files (REC-004-S2, S3)

    func testAppAudioIsRecorded() throws {
        let source = try ClockedRecordingSource(device: try device())
        let ring = NormalizedPCMRing()
        let box = context(source, ring: ring, mode: .inAppPlayback)
        let recording = makeCoordinator(box)
        XCTAssertEqual(recording.audioStatusText, "Recording includes app audio.")
        try record(recording, source: source, ring: ring)
        XCTAssertTrue(recording.probe.hasSuffix("audio=1"), recording.probe)
        XCTAssertFalse(ring.recordingTap.isArmed, "the tap is disarmed when the recording stops")
    }

    func testSystemCaptureAndMicrophoneWithoutConsentRecordNoAudio() throws {
        let source = try ClockedRecordingSource(device: try device())
        for (mode, mic, granted) in [(AudioSourceMode.systemAppCapture, true, true), (.microphone, false, true), (.microphone, true, false)] {
            let ring = NormalizedPCMRing()
            let recording = makeCoordinator(context(source, ring: ring, mode: mode, includeMicrophone: mic, granted: granted))
            try record(recording, source: source, ring: ring)
            XCTAssertTrue(recording.probe.hasSuffix("audio=0"), "\(mode) \(mic) \(granted): \(recording.probe)")
            XCTAssertFalse(recording.recordingAudio?.includesAudio ?? true)
        }
    }

    func testMicrophoneWithConsentIsRecorded() throws {
        let source = try ClockedRecordingSource(device: try device())
        let ring = NormalizedPCMRing()
        let recording = makeCoordinator(context(source, ring: ring, mode: .microphone, includeMicrophone: true, granted: true))
        try record(recording, source: source, ring: ring)
        XCTAssertTrue(recording.probe.hasSuffix("audio=1"), recording.probe)
        XCTAssertEqual(recording.recordingAudio, .include(.microphone))
    }

    // MARK: - Early end (REC-004-R5, S4)

    func testASourceSwitchEndsTheAudio() throws {
        let source = try ClockedRecordingSource(device: try device())
        let ring = NormalizedPCMRing()
        let box = context(source, ring: ring, mode: .inAppPlayback)
        let recording = makeCoordinator(box)
        try record(recording, source: source, ring: ring) { (frame: Int) -> Void in
            guard frame == 6 else { return }
            box.value.audioMode = .systemAppCapture
            recording.checkContext()
            XCTAssertTrue(recording.audioEnded)
            XCTAssertEqual(recording.audioStatusText, "Recording audio ended.")
            XCTAssertFalse(ring.recordingTap.isArmed, "nothing more reaches the recording")
            XCTAssertEqual(recording.state, .recording, "the video goes on")
        }
        XCTAssertTrue(recording.probe.hasSuffix("audio=1"), "the audio before the switch is kept: \(recording.probe)")
    }

    func testANewCaptureSessionEndsTheAudio() throws {
        let source = try ClockedRecordingSource(device: try device())
        let ring = NormalizedPCMRing()
        let recording = makeCoordinator(context(source, ring: ring, mode: .inAppPlayback))
        recording.toggle()
        try source.feed()
        ring.reset()   // a restart of the same mode: the ring disarms the tap itself
        recording.checkContext()
        XCTAssertTrue(recording.audioEnded)
        recording.stop(.user)
        waitUntil("finished") { recording.state == .idle }
    }

    func testWithdrawingMicrophoneConsentEndsTheAudio() throws {
        let source = try ClockedRecordingSource(device: try device())
        let ring = NormalizedPCMRing()
        let box = context(source, ring: ring, mode: .microphone, includeMicrophone: true, granted: true)
        let recording = makeCoordinator(box)
        recording.toggle()
        try source.feed()
        recording.checkContext()
        XCTAssertFalse(recording.audioEnded)
        box.value.includeMicrophone = false
        recording.checkContext()
        XCTAssertTrue(recording.audioEnded)
        XCTAssertFalse(ring.recordingTap.isArmed)
        recording.stop(.user)
        waitUntil("finished") { recording.state == .idle }
    }
}
