// PERF-009 native pipeline archive (contracts/warm-cache.md W6; PERF-009-S1, S3): a cold launch misses and stores,
// a warm launch serves pipelines from the archive (made with `.failOnBinaryArchiveMiss`, so a hit is proof), any
// key change (shader source, OS, GPU family) keeps the old archive closed and deletes it, a changed shader misses
// in Metal even against the old file, and a damaged file is rebuilt. Skipped where Metal or archives are missing.
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

    private static let source = """
    #include <metal_stdlib>
    using namespace metal;
    vertex float4 perf009_vertex(uint i [[vertex_id]]) { return float4(float(i & 1), float(i >> 1), 0, 1); }
    fragment float4 perf009_fragment() { return float4(0.25, 0.5, 0.75, 1); }
    """

    override func setUpWithError() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal device") }
        guard (try? device.makeBinaryArchive(descriptor: MTLBinaryArchiveDescriptor())) != nil else {
            throw XCTSkip("binary archives unsupported here")
        }
        self.device = device
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("perf009-pipe-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        if let folder { try? FileManager.default.removeItem(at: folder) }
    }

    private var store: WarmCacheStore { WarmCacheStore(directory: folder) }

    private func descriptor(source: String = source, format: MTLPixelFormat = .bgra8Unorm) throws -> MTLRenderPipelineDescriptor {
        let library = try device.makeLibrary(source: source, options: nil)
        let d = MTLRenderPipelineDescriptor()
        d.vertexFunction = library.makeFunction(name: "perf009_vertex")
        d.fragmentFunction = library.makeFunction(name: "perf009_fragment")
        d.colorAttachments[0].pixelFormat = format
        return d
    }

    private func open(sources: [String] = [source], identity: WarmStartIdentity? = nil) -> NativePipelineArchive {
        NativePipelineArchive.open(device: device, store: store, identity: identity ?? self.identity, sources: sources)
    }

    /// Cold: miss, pipeline made and queued, written back. Warm: served from the archive (hit counted).
    func testWarmLaunchServesPipelinesFromTheArchive() throws {
        let cold = open()
        XCTAssertEqual(cold.outcome, .miss)
        _ = try cold.makeRenderPipeline(try descriptor())
        _ = try cold.makeRenderPipeline(try descriptor(format: .rgba16Float))
        XCTAssertEqual(cold.misses, 2)
        XCTAssertEqual(cold.pendingCount, 2)
        XCTAssertEqual(try cold.writeBack(), 2)
        XCTAssertEqual(try cold.writeBack(), 0)

        let warm = open()
        XCTAssertEqual(warm.outcome, .hit)
        _ = try warm.makeRenderPipeline(try descriptor())
        _ = try warm.makeRenderPipeline(try descriptor(format: .rgba16Float))
        XCTAssertEqual(warm.hits, 2)
        XCTAssertEqual(warm.misses, 0)
        XCTAssertEqual(warm.pendingCount, 0)
    }

    /// S1, S3: a changed shader source, OS or GPU family is stale: the old archive is deleted, never opened.
    func testKeyChangesNeverOpenTheOldArchive() throws {
        let edited = Self.source.replacingOccurrences(of: "0.25, 0.5", with: "0.5, 0.25")
        var newOS = identity
        newOS.osVersion = "27.3"
        let cases: [(WarmCacheKey.Field, () -> NativePipelineArchive)] = [
            (.contentHash, { self.open(sources: [edited]) }),
            (.osVersion, { self.open(identity: newOS) }),
        ]
        for (field, reopen) in cases {
            let cold = open()
            _ = try cold.makeRenderPipeline(try descriptor())
            try cold.writeBack()
            let changed = reopen()
            XCTAssertEqual(changed.outcome, .stale(field))
            XCTAssertFalse(FileManager.default.fileExists(atPath: store.payloadURL(NativePipelineArchive.entryName).path))
            _ = try changed.makeRenderPipeline(try descriptor(source: edited))
            XCTAssertEqual(changed.hits, 0)
            XCTAssertEqual(changed.misses, 1)
        }
        // GPU family is part of the key (another device's archive is stale).
        var otherGPU = NativePipelineArchive.key(device: device, identity: identity, sources: [Self.source])
        otherGPU.gpuFamily = "Other GPU/apple1"
        XCTAssertEqual(NativePipelineArchive.key(device: device, identity: identity, sources: [Self.source]).firstMismatch(otherGPU), .gpuFamily)
        XCTAssertTrue(NativePipelineArchive.gpuFamily(of: device).hasPrefix(device.name + "/"))
    }

    /// D4: even against the old archive file, Metal never serves a pipeline whose shader changed.
    func testMetalMissesAChangedShaderInAnOldArchive() throws {
        let cold = open()
        _ = try cold.makeRenderPipeline(try descriptor())
        try cold.writeBack()
        let fileDescriptor = MTLBinaryArchiveDescriptor()
        fileDescriptor.url = store.payloadURL(NativePipelineArchive.entryName)
        let archive = try device.makeBinaryArchive(descriptor: fileDescriptor)
        let same = try descriptor()
        same.binaryArchives = [archive]
        XCTAssertNoThrow(try device.makeRenderPipelineState(descriptor: same, options: [.failOnBinaryArchiveMiss]))
        let changed = try descriptor(source: Self.source.replacingOccurrences(of: "0.75", with: "0.80"))
        changed.binaryArchives = [archive]
        XCTAssertThrowsError(try device.makeRenderPipelineState(descriptor: changed, options: [.failOnBinaryArchiveMiss]))
    }

    /// S1: a damaged archive file (checksum) is deleted and rebuilt.
    func testDamagedArchiveIsRebuilt() throws {
        let cold = open()
        _ = try cold.makeRenderPipeline(try descriptor())
        try cold.writeBack()
        let url = store.payloadURL(NativePipelineArchive.entryName)
        var bytes = try Data(contentsOf: url)
        bytes[bytes.count / 2] ^= 0xFF
        try bytes.write(to: url)
        let damaged = open()
        XCTAssertEqual(damaged.outcome, .damaged(.checksum))
        _ = try damaged.makeRenderPipeline(try descriptor())
        XCTAssertEqual(try damaged.writeBack(), 1)
        XCTAssertEqual(open().outcome, .hit)
    }

    /// The shared slot routes FlatShapePass-style creation; without it pipelines are made as before.
    func testSharedSlotIsUsedOnlyForItsDevice() throws {
        XCTAssertNil(NativePipelineArchive.shared)
        _ = try NativePipelineArchive.makeRenderPipelineState(device: device, descriptor: try descriptor())
        let archive = open()
        NativePipelineArchive.shared = archive
        defer { NativePipelineArchive.shared = nil }
        _ = try NativePipelineArchive.makeRenderPipelineState(device: device, descriptor: try descriptor())
        XCTAssertEqual(archive.misses, 1)
        XCTAssertFalse(NativeShaderSources.visualGenerators.isEmpty)
    }
}
#endif
