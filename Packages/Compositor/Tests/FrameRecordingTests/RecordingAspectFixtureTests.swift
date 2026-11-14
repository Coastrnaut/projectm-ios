// RecordingAspectFixtureTests.swift — REC-014-T06, the row's acceptance with the real writer ("Export dimensions
// match preset"): two tiny clips (Square and Landscape, 10 frames at 30 fps, Draft/H.264, offline writer) from a
// 128×256 portrait drawable whose top and bottom quarters are red and middle half green. The file reads back with
// exactly the planned size, and its first decoded frame is green away from the edges: the writer cropped the
// centre to fill (ADR-0060), with no bars and no red band. GPU test; skipped without Metal. Host results are not
// device evidence (REC-014-T15).
#if canImport(Metal) && canImport(AVFoundation) && canImport(CoreGraphics) && !COMPOSITOR_NO_METAL
import AVFoundation
import CoreGraphics
@testable import FrameRecording
import Foundation
import Metal
import XCTest

final class RecordingAspectFixtureTests: XCTestCase {
    static let width = 128
    static let height = 256

    /// BGRA rows: red, green for the middle half, red.
    private static func bands(device: MTLDevice) -> MTLBuffer? {
        let length = width * height * 4
        guard let buffer = device.makeBuffer(length: length, options: .storageModeShared) else { return nil }
        let bytes = buffer.contents().bindMemory(to: UInt8.self, capacity: length)
        for row in 0..<height {
            let green = row >= height / 4 && row < height * 3 / 4
            for column in 0..<width {
                let i = (row * width + column) * 4
                bytes[i] = 0
                bytes[i + 1] = green ? 255 : 0
                bytes[i + 2] = green ? 0 : 255
                bytes[i + 3] = 255
            }
        }
        return buffer
    }

    private func record(_ aspect: RecordingAspect) async throws -> (RecordingProfilePlan, RecordedVideoInfo, URL) {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
              let pixels = Self.bands(device: device) else {
            throw XCTSkip("No Metal device (CI simulator or Linux); RecordingAspectTests cover the rules.")
        }
        let caps = StubCapabilities()
        let plan = try XCTUnwrap(RecordingQualityCatalog.availability(of: .draft, drawableWidth: Self.width, drawableHeight: Self.height,
                                                                      aspect: aspect, capabilities: caps).plan)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("REC-014-\(UUID().uuidString).mp4")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let recorder = try MetalFrameRecorder(device: device, url: url, drawableWidth: Self.width, drawableHeight: Self.height,
                                              settings: plan.settings, realTime: false)
        XCTAssertEqual(recorder.geometry, plan.geometry)
        for k in 0..<10 {
            let commands = try XCTUnwrap(queue.makeCommandBuffer())
            let outcome = recorder.recordFrame(presentationNanoseconds: 1_000_000_000 + UInt64(k) * 33_333_333,
                                               drawableWidth: Self.width, drawableHeight: Self.height,
                                               commandBuffer: commands) { (texture: MTLTexture) -> Bool in
                guard let blit = commands.makeBlitCommandEncoder() else { return false }
                blit.copy(from: pixels, sourceOffset: 0, sourceBytesPerRow: Self.width * 4,
                          sourceBytesPerImage: Self.width * Self.height * 4,
                          sourceSize: MTLSize(width: Self.width, height: Self.height, depth: 1), to: texture,
                          destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
                blit.endEncoding()
                return true
            }
            XCTAssertEqual(outcome, .submitted, "frame \(k)")
            commands.commit()
            recorder.waitForPendingFrames()
        }
        let video = try (await recorder.finish()).get()
        XCTAssertEqual([video.width, video.height], [plan.geometry.outputWidth, plan.geometry.outputHeight])
        let info = try await XCTUnwrapAsync(await RecordedVideoInspector.inspect(url))
        return (plan, info, url)
    }

    /// The first frame's RGBA pixels.
    private func firstFrame(_ url: URL) async throws -> (pixels: [UInt8], width: Int, height: Int) {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let image: CGImage = try await generator.image(at: .zero).image
        let w = image.width, h = image.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) -> Bool in
            guard let context = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        XCTAssertTrue(drawn)
        return (pixels, w, h)
    }

    /// Green (not red, not black) at points 15% in from each corner and at the centre.
    private func assertCentreIsGreen(_ frame: (pixels: [UInt8], width: Int, height: Int), _ name: String) {
        let xs = [frame.width * 15 / 100, frame.width / 2, frame.width * 85 / 100]
        let ys = [frame.height * 15 / 100, frame.height / 2, frame.height * 85 / 100]
        for x in xs {
            for y in ys {
                let i = (y * frame.width + x) * 4
                let r = Int(frame.pixels[i]), g = Int(frame.pixels[i + 1])
                XCTAssertGreaterThan(g, 150, "\(name) (\(x), \(y)) green: r=\(r) g=\(g)")
                XCTAssertLessThan(r, 80, "\(name) (\(x), \(y)) no red band: r=\(r) g=\(g)")
            }
        }
    }

    func testPresetFilesHaveThePlannedSizeAndTheCentreOfThePicture() async throws {
        for (aspect, expected) in [(RecordingAspect.square, [128, 128]), (.landscape, [128, 72])] {
            let (plan, info, url) = try await record(aspect)
            XCTAssertEqual([plan.geometry.outputWidth, plan.geometry.outputHeight], expected, "\(aspect) plan")
            XCTAssertEqual([info.width, info.height], expected, "\(aspect) file")
            XCTAssertEqual(info.frameCount, 10, "\(aspect)")
            let frame = try await firstFrame(url)
            XCTAssertEqual([frame.width, frame.height], expected, "\(aspect) decoded")
            assertCentreIsGreen(frame, "\(aspect)")
            print("REC-014 fixture \(aspect): \(info.summary)")
        }
    }
}
#endif
