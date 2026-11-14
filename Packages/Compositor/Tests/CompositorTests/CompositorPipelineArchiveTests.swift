// PERF-009 (contracts/warm-cache.md W6; PERF-009-S3): the compositor's render pipelines go through the shared
// warm-start pipeline archive. A first compositor misses and queues; after write-back a second launch's compositor
// is served from the archive (hits counted with `.failOnBinaryArchiveMiss`). Skipped without Metal archives.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Foundation
import LocalPortability
import Metal
import VisualGenerators
import XCTest
@testable import Compositor

final class CompositorPipelineArchiveTests: XCTestCase {
    func testCompositorPipelinesAreServedFromTheArchiveOnTheNextLaunch() throws {
        let gpu = try GPURig()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("perf009-cmp-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        defer { NativePipelineArchive.shared = nil }
        let store = WarmCacheStore(directory: folder)
        let identity = WarmStartIdentity(appVersion: "1.1", build: "2", osVersion: "27.2")
        let sources: [String] = CompositorShaderSources.archived

        let cold = NativePipelineArchive.open(device: gpu.device, store: store, identity: identity, sources: sources)
        if cold.outcome == .unsupported { throw XCTSkip("binary archives unsupported here") }
        NativePipelineArchive.shared = cold
        _ = try Compositor(device: gpu.device)
        XCTAssertEqual(cold.outcome, .miss)
        XCTAssertGreaterThanOrEqual(cold.misses, 4)
        XCTAssertEqual(cold.hits, 0)
        XCTAssertEqual(try cold.writeBack(), cold.misses)

        let warm = NativePipelineArchive.open(device: gpu.device, store: store, identity: identity, sources: sources)
        NativePipelineArchive.shared = warm
        _ = try Compositor(device: gpu.device)
        XCTAssertEqual(warm.outcome, .hit)
        XCTAssertEqual(warm.misses, 0)
        XCTAssertEqual(warm.hits, cold.misses)
    }
}
#endif
