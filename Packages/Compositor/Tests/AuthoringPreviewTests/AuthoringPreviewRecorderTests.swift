// AuthoringPreviewRecorderTests.swift — SHD-012-T06 (R4, R5; S1, S3; contract P3): on the host GPU, two recordings of
// one request give identical frame checksum sequences and trajectories; the layer's own motion follows the trajectory;
// a changed setting changes the frames. Exact equality is promised per GPU class only (SHD-006's rule).
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import AuthoringPreview
import Metal
import ParameterGraph
import ProceduralMaterials
import XCTest

final class AuthoringPreviewRecorderTests: XCTestCase {
    private let definition: MaterialDefinition = ProceduralMaterialCatalog.definition(.noiseFlow)

    private func request(values: MaterialParameterValues? = nil) -> AuthoringPreviewRequest {
        let binding = AudioFeatureBinding(source: .kick, target: definition.parameterID("warpAmount"), outputStart: 0, outputEnd: 4)
        return AuthoringPreviewRequest(values: values ?? MaterialParameterValues(definition), bindings: [binding],
                                       fixture: AuthoringPreviewFixture(seed: 1, seconds: 1))
    }

    private func recorder() throws -> AuthoringPreviewRecorder {
        guard let r = AuthoringPreviewRecorder.makeDefault() else { throw XCTSkip("no Metal device") }
        return r
    }

    func testTwoRecordingsGiveTheSameTrajectoryAndFrameSequence() throws {
        let r = try recorder()
        let a = try r.record(request(), width: 64, height: 64)
        let b = try r.record(request(), width: 64, height: 64)
        XCTAssertEqual(a.checksums.count, 30)
        XCTAssertEqual(a.checksums, b.checksums, "same GPU (\(r.device.name)): identical frames")
        XCTAssertEqual(a.runDigest, b.runDigest)
        XCTAssertEqual(a.trajectory, b.trajectory)
        XCTAssertEqual(a.trajectory, try AuthoringPreviewSequencer.record(request()), "the GPU run records the sequencer's trajectory")
        XCTAssertGreaterThan(Set(a.checksums).count, 20, "the frames move")
        XCTAssertEqual(a.checksums[0].count, 64)
    }

    func testLayerMotionFollowsTheTrajectoryAndImagesAreKept() throws {
        let r = try recorder()
        let a = try r.record(request(), width: 32, height: 32, keepImages: true)
        XCTAssertEqual(a.layerMotion.map(\.phase), a.trajectory.phase)
        XCTAssertEqual(a.layerMotion.map(\.audioLevel), a.trajectory.audioLevel)
        XCTAssertEqual(a.images.count, 30)
        XCTAssertEqual(a.images.first?.width, 32)
    }

    func testChangedSettingChangesTheFrames() throws {
        let r = try recorder()
        var values = MaterialParameterValues(definition)
        try values.set(.integer(7), for: definition.parameterID("seed"))
        let a = try r.record(request(), width: 32, height: 32)
        let b = try r.record(request(values: values), width: 32, height: 32)
        XCTAssertEqual(a.trajectory, b.trajectory, "the seed is not bound: same trajectory")
        XCTAssertNotEqual(a.checksums, b.checksums, "another noise seed draws other frames")
        XCTAssertNotEqual(a.runDigest, b.runDigest)
    }
}
#endif
