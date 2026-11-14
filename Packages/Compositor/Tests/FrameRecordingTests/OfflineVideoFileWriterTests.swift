// OfflineVideoFileWriterTests.swift — REC-013-T07: the offline export's writer (research REC-013-D5). Frames from CPU
// BGRA bytes at exact slots with interleaved audio; the file reads back with every frame and an audio track; cancel
// leaves no file. Tiny sizes; no wall clock asserted.
#if canImport(AVFoundation)
@testable import FrameRecording
import Foundation
import XCTest

final class OfflineVideoFileWriterTests: XCTestCase {
    private func url() -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("REC013-\(UUID().uuidString).mp4")
        addTeardownBlock { () -> Void in try? FileManager.default.removeItem(at: u) }
        return u
    }

    func testEveryFrameAndTheAudioAreWritten() async throws {
        let target = url()
        let writer = try OfflineVideoFileWriter(url: target, width: 32, height: 18, fps: 30, audio: true)
        let count = 32 * 4 * 18
        let pixels = UnsafeMutablePointer<UInt8>.allocate(capacity: count)
        defer { pixels.deallocate() }
        for n in 0..<15 {
            for i in stride(from: 0, to: count, by: 4) {
                pixels[i] = UInt8(n * 16); pixels[i + 1] = 40; pixels[i + 2] = 200; pixels[i + 3] = 255
            }
            let ok: Bool = await writer.appendFrame(bgra: UnsafeRawPointer(pixels), bytesPerRow: 32 * 4)
            XCTAssertTrue(ok, "frame \(n)")
            let audioOK = await writer.appendAudio([Float](repeating: 0.1, count: 1_470 * 2), startSample: Int64(n * 1_470))
            XCTAssertTrue(audioOK, "audio \(n)")
        }
        XCTAssertEqual(writer.framesWritten, 15)
        if case let .failure(f) = await writer.finish() { XCTFail("\(f)") }
        let inspected: RecordedVideoInfo? = await RecordedVideoInspector.inspect(target)
        let info = try XCTUnwrap(inspected)
        XCTAssertEqual(info.frameCount, 15)
        XCTAssertEqual(info.presentationTicks, (0..<15).map { (k: Int) -> Int64 in Int64(k) * 20 })
        XCTAssertEqual(info.audioTrackCount, 1)
        XCTAssertEqual(info.durationSeconds, 0.5, accuracy: 0.03)
    }

    func testCancelDeletesTheFileAndOddSizesAreRefused() async throws {
        let target = url()
        let writer = try OfflineVideoFileWriter(url: target, width: 32, height: 18, fps: 60, audio: false)
        let pixels = UnsafeMutablePointer<UInt8>.allocate(capacity: 32 * 4 * 18)
        pixels.initialize(repeating: 128, count: 32 * 4 * 18)
        defer { pixels.deallocate() }
        let ok: Bool = await writer.appendFrame(bgra: UnsafeRawPointer(pixels), bytesPerRow: 32 * 4)
        XCTAssertTrue(ok)
        await writer.cancel()
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
        XCTAssertThrowsError(try OfflineVideoFileWriter(url: url(), width: 33, height: 18, fps: 30, audio: false))
    }
}
#endif
