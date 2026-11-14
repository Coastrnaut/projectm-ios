// PERF-009 native pipeline archive (contracts/warm-cache.md W6; PERF-009-S1, S3): a cold launch misses and stores,
// a warm launch serves the native spectra's pipelines from the archive (made with `.failOnBinaryArchiveMiss`, so a
// hit is proof), any key change (shader source, OS, GPU family) keeps the old archive closed and deletes it, and a
// damaged file is rebuilt. Pipelines come from the real `FlatShapePass` (no test-only shader source: SHD-011 keeps
// Metal source and binary archives in reviewed files). Skipped where Metal or archives are missing.
// Metal's own guard (a changed function misses even against an old archive file) was measured by the research probe
// (PERF-009-D4).
#if canImport(Metal) && !VISUAL_NO_METAL
import Foundation
import LocalPortability
import Metal
import XCTest
@testable import VisualGenerators

final class NativePipelineArchiveTests: XCTestCase {
    private var folder: URL!
    private var device: MTLDevice!
    private let identity = WarmStartIdentity(appVersion: "1.1", build: "2", osVersion: "27.2")
    private var sources: [String] { NativeShaderSources.visualGenerators }

    override func setUpWithError() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal device") }
        self.device = device
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("perf009-pipe-\(UUID().uuidString)", isDirectory: true)
        if open().outcome == .unsupported { throw XCTSkip("binary archives unsupported here") }
    }

    override func tearDownWithError() throws {
        NativePipelineArchive.shared = nil
        if let folder { try? FileManager.default.removeItem(at: folder) }
    }

    private var store: WarmCacheStore { WarmCacheStore(directory: folder) }

    private func open(sources: [String]? = nil, identity: WarmStartIdentity? = nil) -> NativePipelineArchive {
        NativePipelineArchive.open(device: device, store: store, identity: identity ?? self.identity, sources: sources ?? self.sources)
    }

    /// The native spectra's two pipelines (both supported formats) through `archive`.
    private func makeSpectrumPipelines(_ archive: NativePipelineArchive) throws {
        NativePipelineArchive.shared = archive
        defer { NativePipelineArchive.shared = nil }
        for format in FlatShapePass.supportedPixelFormats {
            _ = try FlatShapePass(device: device, pixelFormat: format, maximumVertexCount: 6, label: "PERF-009 test")
        }
    }

    /// Cold: miss, pipelines made and queued, written back. Warm: served from the archive (hits counted).
    func testWarmLaunchServesPipelinesFromTheArchive() throws {
        let cold = open()
        XCTAssertEqual(cold.outcome, .miss)
        try makeSpectrumPipelines(cold)
        XCTAssertEqual(cold.misses, 2)
        XCTAssertEqual(cold.pendingCount, 2)
        XCTAssertEqual(try cold.writeBack(), 2)
        XCTAssertEqual(try cold.writeBack(), 0)

        let warm = open()
        XCTAssertEqual(warm.outcome, .hit)
        try makeSpectrumPipelines(warm)
        XCTAssertEqual(warm.hits, 2)
        XCTAssertEqual(warm.misses, 0)
        XCTAssertEqual(warm.pendingCount, 0)
    }

    /// S1, S3: a changed shader source or OS is stale: the old archive is deleted, never opened, and pipelines
    /// compile from source again.
    func testKeyChangesNeverOpenTheOldArchive() throws {
        let edited = sources.map { (text: String) -> String in text + "\n// edited\n" }
        var newOS = identity
        newOS.osVersion = "27.3"
        let cases: [(WarmCacheKey.Field, () -> NativePipelineArchive)] = [
            (.contentHash, { self.open(sources: edited) }),
            (.osVersion, { self.open(identity: newOS) }),
        ]
        for (field, reopen) in cases {
            let cold = open()
            try makeSpectrumPipelines(cold)
            try cold.writeBack()
            let changed = reopen()
            XCTAssertEqual(changed.outcome, .stale(field))
            XCTAssertFalse(FileManager.default.fileExists(atPath: store.payloadURL(NativePipelineArchive.entryName).path))
            try makeSpectrumPipelines(changed)
            XCTAssertEqual(changed.hits, 0)
            XCTAssertEqual(changed.misses, 2)
        }
        // The GPU family is part of the key: another device's archive is stale.
        var otherGPU = NativePipelineArchive.key(device: device, identity: identity, sources: sources)
        otherGPU.gpuFamily = "Other GPU/apple1"
        XCTAssertEqual(NativePipelineArchive.key(device: device, identity: identity, sources: sources).firstMismatch(otherGPU), .gpuFamily)
        XCTAssertTrue(NativePipelineArchive.gpuFamily(of: device).hasPrefix(device.name + "/"))
    }

    /// S1: a damaged archive file (checksum) is deleted and rebuilt.
    func testDamagedArchiveIsRebuilt() throws {
        let cold = open()
        try makeSpectrumPipelines(cold)
        try cold.writeBack()
        let url = store.payloadURL(NativePipelineArchive.entryName)
        var bytes = try Data(contentsOf: url)
        bytes[bytes.count / 2] ^= 0xFF
        try bytes.write(to: url)
        let damaged = open()
        XCTAssertEqual(damaged.outcome, .damaged(.checksum))
        try makeSpectrumPipelines(damaged)
        XCTAssertEqual(try damaged.writeBack(), 2)
        XCTAssertEqual(open().outcome, .hit)
    }

    /// Without a shared archive pipelines are made exactly as before (nothing counted, nothing queued).
    func testNoSharedArchiveMeansPlainCreation() throws {
        let unused = open()
        XCTAssertNil(NativePipelineArchive.shared)
        _ = try FlatShapePass(device: device, pixelFormat: .rgba16Float, maximumVertexCount: 6, label: "PERF-009 plain")
        XCTAssertEqual(unused.misses + unused.hits + unused.pendingCount, 0)
    }
}
#endif
