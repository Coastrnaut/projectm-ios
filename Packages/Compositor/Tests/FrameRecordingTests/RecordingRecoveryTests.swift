// RecordingRecoveryTests.swift — REC-016-T05, T08 (specs/226-rec-016-recording-interruption-recovery, contract C1, C2):
// injected append, writer, finish and start failures on the real writer with short fixtures (at most 1.5 s of 64 × 48
// frames, offline writer). Asserts the recorder's resources are released (ledger, frames in flight) and reads the kept
// file back. GPU tests skip without a Metal device; the thermal guard rules run everywhere AVFoundation does.
#if canImport(Metal) && canImport(AVFoundation) && !COMPOSITOR_NO_METAL
import AVFoundation
@testable import FrameRecording
import Foundation
import Metal
import XCTest

final class RecordingRecoveryTests: XCTestCase {
    private let frame: UInt64 = 1_000_000_000 / 30

    private func gpu() throws -> (MTLDevice, MTLCommandQueue) {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw XCTSkip("No Metal device (CI simulator or Linux); the rule tests cover the contract.")
        }
        return (device, queue)
    }

    private func temporaryURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("REC-016-\(name)-\(UUID().uuidString).mp4")
    }

    /// H.264 (fast everywhere), 0.5 s fragments so the fixtures stay short.
    private var settings: RecordingSettings {
        var s = RecordingSettings(codecPreference: [.h264])
        s.fragmentIntervalSeconds = 0.5
        return s
    }

    @discardableResult
    private func offer(_ recorder: MetalFrameRecorder, queue: MTLCommandQueue, index: Int) throws -> MetalFrameRecorder.FrameOutcome {
        let commands = try XCTUnwrap(queue.makeCommandBuffer())
        let level = Double(index % 10) / 10
        let outcome = recorder.recordFrame(presentationNanoseconds: UInt64(index) * frame, drawableWidth: 64, drawableHeight: 48,
                                           commandBuffer: commands) { (texture: MTLTexture) -> Bool in
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
        recorder.waitForPendingFrames()
        return outcome
    }

    private struct Run {
        let result: Result<RecordedVideo, RecordingFailure>
        let appended: Int
    }

    /// Records `frames` frames (stopping at the first `.failed`), finishes, releases the recorder and checks the ledger.
    private func record(_ name: String, url: URL, fault: RecordingWriterFault, frames: Int) async throws -> Run {
        let (device, queue) = try gpu()
        let recorders = RecordingResourceLedger.liveRecorders, writers = RecordingResourceLedger.liveWriters
        var appended = 0
        var result: Result<RecordedVideo, RecordingFailure>
        do {
            let recorder = try MetalFrameRecorder(device: device, url: url, drawableWidth: 64, drawableHeight: 48,
                                                  settings: settings, realTime: false, fault: fault)
            XCTAssertEqual(RecordingResourceLedger.liveRecorders, recorders + 1)
            XCTAssertEqual(RecordingResourceLedger.liveWriters, writers + 1)
            for i in 0..<frames {
                if try offer(recorder, queue: queue, index: i) == .failed { break }
            }
            appended = recorder.statistics.written
            result = await recorder.finish()
            XCTAssertEqual(recorder.framesInFlight, 0, "\(name): nothing in flight")
        }
        try await Task.sleep(for: .milliseconds(50))   // the finish task's last references go
        XCTAssertEqual(RecordingResourceLedger.liveRecorders, recorders, "\(name): the recorder is released")
        XCTAssertEqual(RecordingResourceLedger.liveWriters, writers, "\(name): the writer and its pool are released")
        return Run(result: result, appended: appended)
    }

    /// The kept file: readable, strictly increasing times on the 30 fps grid from 0, frames within one fragment
    /// (15 frames) plus 0.5 s of encoder lag (15 frames) of what was appended.
    private func assertKept(_ run: Run, url: URL, name: String) async throws {
        let video = try run.result.get()
        XCTAssertNotNil(video.interruption, name)
        let read = await RecordedVideoInspector.inspect(url)
        let info = try XCTUnwrap(read, name)
        XCTAssertEqual(info.frameCount, video.frameCount, name)
        XCTAssertGreaterThanOrEqual(info.frameCount, run.appended - 30, "\(name): appended \(run.appended)")
        XCTAssertLessThanOrEqual(info.frameCount, run.appended, name)
        XCTAssertTrue(info.timesStrictlyIncrease, name)
        XCTAssertEqual(info.presentationTicks.first, 0, name)
        XCTAssertEqual(info.presentationTicks.last, Int64(info.frameCount - 1) * 20, name)
        XCTAssertEqual(video.durationSeconds, info.durationSeconds, accuracy: 0.001, name)
    }

    /// REC-016-S1: an append failure with the writer still healthy → the file is finished at the last good frame.
    func testAppendFailureKeepsEveryFrameBeforeIt() async throws {
        let url = temporaryURL("append")
        defer { try? FileManager.default.removeItem(at: url) }
        let run = try await record("append", url: url, fault: .appendFailure(afterFrames: 30), frames: 40)
        XCTAssertEqual(run.appended, 30)
        try await assertKept(run, url: url, name: "append")
        XCTAssertEqual(try run.result.get().frameCount, 30, "a healthy writer keeps every appended frame")
        XCTAssertEqual(try run.result.get().interruption, .writerFailed("The operation could not be completed"))
    }

    /// REC-016-S1: the real writer fails (AVFoundation's failed state) → its completed fragments are kept.
    func testWriterFailureKeepsTheCompletedFragments() async throws {
        let url = temporaryURL("writer")
        defer { try? FileManager.default.removeItem(at: url) }
        let run = try await record("writer", url: url, fault: .writerFailure(afterFrames: 45), frames: 50)
        XCTAssertEqual(run.appended, 45)
        try await assertKept(run, url: url, name: "writer")
    }

    /// REC-016-S1: the finish fails → the completed fragments are kept.
    func testFinishFailureKeepsTheCompletedFragments() async throws {
        let url = temporaryURL("finish")
        defer { try? FileManager.default.removeItem(at: url) }
        let run = try await record("finish", url: url, fault: .finishFailure, frames: 45)
        XCTAssertEqual(run.appended, 45)
        try await assertKept(run, url: url, name: "finish")
    }

    /// REC-016-R3: a failure before any fragment completed keeps nothing (the file is deleted).
    func testEarlyWriterFailureKeepsNothing() async throws {
        let url = temporaryURL("early")
        defer { try? FileManager.default.removeItem(at: url) }
        let run = try await record("early", url: url, fault: .writerFailure(afterFrames: 3), frames: 5)
        guard case .failure(.writerFailed) = run.result else { return XCTFail("\(run.result)") }
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    /// REC-016-R9: out of storage still deletes the partial file (REC-015-R7).
    func testOutOfStorageStillDeletes() async throws {
        let url = temporaryURL("full")
        defer { try? FileManager.default.removeItem(at: url) }
        let run = try await record("full", url: url, fault: .diskFull(afterFrames: 20), frames: 25)
        XCTAssertEqual(run.result, .failure(.storageFull))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    /// REC-016-S2: a start failure after the writer existed leaves no file and no live writer.
    func testStartFailureLeavesNothing() throws {
        let (device, _) = try gpu()
        let url = temporaryURL("start")
        let writers = RecordingResourceLedger.liveWriters
        XCTAssertThrowsError(try MetalFrameRecorder(device: device, url: url, drawableWidth: 64, drawableHeight: 48,
                                                    settings: settings, realTime: false, fault: .startFailure))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(RecordingResourceLedger.liveWriters, writers)
    }

    /// REC-016-S5: a normal finish is an ordinary MP4 (no movie fragment box) that passes QA-008.
    func testNormalFinishIsAnOrdinaryMP4() async throws {
        let (device, queue) = try gpu()
        let url = temporaryURL("normal")
        defer { try? FileManager.default.removeItem(at: url) }
        let recorder = try MetalFrameRecorder(device: device, url: url, drawableWidth: 64, drawableHeight: 48,
                                              settings: settings, realTime: false)
        for i in 0..<24 { try offer(recorder, queue: queue, index: i) }   // 0.8 s: past one fragment
        let video = try (await recorder.finish()).get()
        XCTAssertNil(video.interruption)
        XCTAssertEqual(video.frameCount, 24)
        let boxes = try topLevelBoxes(url)
        XCTAssertFalse(boxes.contains("moof"), "\(boxes)")
        XCTAssertTrue(boxes.contains("moov"), "\(boxes)")
        let report = await RecordingValidator.validate(url, expectation: RecordingExpectation(durationSeconds: 0.8))
        XCTAssertTrue(report.passed, report.summary)
    }

    private func topLevelBoxes(_ url: URL) throws -> [String] {
        let data = try Data(contentsOf: url)
        var boxes: [String] = []
        var offset = 0
        while offset + 8 <= data.count {
            var size = data[offset..<offset + 4].reduce(UInt64(0)) { (a: UInt64, b: UInt8) -> UInt64 in a << 8 | UInt64(b) }
            let type = String(decoding: data[offset + 4..<offset + 8], as: UTF8.self)
            if size == 1, offset + 16 <= data.count {
                size = data[offset + 8..<offset + 16].reduce(UInt64(0)) { (a: UInt64, b: UInt8) -> UInt64 in a << 8 | UInt64(b) }
            }
            boxes.append(type)
            guard size >= 8 else { break }
            offset += Int(size)
        }
        return boxes
    }
}
#endif

// MARK: - Thermal guard (plain Swift)

import FrameRecording
import XCTest

final class RecordingThermalGuardTests: XCTestCase {
    /// REC-016-R8: Serious warns once per recording, Critical stops; Record is refused at Critical.
    func testWarnsOnceAtSeriousAndStopsAtCritical() {
        var guardState = RecordingThermalGuard()
        XCTAssertEqual(guardState.update(.nominal), .none)
        XCTAssertEqual(guardState.update(.fair), .none)
        XCTAssertEqual(guardState.update(.serious), .warn)
        XCTAssertEqual(guardState.update(.serious), .none, "once per recording")
        XCTAssertEqual(guardState.update(.fair), .none)
        XCTAssertEqual(guardState.update(.serious), .none)
        XCTAssertEqual(guardState.update(.critical), .stop)
        XCTAssertEqual(RecordingThermalGuard.refusalLevel, .critical)
        XCTAssertEqual(RecordingStopReason.thermal.notice, "Recording stopped because the device is too hot.")
        XCTAssertEqual(RecordingRefusal.thermal.notice, "The device is too hot to record. Try again when it cools down.")
        XCTAssertEqual(RecordingStopReason.writerFailed.notice,
                       "Recording stopped because of a write error. The part recorded before it was kept.")
    }

    /// REC-016-R2: the DEBUG argument's forms.
    func testFaultArgument() {
        XCTAssertEqual(RecordingWriterFault(argument: "append:10")?.kind, .appendFails)
        XCTAssertEqual(RecordingWriterFault(argument: "append:10")?.afterFrames, 10)
        XCTAssertEqual(RecordingWriterFault(argument: "writer:90")?.kind, .writerFails)
        XCTAssertEqual(RecordingWriterFault(argument: "finish")?.kind, .finishFails)
        XCTAssertEqual(RecordingWriterFault(argument: "start")?.kind, .startFails)
        XCTAssertEqual(RecordingWriterFault(argument: "diskFull:3")?.kind, .appendFails)
        XCTAssertNil(RecordingWriterFault(argument: "append"))
        XCTAssertNil(RecordingWriterFault(argument: "other:1"))
    }
}
