// RecordingQualityAppTests.swift — REC-005-T09, T10: the record quality setting (default Standard,
// persistence, unknown values, disabled rows cannot be picked, the rows' size) and Record with injected
// capabilities (fallback with the X9c notice, refusal, the profile fixed per recording). Files are read back
// through the coordinator's DEBUG probe. Simulator results are never device evidence (Constitution X); the
// per-profile metadata is proven by the FrameRecording fixture.
import AudioCore
import FrameRecording
import Metal
import UIKit
import XCTest
@testable import projectM_iOS

/// Injected capabilities (REC-005-S2).
private struct StubCapabilities: RecordingEncoderCapabilities {
    var hevc = true
    var h264 = true
    var maxLongSide = 8_192
    var maxFramesPerSecond = 60

    func canEncode(_ codec: RecordingCodec, width: Int, height: Int) -> Bool {
        guard max(width, height) <= maxLongSide else { return false }
        return codec == .hevc ? hevc : h264
    }
}

/// A 64 × 48 visual fed by hand at 30 fps on the uptime clock.
@MainActor
private final class QualitySource: VideoRecordingSource {
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
private final class QualityContextBox {
    var value: VideoRecordingCoordinator.Context
    init(_ value: VideoRecordingCoordinator.Context) { self.value = value }
}

@MainActor
final class RecordingQualityAppTests: XCTestCase {
    private func suite() -> UserDefaults {
        let name = "RecordingQualityAppTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: name) }
        return defaults
    }

    private func setting(_ defaults: UserDefaults, caps: StubCapabilities = StubCapabilities(),
                         size: CGSize = CGSize(width: 1206, height: 2622)) -> RecordingQualitySetting {
        RecordingQualitySetting(defaults: defaults, capabilities: { () -> any RecordingEncoderCapabilities in caps },
                                rowSize: { () -> CGSize in size })
    }

    // MARK: - Setting (REC-005-R7, R9, R12)

    func testDefaultsToStandardAndPersists() {
        let defaults = suite()
        let s = setting(defaults)
        XCTAssertEqual(s.profile, .standard)
        XCTAssertNil(defaults.object(forKey: RecordingQualitySetting.profileKey), "nothing stored until changed")
        XCTAssertTrue(s.select(.high))
        XCTAssertEqual(setting(defaults).profile, .high, "a new store reads the saved value")
        defaults.set("ultra", forKey: RecordingQualitySetting.profileKey)
        XCTAssertEqual(setting(defaults).profile, .standard, "unknown → Standard")
        defaults.set(3, forKey: RecordingQualitySetting.profileKey)
        XCTAssertEqual(setting(defaults).profile, .standard, "not a string → Standard")
        XCTAssertEqual(RecordingQualitySetting.profileKey, "settings.recording.qualityProfile")
    }

    func testDisabledRowsShowTheirReasonAndCannotBePicked() {
        let defaults = suite()
        let s = setting(defaults, caps: StubCapabilities(hevc: false))
        XCTAssertFalse(s.select(.max))
        XCTAssertEqual(s.profile, .standard)
        XCTAssertNil(defaults.object(forKey: RecordingQualitySetting.profileKey))
        XCTAssertEqual(s.rowLabel(.max), "Max, unavailable: Needs HEVC, which this device cannot encode.")
        XCTAssertEqual(s.rowLabel(.draft), "Draft, 588×1280 · H.264 · 4 Mb/s · 30 fps")
        XCTAssertTrue(RecordingQualitySetting.tableText.contains("High: Up to 2560 px · HEVC · 20 Mb/s · 60 fps"))
    }

    func testRowsDescribeTheGivenSize() {
        let limited = StubCapabilities(maxLongSide: 1920)
        let phone = setting(suite(), caps: limited)
        XCTAssertEqual(phone.availability(.max).reason, .sizeUnsupported(width: 1206, height: 2622))
        let window = setting(suite(), caps: limited, size: CGSize(width: 1280, height: 720))
        XCTAssertEqual(window.rowLabel(.max), "Max, 1280×720 · HEVC · 40 Mb/s · 60 fps", "a smaller drawable: no upscaling")
    }

    // MARK: - Record (REC-005-R6, R11)

    private func device() throws -> MTLDevice {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device in this simulator") }
        return device
    }

    private func tempDirectory(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("rec005-\(name)-\(UUID().uuidString)", isDirectory: true)
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

    private func coordinator(_ source: QualitySource, profile: RecordingQualityProfile,
                             caps: StubCapabilities) -> (VideoRecordingCoordinator, QualityContextBox) {
        let box = QualityContextBox(.init(source: source, visualShown: true, outputLive: true, paused: false,
                                          qualityProfile: profile, qualityCapabilities: caps))
        let recording = VideoRecordingCoordinator(directory: tempDirectory("work"), debugDirectory: tempDirectory("out"),
                                                  checkInterval: nil, storageCheckInterval: nil) { box.value }
        return (recording, box)
    }

    private func recordFrames(_ recording: VideoRecordingCoordinator, _ source: QualitySource, between: (() -> Void)? = nil) throws {
        for frame in 0..<8 {
            if frame == 4 { between?() }
            try source.feed()
        }
        recording.stop(.user)
        waitUntil("read back") { recording.probe.hasPrefix("video") || recording.probe.hasPrefix("failed") }
    }

    func testUnavailableSelectionFallsBackAndAnnouncesX9c() throws {
        let source = try QualitySource(device: device())
        let (recording, _) = coordinator(source, profile: .max, caps: StubCapabilities(hevc: false))
        recording.toggle()
        XCTAssertEqual(recording.state, .recording)
        XCTAssertEqual(recording.recordingProfile, .standard, "High is HEVC-only too: Standard (H.264) is next")
        let notice = try XCTUnwrap(recording.notice)
        XCTAssertEqual(notice, "Recording at Standard: Needs HEVC, which this device cannot encode.")
        let event = StatusEventCatalog.recordingNotice(notice)
        XCTAssertEqual([event.id, event.announcement], ["X9c", notice])
        XCTAssertEqual(event.cause, .user)
        try recordFrames(recording, source)
        XCTAssertTrue(recording.probe.hasPrefix("video avc1 64x48"), recording.probe)
    }

    func testNothingEncodableRefusesWithEncoderUnavailable() throws {
        let source = try QualitySource(device: device())
        let (recording, _) = coordinator(source, profile: .high, caps: StubCapabilities(hevc: false, h264: false))
        recording.toggle()
        XCTAssertEqual(recording.state, .idle)
        XCTAssertEqual(recording.notice, RecordingFailure.encoderUnavailable.notice)
        XCTAssertNil(source.videoRecording)
    }

    func testChangingTheProfileDuringARecordingKeepsItsProfile() throws {
        let source = try QualitySource(device: device())
        let (recording, box) = coordinator(source, profile: .draft, caps: StubCapabilities())
        recording.toggle()
        XCTAssertEqual(recording.recordingProfile, .draft)
        XCTAssertNil(recording.notice, "no fallback, no notice")
        XCTAssertEqual(source.videoRecording?.recorder.settings, RecordingQualityProfile.draft.settings)
        try recordFrames(recording, source) { box.value.qualityProfile = .max }
        XCTAssertTrue(recording.probe.hasPrefix("video avc1 64x48"), "Draft is H.264: \(recording.probe)")
        XCTAssertEqual(recording.recordingAudio?.includesAudio, false, "audio is REC-004's decision, unchanged")
    }
}
