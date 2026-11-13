// MemoryPressureAppTests.swift — PERF-006-T10, T13 (PERF-006-S1, S4, S5; R6, R8, R11, R12, R13).
//
// The warning is injected by posting `UIApplication.didReceiveMemoryWarningNotification`, the
// notification UIKit posts for a real warning (simulated pressure, real path: the app's
// MemoryPressureCoordinator.shared observer runs every registered step, including the host app's own).
// The Photo visual renders offscreen at 64 × 128 and 96 × 160 (small, fast). Needs a Metal device;
// skipped without one. No wall clock: escalation uses a fake clock.
import Compositor
import ImageLayer
import Metal
import PresentationLifecycle
import UIKit
import XCTest
@testable import projectM_iOS

@MainActor
final class MemoryPressureAppTests: XCTestCase {
    private func output(_ device: MTLDevice, width: Int, height: Int) throws -> MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: width, height: height, mipmapped: false)
        d.usage = [.renderTarget]
        d.storageMode = .private
        return try XCTUnwrap(device.makeTexture(descriptor: d))
    }

    private func frame(_ compositor: Compositor, queue: MTLCommandQueue, output: MTLTexture) throws {
        let commands = try XCTUnwrap(queue.makeCommandBuffer())
        XCTAssertTrue(compositor.composite(into: output, commandBuffer: commands, presentationTimeNanoseconds: 1_000_000_000,
                                           contentScale: 2, reduceFlashing: false, audio: .empty))
        commands.commit()
        commands.waitUntilCompleted()
    }

    private func photoFile() throws -> URL {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 24)).image { (context: UIGraphicsImageRendererContext) in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 32, height: 24))
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("perf006-\(UUID().uuidString).png")
        try XCTUnwrap(image.pngData()).write(to: url)
        return url
    }

    private func storedSettings() -> [String: String] {
        var values: [String: String] = [:]
        for key in AppSettings.allKeys { values[key] = UserDefaults.standard.object(forKey: key).map { "\($0)" } ?? "unset" }
        return values
    }

    /// S1, S4: an injected warning frees every retired picture (reported exactly), the shown Photo keeps
    /// rendering, and 60 further frames at a steady size create no picture.
    func testAnInjectedWarningFreesRetiredPicturesAndThePhotoKeepsRendering() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw XCTSkip("No Metal device in this simulator")
        }
        let pool = SharedTexturePool.pool(for: device)
        let file = try photoFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let host = try PhotoVisualHost.make(device: device, reader: nil, barCount: .b32)
        host.content = .file(file)
        host.photo.waitUntilLoaded()
        let small = try output(device, width: 64, height: 128), large = try output(device, width: 96, height: 160)
        try frame(host.compositor, queue: queue, output: small)
        try frame(host.compositor, queue: queue, output: large)   // the resize retires the small pictures
        let retired = SharedTexturePool.retiredBytes
        XCTAssertGreaterThan(retired, 0, "the old size's pictures are pooled")
        let settingsBefore = storedSettings()
        let recoveriesBefore = MemoryPressureCoordinator.shared.recovery.recoveries

        NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: UIApplication.shared)

        XCTAssertEqual(MemoryPressureCoordinator.shared.recovery.recoveries, recoveriesBefore + 1, "one recovery per warning")
        let report = try XCTUnwrap(MemoryPressureCoordinator.shared.lastReport)
        let poolStep = try XCTUnwrap(report.steps.first { $0.name == "shared texture pool" })
        XCTAssertEqual(poolStep.release.bytes, retired, "the step reports what the pool held")
        XCTAssertFalse(poolStep.release.bytesEstimated)
        XCTAssertGreaterThanOrEqual(report.freedBytes, retired)
        XCTAssertEqual(SharedTexturePool.retiredBytes, 0, "S1: no retired picture remains")
        XCTAssertGreaterThan(pool.counters.checkedOutTextures, 0, "pictures in use are untouched")
        XCTAssertEqual(storedSettings(), settingsBefore, "R6: no stored setting changed")
        print("PERF-006 evidence: pool retired \(retired) B, report \(report.summary)")

        let shown = host.framesShown
        try frame(host.compositor, queue: queue, output: large)
        XCTAssertGreaterThan(host.framesShown, shown, "the next frame renders the photo")
        let misses = pool.counters.misses, live = pool.counters.liveTextures
        for _ in 0..<60 { try frame(host.compositor, queue: queue, output: large) }
        XCTAssertEqual(pool.counters.misses, misses, "S4: no picture created at a steady size")
        XCTAssertEqual(pool.counters.liveTextures, live)
        XCTAssertEqual(host.framesShown, shown + 61)
    }

    /// R11: the archive step drops the decompressed chunk, reports its size, and the next read works.
    func testThePresetArchiveCacheIsDroppedAndRebuiltOnDemand() throws {
        let presetText = Data(String(repeating: "per_frame_1=wave_r = 0.5;\n", count: 40).utf8)
        let compressed = try (presetText as NSData).compressed(using: .zlib) as Data
        var file = Data("PMPA".utf8)
        func u32(_ v: Int) { withUnsafeBytes(of: UInt32(v).littleEndian) { file.append(contentsOf: $0) } }
        func u64(_ v: Int) { withUnsafeBytes(of: UInt64(v).littleEndian) { file.append(contentsOf: $0) } }
        u32(1); u32(1); u32(0); u32(1)                                      // version, presets, reserved, chunks
        let dataOffset = 20 + 16 + 12
        u64(dataOffset); u32(compressed.count); u32(presetText.count)      // the chunk
        u32(0); u32(0); u32(presetText.count)                               // the preset's entry
        file.append(compressed)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("perf006-\(UUID().uuidString).bin")
        try file.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let archive = try PresetArchive(url: url, packIds: ["pack/a"])
        XCTAssertEqual(archive.dropCache(), 0, "nothing cached yet")
        XCTAssertEqual(try archive.contents(of: "pack/a"), presetText)
        XCTAssertEqual(archive.cachedBytes, presetText.count)
        XCTAssertEqual(archive.dropCache(), presetText.count)
        XCTAssertEqual(archive.dropCache(), 0, "idempotent")
        XCTAssertEqual(try archive.contents(of: "pack/a"), presetText, "rebuilt on demand")

        let loader = RendererPresetLoader()
        XCTAssertEqual(loader.memoryPressureName, "preset archive cache")
        XCTAssertEqual(loader.releaseForMemoryPressure(.warning), .none, "no archive opened: nothing to free")
    }

    /// R12: only a spectrum that is not the chosen visual is idle.
    func testOnlyASpectrumThatIsNotChosenIsReleased() {
        for choice in VisualChoice.allCases {
            XCTAssertEqual(AppCoordinator.releasesIdleNativeSpectrum(choice: choice, hostExists: true), !choice.isNative, "\(choice)")
            XCTAssertFalse(AppCoordinator.releasesIdleNativeSpectrum(choice: choice, hostExists: false), "no host: nothing")
        }
    }

    /// T13 (S5): the app coordinator escalates on a repeat, schedules one restore for the cool-down's
    /// end and restores once (fake clock; the restore is called directly, not waited for).
    func testTheCoordinatorSchedulesOneRestoreAndRestoresOnce() {
        final class FakeBackgroundWork: MemoryPressureResponder {
            let memoryPressureName = "fake background work"
            let memoryPressureTier = MemoryPressureTier.optional
            var reclaimableBytes: Int { 0 }
            var releases = 0, restores = 0
            func releaseForMemoryPressure(_ level: MemoryPressureLevel) -> MemoryPressureRelease { releases += 1; return .none }
            func restoreAfterMemoryPressure() { restores += 1 }
        }
        var now = 1_000.0
        let coordinator = MemoryPressureCoordinator(recovery: MemoryPressureRecovery(repeatWindowSeconds: 30, coolDownSeconds: 60),
                                                    observeSystemWarnings: false, clock: { () -> Double in now })
        let work = FakeBackgroundWork()
        coordinator.register(work)
        XCTAssertEqual(coordinator.handle(.warning)?.escalated, false)
        XCTAssertNil(coordinator.scheduledRestoreAt)
        now += 10
        XCTAssertEqual(coordinator.handle(.warning)?.escalated, true)
        XCTAssertEqual(work.releases, 1)
        XCTAssertEqual(coordinator.scheduledRestoreAt, 1_070)
        now += 20
        coordinator.handle(.warning)   // extends the cool-down
        XCTAssertEqual(coordinator.scheduledRestoreAt, 1_090)
        now = 1_080
        XCTAssertEqual(coordinator.restoreIfDue(), [], "not before the end")
        XCTAssertEqual(coordinator.scheduledRestoreAt, 1_090)
        now = 1_090
        XCTAssertEqual(coordinator.restoreIfDue(), ["fake background work"])
        XCTAssertEqual(coordinator.restoreIfDue(), [])
        XCTAssertEqual(work.restores, 1)
        XCTAssertNil(coordinator.scheduledRestoreAt, "nothing pending after the restore")
    }
}
