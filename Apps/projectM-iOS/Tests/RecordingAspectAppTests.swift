// RecordingAspectAppTests.swift — REC-014-T09, T11: the aspect setting (default Match screen, persistence, unknown
// values, custom validation, rows and profile rows describe the planned size, a reduced custom size says so) and
// Record with injected capabilities (the plan's size, the aspect fixed per recording, the reduced-size X9c notice).
// Simulator results are never device evidence (Constitution X); the written size is proven by the FrameRecording
// fixture.
import FrameRecording
import Metal
import UIKit
import XCTest
@testable import projectM_iOS

private struct AspectStubCapabilities: RecordingEncoderCapabilities {
    var maxFramesPerSecond = 60
    var outputCap: RecordingOutputCap = .regular

    func canEncode(_ codec: RecordingCodec, width: Int, height: Int) -> Bool { true }
}

/// A 128 × 256 portrait visual fed at 30 Hz.
@MainActor
private final class PortraitSource: VideoRecordingSource {
    let recordingDevice: MTLDevice
    let queue: MTLCommandQueue
    var recordingDrawableSize = CGSize(width: 128, height: 256)
    var isPresentingFrames = true
    var videoRecording: VideoRecordingTap?

    init(device: MTLDevice) throws {
        recordingDevice = device
        queue = try XCTUnwrap(device.makeCommandQueue())
    }

    func feed(frame k: Int) throws {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: 128, height: 256, mipmapped: false)
        d.usage = [.renderTarget]
        let drawable = try XCTUnwrap(recordingDevice.makeTexture(descriptor: d))
        let commands = try XCTUnwrap(queue.makeCommandBuffer())
        let time: UInt64 = 10_000_000_000 + UInt64(k) * 1_000_000_000 / 30
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
private final class AspectContextBox {
    var value: VideoRecordingCoordinator.Context
    init(_ value: VideoRecordingCoordinator.Context) { self.value = value }
}

@MainActor
final class RecordingAspectAppTests: XCTestCase {
    private func suite() -> UserDefaults {
        let name = "RecordingAspectAppTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: name) }
        return defaults
    }

    private func setting(_ defaults: UserDefaults, caps: AspectStubCapabilities = AspectStubCapabilities()) -> RecordingQualitySetting {
        RecordingQualitySetting(defaults: defaults, capabilities: { () -> any RecordingEncoderCapabilities in caps },
                                rowSize: { () -> CGSize in CGSize(width: 1179, height: 2556) })
    }

    // MARK: - Setting (REC-014-R6, R7, R8)

    func testDefaultsToMatchScreenAndPersists() {
        let defaults = suite()
        let s = setting(defaults)
        XCTAssertEqual(s.aspect, .matchScreen)
        XCTAssertEqual(s.customSize, RecordingCustomSize(width: 1080, height: 1350))
        for key in RecordingQualitySetting.aspectKeys { XCTAssertNil(defaults.object(forKey: key), "nothing stored until changed") }
        XCTAssertTrue(s.select(.square))
        s.setCustom(width: 720, height: 1280)
        let reread = setting(defaults)
        XCTAssertEqual(reread.aspectKind, .square, "a new store reads the saved value")
        XCTAssertEqual(reread.customSize, RecordingCustomSize(width: 720, height: 1280))
        defaults.set("cinema", forKey: RecordingQualitySetting.aspectKey)
        XCTAssertEqual(setting(defaults).aspectKind, .screen, "unknown → Match screen")
        XCTAssertEqual(RecordingQualitySetting.aspectKeys,
                       ["settings.recording.aspect", "settings.recording.customWidth", "settings.recording.customHeight"])
    }

    func testCustomSizeIsValidatedWhenEntered() {
        let s = setting(suite())
        s.setCustom(width: 1081, height: 1350)
        XCTAssertEqual(s.customSize.width, 1080, "odd rounds down to even")
        s.setCustom(width: 50, height: 9000)
        XCTAssertEqual(s.customSize, RecordingCustomSize(width: 128, height: 4096), "clamped to 128...4096")
    }

    func testRowsShowThePlannedSizeAndAReducedCustomSize() {
        let s = setting(suite())
        XCTAssertTrue(s.detail(.square).hasPrefix("1178×1178 · HEVC"), s.detail(.square))
        XCTAssertTrue(s.detail(.landscape).hasPrefix("1152×648 · "), s.detail(.landscape))
        XCTAssertTrue(s.detail(.screen).hasPrefix("884×1920 · "), "Match screen: REC-005's row")
        XCTAssertTrue(s.select(.square))
        XCTAssertTrue(s.rowLabel(.standard).hasPrefix("Standard, 1178×1178 · HEVC"), "profile rows describe the aspect")
        XCTAssertTrue(s.select(.max))
        s.setCustom(width: 2000, height: 2500)
        XCTAssertEqual(s.detail(.custom), "Reduced to 1176×1470 on this screen · HEVC · 40 Mb/s · 60 fps")
        XCTAssertEqual(s.rowLabel(.custom), "Custom 2000×2500, Reduced to 1176×1470 on this screen · HEVC · 40 Mb/s · 60 fps")
        let compact = setting(suite(), caps: AspectStubCapabilities(outputCap: .compact))
        XCTAssertTrue(compact.select(.max))
        XCTAssertTrue(compact.detail(.screen).hasPrefix("1178×2556"), "a phone screen fits the compact cap")
    }

    func testDeviceCapIsThisDevicesClass() {
        let expected = RecordingOutputCap.device(physicalMemory: ProcessInfo.processInfo.physicalMemory)
        XCTAssertEqual(RecordingQualitySetting.deviceOutputCap, expected)
        XCTAssertEqual(RecordingQualitySetting.deviceCapabilities().outputCap, expected)
    }

    // MARK: - Record (REC-014-R6, R9, R10)

    private func device() throws -> MTLDevice {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device in this simulator") }
        return device
    }

    private func tempDirectory(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("rec014-\(name)-\(UUID().uuidString)", isDirectory: true)
    }

    private func coordinator(_ source: PortraitSource, aspect: RecordingAspect, profile: RecordingQualityProfile = .draft,
                             caps: AspectStubCapabilities) -> (VideoRecordingCoordinator, AspectContextBox) {
        var context = VideoRecordingCoordinator.Context(source: source, visualShown: true, outputLive: true, paused: false,
                                                        qualityProfile: profile, qualityCapabilities: caps)
        context.aspect = aspect
        let box = AspectContextBox(context)
        let recording = VideoRecordingCoordinator(directory: tempDirectory("work"), debugDirectory: tempDirectory("out"),
                                                  checkInterval: nil, storageCheckInterval: nil) { box.value }
        return (recording, box)
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

    func testSquareRecordingUsesThePlannedSizeAndKeepsItsAspect() throws {
        let source = try PortraitSource(device: device())
        let (recording, box) = coordinator(source, aspect: .square, caps: AspectStubCapabilities())
        recording.toggle()
        XCTAssertEqual(recording.state, .recording)
        XCTAssertNil(recording.notice)
        let geometry = try XCTUnwrap(source.videoRecording?.recorder.geometry)
        XCTAssertEqual([geometry.outputWidth, geometry.outputHeight], [128, 128])
        XCTAssertTrue(geometry.cropsToFill)
        for k in 0..<6 {
            if k == 3 { box.value.aspect = .landscape }   // REC-014-R10: the next recording's choice
            try source.feed(frame: k)
        }
        XCTAssertEqual(source.videoRecording?.recorder.geometry.outputHeight, 128, "the running recording keeps its aspect")
        recording.stop(.user)
        waitUntil("read back") { recording.probe.hasPrefix("video") || recording.probe.hasPrefix("failed") }
        XCTAssertTrue(recording.probe.contains(" 128x128 "), recording.probe)
        XCTAssertEqual([recording.lastRecording?.width, recording.lastRecording?.height], [128, 128])
    }

    func testReducedCustomSizeIsAnnouncedAsX9c() throws {
        let source = try PortraitSource(device: device())
        let caps = AspectStubCapabilities(outputCap: .compact)
        let (recording, _) = coordinator(source, aspect: .custom(RecordingCustomSize(width: 4096, height: 4096)), profile: .max,
                                         caps: caps)
        recording.toggle()
        XCTAssertEqual(recording.state, .recording)
        let notice = try XCTUnwrap(recording.notice)
        XCTAssertEqual(notice, "Recording at 128×128: Custom size reduced to fit this device.")
        let event = StatusEventCatalog.recordingNotice(notice)
        XCTAssertEqual([event.id, event.announcement], ["X9c", notice])
        for k in 0..<3 { try source.feed(frame: k) }
        recording.stop(.user)
        waitUntil("read back") { recording.probe.hasPrefix("video") || recording.probe.hasPrefix("failed") }
        XCTAssertTrue(recording.probe.contains(" 128x128 "), recording.probe)
    }
}
