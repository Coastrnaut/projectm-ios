// TexturePoolAppTests.swift — PERF-004-T08 (S5; PERF-004-R5, R8): the app's compositor visuals share one
// texture pool per device, so switching Camera (stand-in camera) → Photo → Spectrum → Camera reuses
// pictures instead of creating them, and the memory warning frees retired ones. One offscreen frame per
// visual at 64 × 128 (small, fast). Needs a Metal device; skipped without one.
import CameraLayer
import Compositor
import Metal
import UIKit
import XCTest
@testable import projectM_iOS

@MainActor
final class TexturePoolAppTests: XCTestCase {
    private func frame(_ compositor: Compositor, queue: MTLCommandQueue, output: MTLTexture) throws {
        let commands = try XCTUnwrap(queue.makeCommandBuffer())
        XCTAssertTrue(compositor.composite(into: output, commandBuffer: commands, presentationTimeNanoseconds: 1_000_000_000,
                                           contentScale: 2, reduceFlashing: false, audio: .empty))
        commands.commit()
        commands.waitUntilCompleted()
    }

    func testSwitchingVisualsReusesTheSharedPoolsPictures() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw XCTSkip("No Metal device in this simulator")
        }
        let pool = SharedTexturePool.pool(for: device)
        XCTAssertTrue(SharedTexturePool.pool(for: device) === pool, "one pool per device")
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: 64, height: 128, mipmapped: false)
        d.usage = [.renderTarget]
        d.storageMode = .private
        let output = try XCTUnwrap(device.makeTexture(descriptor: d))
        SharedTexturePool.purgeAll()

        var liveAfterCycle: [Int] = []
        var missesAfterCycle: [Int] = []
        for _ in 0..<5 {
            var camera: CameraVisualHost? = try CameraVisualHost.make(device: device, reader: nil, barCount: .b32) { (device: MTLDevice) -> any CameraFrameProvider in
                StubCameraFrameProvider(device: device, scenario: .granted)
            }
            XCTAssertTrue(camera!.compositor.texturePool === pool, "the Camera visual uses the shared pool")
            try frame(camera!.compositor, queue: queue, output: output)
            camera = nil

            var photo: PhotoVisualHost? = try PhotoVisualHost.make(device: device, reader: nil, barCount: .b32)
            XCTAssertTrue(photo!.compositor.texturePool === pool, "the Photo visual uses the shared pool")
            try frame(photo!.compositor, queue: queue, output: output)
            photo = nil

            var spectrum: NativeSpectrumHost? = try NativeSpectrumHost.make(device: device, reader: nil, barCount: .b32)
            XCTAssertNotNil(spectrum, "the native spectrum draws without the compositor")
            spectrum = nil

            liveAfterCycle.append(pool.counters.liveTextures)
            missesAfterCycle.append(pool.counters.misses)
        }
        XCTAssertEqual(pool.counters.checkedOutTextures, 0, "released visuals returned every picture")
        XCTAssertEqual(Set(liveAfterCycle).count, 1, "live textures plateau after the first cycle: \(liveAfterCycle)")
        XCTAssertEqual(Set(missesAfterCycle).count, 1, "later cycles create no texture: \(missesAfterCycle)")
        XCTAssertGreaterThan(pool.counters.hits, 0)

        NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: UIApplication.shared)
        XCTAssertEqual(pool.counters.retiredTextures, 0, "the memory warning frees retired textures")
        XCTAssertGreaterThanOrEqual(pool.counters.purges, 2)
    }
}
