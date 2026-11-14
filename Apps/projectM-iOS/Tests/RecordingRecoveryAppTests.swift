// RecordingRecoveryAppTests.swift — REC-016-T07-T10 (specs/226-rec-016-recording-interruption-recovery, contract C3,
// C4): the coordinator after an injected writer failure (resources released, notice, the kept part offered and read
// back), an injected start failure (nothing on disk), the background stop (finished and offered) and the thermal
// guard. A fake source feeds offscreen 64 × 48 frames. Simulator results are never device evidence (Constitution X).
import FrameRecording
import Metal
import UIKit
import XCTest
@testable import projectM_iOS

/// A source the test feeds by hand (offscreen 64 × 48 frames at 30 fps of the frame clock).
@MainActor
private final class RecoverySource: VideoRecordingSource {
    let recordingDevice: MTLDevice
    let queue: MTLCommandQueue
    var recordingDrawableSize = CGSize(width: 64, height: 48)
    var isPresentingFrames = true
    var videoRecording: VideoRecordingTap?
    private var frame = 0

    init(device: MTLDevice) throws {
        recordingDevice = device
        queue = try XCTUnwrap(device.makeCommandQueue())
    }

    func feed() throws {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: 64, height: 48, mipmapped: false)
        d.usage = [.renderTarget]
        let drawable = try XCTUnwrap(recordingDevice.makeTexture(descriptor: d))
        let commands = try XCTUnwrap(queue.makeCommandBuffer())
        let level = Double(frame % 10) / 10
        let recorder = videoRecording?.recorder
        videoRecording?.record(commandBuffer: commands, presentationNanoseconds: UInt64(frame) * 1_000_000_000 / 30,
                               drawable: drawable) { (texture: MTLTexture) -> Bool in
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = texture
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor = MTLClearColor(red: level, green: level, blue: level, alpha: 1)
            guard let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return false }
            encoder.endEncoding()
            return true
        }
        commands.commit()
        commands.waitUntilCompleted()
        recorder?.waitForPendingFrames()
        frame += 1
    }
}

@MainActor
private final class RecoveryContext {
    var value: VideoRecordingCoordinator.Context
    var thermal: RecordingThermalLevel = .nominal
    init(_ value: VideoRecordingCoordinator.Context) { self.value = value }
}

private final class AmpleStorage: StorageProbe, @unchecked Sendable {
    func availableBytes(at directory: URL) -> Int64? { 64_000_000_000 }
}

@MainActor
final class RecordingRecoveryAppTests: XCTestCase {
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

    private func device() throws -> MTLDevice {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device in this simulator") }
        return device
    }

    private func directory(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("rec016-\(name)-\(UUID().uuidString)", isDirectory: true)
    }

    /// Records into `folder` (the REC-012 offer, not the DEBUG folder) with an optional fault and the box's thermal level.
    private func makeCoordinator(_ box: RecoveryContext, folder: URL, fault: RecordingWriterFault? = nil) -> VideoRecordingCoordinator {
        VideoRecordingCoordinator(directory: folder, debugDirectory: nil, checkInterval: nil, storageProbe: AmpleStorage(),
                                  storageCheckInterval: nil, writerFault: fault,
                                  thermalLevel: { () -> RecordingThermalLevel in box.thermal }) {
            box.value
        }
    }

    private func inspect(_ url: URL) -> RecordedVideoInfo? {
        let done = expectation(description: "inspected")
        nonisolated(unsafe) var info: RecordedVideoInfo?
        Task.detached {
            info = await RecordedVideoInspector.inspect(url)
            done.fulfill()
        }
        wait(for: [done], timeout: 10)
        return info
    }

    /// REC-016 acceptance in the app: an append failure mid-recording → the session is idle, the tap detached, the
    /// recorder and writer released, the notice shown (X13), and the offered file reads back with the frames before it.
    func testInjectedWriterFailureReleasesResourcesAndOffersTheKeptPart() throws {
        let source = try RecoverySource(device: try device())
        let box = RecoveryContext(.init(source: source, visualShown: true, outputLive: true, paused: false))
        let recorders = RecordingResourceLedger.liveRecorders, writers = RecordingResourceLedger.liveWriters
        let recording = makeCoordinator(box, folder: directory("append"), fault: .appendFailure(afterFrames: 10))
        recording.toggle()
        XCTAssertEqual(recording.state, .recording)
        XCTAssertEqual(RecordingResourceLedger.liveWriters, writers + 1)
        for _ in 0..<12 { try source.feed() }   // the 11th append fails; the tap reports it on the next frame
        waitUntil("offered") { recording.state == .idle && recording.offered != nil }
        defer { recording.discardOffered() }
        XCTAssertEqual(recording.lastStopReason, .writerFailed)
        XCTAssertEqual(recording.notice, "Recording stopped because of a write error. The part recorded before it was kept.")
        XCTAssertEqual(StatusEventCatalog.recordingNotice(recording.notice ?? "").id, "X13")
        XCTAssertNil(source.videoRecording, "the tap is detached")
        XCTAssertFalse(recording.holdsRecorder)
        waitUntil("released") {
            RecordingResourceLedger.liveRecorders == recorders && RecordingResourceLedger.liveWriters == writers
        }
        let video = try XCTUnwrap(recording.lastRecording)
        XCTAssertNotNil(video.interruption)
        XCTAssertEqual(video.frameCount, 10, "\(video.statistics)")
        let info = try XCTUnwrap(inspect(try XCTUnwrap(recording.offered)))
        XCTAssertEqual(info.frameCount, 10)
        XCTAssertTrue(info.timesStrictlyIncrease)
        recording.discardOffered()
        recording.toggle()
        XCTAssertEqual(recording.state, .recording, "Record works again")
        recording.toggle()
        waitUntil("stopped") { recording.state == .idle }
    }

    /// REC-016-S2: a start failure after the writer existed: idle, the notice, and nothing in the recording folder.
    func testInjectedStartFailureLeavesNothingOnDisk() throws {
        let source = try RecoverySource(device: try device())
        let box = RecoveryContext(.init(source: source, visualShown: true, outputLive: true, paused: false))
        let folder = directory("start")
        let writers = RecordingResourceLedger.liveWriters
        let recording = makeCoordinator(box, folder: folder, fault: .startFailure)
        recording.toggle()
        XCTAssertEqual(recording.state, .idle)
        XCTAssertEqual(recording.notice, "The recording couldn't be finished.")
        XCTAssertNil(source.videoRecording)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), [], "no file left")
        XCTAssertEqual(RecordingResourceLedger.liveWriters, writers)
    }

    /// REC-016-S3: leaving the app finishes the file and offers it (not deleted) with the background notice.
    func testBackgroundStopFinishesAndOffersTheFile() throws {
        let source = try RecoverySource(device: try device())
        let box = RecoveryContext(.init(source: source, visualShown: true, outputLive: true, paused: false))
        let recording = makeCoordinator(box, folder: directory("background"))
        recording.toggle()
        for _ in 0..<4 { try source.feed() }
        recording.appEnteredBackground()
        waitUntil("offered") { recording.state == .idle && recording.offered != nil }
        defer { recording.discardOffered() }
        XCTAssertEqual(recording.lastStopReason, .background)
        XCTAssertEqual(recording.notice, "Recording stopped when the app left the screen.")
        let video = try XCTUnwrap(recording.lastRecording)
        XCTAssertNil(video.interruption)
        let info = try XCTUnwrap(inspect(try XCTUnwrap(recording.offered)))
        XCTAssertEqual(info.frameCount, video.frameCount)
        XCTAssertGreaterThanOrEqual(info.frameCount, 2)
    }

    /// REC-016-S4: Record refused at Critical; Serious warns once and keeps recording; Critical stops and offers.
    func testThermalWarningAndStop() throws {
        let source = try RecoverySource(device: try device())
        let box = RecoveryContext(.init(source: source, visualShown: true, outputLive: true, paused: false))
        let recording = makeCoordinator(box, folder: directory("thermal"))
        box.thermal = .critical
        recording.toggle()
        XCTAssertEqual(recording.state, .idle)
        XCTAssertEqual(recording.probe, "refused: thermal")
        XCTAssertEqual(recording.notice, "The device is too hot to record. Try again when it cools down.")
        XCTAssertEqual(StatusEventCatalog.recordingNotice(recording.notice ?? "").id, "X12")
        box.thermal = .fair
        recording.toggle()
        XCTAssertEqual(recording.state, .recording)
        for _ in 0..<3 { try source.feed() }
        box.thermal = .serious
        recording.checkContext()
        XCTAssertEqual(recording.state, .recording)
        XCTAssertEqual(recording.notice, "The device is getting hot. Recording stops if it gets hotter.")
        XCTAssertEqual(StatusEventCatalog.recordingNotice(recording.notice ?? "").id, "X13")
        recording.clearNotice()
        recording.checkContext()
        XCTAssertNil(recording.notice, "warned once")
        try source.feed()
        box.thermal = .critical
        recording.checkContext()
        XCTAssertEqual(recording.lastStopReason, .thermal)
        waitUntil("offered") { recording.state == .idle && recording.offered != nil }
        defer { recording.discardOffered() }
        XCTAssertEqual(recording.notice, "Recording stopped because the device is too hot.")
        XCTAssertEqual(StatusEventCatalog.recordingNotice(recording.notice ?? "").id, "X13")
    }

    func testThermalStateMapping() {
        XCTAssertEqual(VideoRecordingCoordinator.recordingThermalLevel(.nominal), .nominal)
        XCTAssertEqual(VideoRecordingCoordinator.recordingThermalLevel(.fair), .fair)
        XCTAssertEqual(VideoRecordingCoordinator.recordingThermalLevel(.serious), .serious)
        XCTAssertEqual(VideoRecordingCoordinator.recordingThermalLevel(.critical), .critical)
    }
}
