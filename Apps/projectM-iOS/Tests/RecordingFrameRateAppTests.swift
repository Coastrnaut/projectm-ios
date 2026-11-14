// RecordingFrameRateAppTests.swift — REC-006-T10, T12: the frame-rate setting (default Profile default,
// persistence, unknown values, disabled rows cannot be picked, the profile rows describe the effective rate), the
// render cap from QualityGovernor's rules, and Record with injected capabilities and injected frame times (the
// rate fallback with its X9c notice, the rate fixed per recording, the last recording's rate and dropped
// frames). Simulator results are never device evidence (Constitution X); the file grid is proven by the
// FrameRecording fixture.
import FrameRecording
import Metal
import Rendering
import UIKit
import XCTest
@testable import projectM_iOS

/// Injected capabilities (REC-006-S4).
private struct RateStubCapabilities: RecordingEncoderCapabilities {
    var maxFramesPerSecond = 60
    var renderLimit: RecordingRenderLimit? = nil

    func canEncode(_ codec: RecordingCodec, width: Int, height: Int) -> Bool { true }
}

/// A 64 × 48 visual fed with injected frame times (60 Hz from an arbitrary origin).
@MainActor
private final class InjectedTimeSource: VideoRecordingSource {
    let recordingDevice: MTLDevice
    let queue: MTLCommandQueue
    var recordingDrawableSize = CGSize(width: 64, height: 48)
    var isPresentingFrames = true
    var videoRecording: VideoRecordingTap?

    init(device: MTLDevice) throws {
        recordingDevice = device
        queue = try XCTUnwrap(device.makeCommandQueue())
    }

    /// Offers the frame shown at 60 Hz frame `k`.
    func feed(frame k: Int) throws {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: 64, height: 48, mipmapped: false)
        d.usage = [.renderTarget]
        let drawable = try XCTUnwrap(recordingDevice.makeTexture(descriptor: d))
        let commands = try XCTUnwrap(queue.makeCommandBuffer())
        let time: UInt64 = 10_000_000_000 + UInt64(k) * 1_000_000_000 / 60
        videoRecording?.record(commandBuffer: commands, presentationNanoseconds: time, drawable: drawable) { (texture: MTLTexture) -> Bool in
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
private final class RateContextBox {
    var value: VideoRecordingCoordinator.Context
    init(_ value: VideoRecordingCoordinator.Context) { self.value = value }
}

@MainActor
final class RecordingFrameRateAppTests: XCTestCase {
    private func suite() -> UserDefaults {
        let name = "RecordingFrameRateAppTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: name) }
        return defaults
    }

    private func setting(_ defaults: UserDefaults, caps: RateStubCapabilities = RateStubCapabilities()) -> RecordingQualitySetting {
        RecordingQualitySetting(defaults: defaults, capabilities: { () -> any RecordingEncoderCapabilities in caps },
                                rowSize: { () -> CGSize in CGSize(width: 1206, height: 2622) })
    }

    // MARK: - Setting (REC-006-R6, R8, R9)

    func testDefaultsToProfileDefaultAndPersists() {
        let defaults = suite()
        let s = setting(defaults)
        XCTAssertEqual(s.frameRate, .profileDefault)
        XCTAssertNil(defaults.object(forKey: RecordingQualitySetting.frameRateKey), "nothing stored until changed")
        XCTAssertEqual(s.title(.profileDefault), "Profile default (30 fps)", "Standard's rate")
        XCTAssertTrue(s.select(.fps24))
        XCTAssertEqual(setting(defaults).frameRate, .fps24, "a new store reads the saved value")
        defaults.set("25", forKey: RecordingQualitySetting.frameRateKey)
        XCTAssertEqual(setting(defaults).frameRate, .profileDefault, "unknown → Profile default")
        XCTAssertEqual(RecordingQualitySetting.frameRateKey, "settings.recording.frameRate")
    }

    func testUnavailableRatesShowTheirReasonAndCannotBePicked() {
        let defaults = suite()
        let lowPower = setting(defaults, caps: RateStubCapabilities(renderLimit: RecordingRenderLimit(reason: .lowPowerMode)))
        XCTAssertFalse(lowPower.select(.fps60))
        XCTAssertEqual(lowPower.frameRate, .profileDefault)
        XCTAssertNil(defaults.object(forKey: RecordingQualitySetting.frameRateKey))
        XCTAssertEqual(lowPower.rowLabel(.fps60), "60 fps, unavailable: Low Power Mode limits the visual to 30 fps.")
        XCTAssertEqual(lowPower.rowLabel(.fps30), "30 fps")
        let thirty = setting(suite(), caps: RateStubCapabilities(maxFramesPerSecond: 30))
        XCTAssertEqual(thirty.rowLabel(.fps60), "60 fps, unavailable: This display shows at most 30 fps.")
        XCTAssertEqual(thirty.availability(.high).reason, .frameRateUnsupported(maximum: 30), "Profile default: REC-005 unchanged")
        XCTAssertTrue(thirty.select(.fps24))
        XCTAssertEqual(thirty.rowLabel(.high), "High, 1178×2560 · HEVC · 20 Mb/s · 24 fps", "profile rows describe the effective rate")
    }

    func testRenderCapFollowsQualityGovernor() {
        XCTAssertEqual(RecordingQualitySetting.renderLimit(thermal: .nominal, lowPower: true),
                       RecordingRenderLimit(reason: .lowPowerMode, maximumFramesPerSecond: 30))
        XCTAssertEqual(RecordingQualitySetting.renderLimit(thermal: .serious, lowPower: false)?.reason, .thermal)
        XCTAssertNil(RecordingQualitySetting.renderLimit(thermal: .fair, lowPower: false))
    }

    // MARK: - Record (REC-006-R4, R7, R10)

    private func device() throws -> MTLDevice {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device in this simulator") }
        return device
    }

    private func tempDirectory(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("rec006-\(name)-\(UUID().uuidString)", isDirectory: true)
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

    private func coordinator(_ source: InjectedTimeSource, choice: RecordingFrameRateChoice,
                             caps: RateStubCapabilities) -> (VideoRecordingCoordinator, RateContextBox) {
        let box = RateContextBox(.init(source: source, visualShown: true, outputLive: true, paused: false,
                                       qualityProfile: .draft, qualityCapabilities: caps, frameRateChoice: choice))
        let recording = VideoRecordingCoordinator(directory: tempDirectory("work"), debugDirectory: tempDirectory("out"),
                                                  checkInterval: nil, storageCheckInterval: nil) { box.value }
        return (recording, box)
    }

    /// 24 fps from 60 Hz frames 0-9 and 22-35 (a 200 ms stall): slots 0-14; slots 5-8 have no frame in their
    /// window, and slot 4's only frame (150 ms) was passed over for the predicted 166.7 ms frame that the stall
    /// never delivered (research REC-006-D2, D8: the stall's empty slots plus at most one).
    func testTwentyFourFpsRecordingReportsItsRateAndDroppedFrames() throws {
        let source = try InjectedTimeSource(device: device())
        let (recording, box) = coordinator(source, choice: .fps24, caps: RateStubCapabilities())
        recording.toggle()
        XCTAssertEqual(recording.state, .recording)
        XCTAssertNil(recording.notice)
        XCTAssertEqual(source.videoRecording?.recorder.settings.maxFrameRate, 24)
        for k in Array(0...9) + Array(22...35) {
            if k == 22 { box.value.frameRateChoice = .fps60 }   // REC-006-R10: the next recording's choice
            try source.feed(frame: k)
        }
        XCTAssertEqual(source.videoRecording?.recorder.settings.maxFrameRate, 24, "the running recording keeps its rate")
        recording.stop(.user)
        waitUntil("read back") { recording.probe.hasPrefix("video") || recording.probe.hasPrefix("failed") }
        let last = try XCTUnwrap(recording.lastRecording)
        XCTAssertEqual(last.frameRate, 24)
        // The stall empties 5 slots; on a loaded machine the live writer may also drop a frame, which empties its slot
        // and is counted (each frame is awaited, so no slot is refilled).
        XCTAssertEqual(last.droppedFrames, 5 + last.statistics.dropped, "the stall's 5 slots plus any frame the writer dropped")
        XCTAssertEqual(last.frameCount + last.droppedFrames, 15, "slots 0-14")
        XCTAssertTrue(recording.probe.contains("frames=\(last.frameCount) duration=0.62"), recording.probe)
    }

    func testRenderCapLowersAnExplicitRateWithX9c() throws {
        let source = try InjectedTimeSource(device: device())
        let caps = RateStubCapabilities(renderLimit: RecordingRenderLimit(reason: .lowPowerMode))
        let (recording, _) = coordinator(source, choice: .fps60, caps: caps)
        recording.toggle()
        XCTAssertEqual(recording.state, .recording)
        XCTAssertEqual(source.videoRecording?.recorder.settings.maxFrameRate, 30)
        let notice = try XCTUnwrap(recording.notice)
        XCTAssertEqual(notice, "Recording at 30 fps: Low Power Mode limits the visual to 30 fps.")
        let event = StatusEventCatalog.recordingNotice(notice)
        XCTAssertEqual([event.id, event.announcement], ["X9c", notice])
        for k in 0..<6 { try source.feed(frame: k) }
        recording.stop(.user)
        waitUntil("read back") { recording.probe.hasPrefix("video") || recording.probe.hasPrefix("failed") }
        XCTAssertEqual(recording.lastRecording?.frameRate, 30)
        XCTAssertEqual(recording.lastRecording?.droppedFrames, 0, "60 Hz into 30 fps")
    }
}
