// AuthoringPreviewTrajectoryTests.swift — SHD-012-T04 (R1, R2, R3, R5; S1, S2, S3; contract P1, P2): the preview's
// parameter trajectory is a pure function of the request. Plain Swift: runs in the Linux shape too.
import AuthoringPreview
import ParameterGraph
import ProceduralMaterials
import XCTest

final class AuthoringPreviewTrajectoryTests: XCTestCase {
    private let definition: MaterialDefinition = ProceduralMaterialCatalog.definition(.noiseFlow)

    private var warp: ParameterID { definition.parameterID("warpAmount") }
    private var speed: ParameterID { definition.parameterID("speed") }

    private func binding(_ source: AudioFeatureSource = .kick, target: ParameterID? = nil) -> AudioFeatureBinding {
        AudioFeatureBinding(source: source, target: target ?? warp, outputStart: 0, outputEnd: 4)
    }

    /// 1 s at 30 fps (30 frames) keeps each test short; one test runs the full default fixture.
    private func request(seed: UInt64 = 1, bindings: [AudioFeatureBinding]? = nil, frames: Int? = nil) -> AuthoringPreviewRequest {
        AuthoringPreviewRequest(values: MaterialParameterValues(definition), bindings: bindings ?? [binding()],
                                fixture: AuthoringPreviewFixture(seed: seed, seconds: 1), frameCount: frames)
    }

    func testDefaultFixtureHas120FramesAndTwoRunsAreIdentical() throws {
        let full = AuthoringPreviewRequest(values: MaterialParameterValues(definition), bindings: [binding()])
        XCTAssertEqual(full.fixture.frameCount, 120)
        let a = try AuthoringPreviewSequencer.record(full)
        let b = try AuthoringPreviewSequencer.record(full)
        XCTAssertEqual(a.frameCount, 120)
        XCTAssertEqual(a, b, "same request, same trajectory (exact Doubles)")
        let values: [Double] = try XCTUnwrap(a.values(for: warp))
        XCTAssertEqual(values.count, 120)
        XCTAssertGreaterThan(values.max()! - values.min()!, 0.5, "the kick moves warp: \(values.min()!)…\(values.max()!)")
        XCTAssertEqual(a.presentationTimeNanoseconds.first, 1_000_000_000)
        XCTAssertTrue(a.phase.last! > 0, "the material drifts")
    }

    func testSteppingFrameByFrameOrInChunksEqualsOnePass() throws {
        let r = request()
        let single = try AuthoringPreviewSequencer.record(r)

        let perFrame = try AuthoringPreviewSequencer(request: r)
        var stepped = AuthoringPreviewTrajectory(parameters: r.boundParameters)
        while let f = perFrame.step() { stepped.append(f) }

        let chunked = try AuthoringPreviewSequencer(request: r)
        var chunks = AuthoringPreviewTrajectory(parameters: r.boundParameters)
        while true {
            let part: [AuthoringPreviewFrame] = chunked.run(frames: 7)
            if part.isEmpty { break }
            part.forEach { (f: AuthoringPreviewFrame) -> Void in chunks.append(f) }
        }
        XCTAssertEqual(single.frameCount, 30)
        XCTAssertEqual(stepped, single)
        XCTAssertEqual(chunks, single)
    }

    func testChangedSeedOrBindingChangesTheTrajectory() throws {
        let base = try AuthoringPreviewSequencer.record(request())
        let otherSeed = try AuthoringPreviewSequencer.record(request(seed: 2))
        // The seed changes the fixture's noise hits, not its kick: the music level (and so the phase) differs, and a
        // band-driven binding differs; a kick-driven one follows the same kicks.
        XCTAssertNotEqual(otherSeed, base, "another fixture seed")
        XCTAssertNotEqual(otherSeed.audioLevel, base.audioLevel)
        let bandSeed1 = try AuthoringPreviewSequencer.record(request(bindings: [binding(.bandMean)]))
        let bandSeed2 = try AuthoringPreviewSequencer.record(request(seed: 2, bindings: [binding(.bandMean)]))
        XCTAssertNotEqual(bandSeed2.values(for: warp), bandSeed1.values(for: warp), "a band-driven binding follows the seed")
        let otherSource = try AuthoringPreviewSequencer.record(request(bindings: [binding(.bandMean)]))
        XCTAssertNotEqual(otherSource.values(for: warp), base.values(for: warp), "another source")
        let speedBinding = AudioFeatureBinding(source: .kick, target: speed, outputStart: 0, outputEnd: 1)
        let otherTarget = try AuthoringPreviewSequencer.record(request(bindings: [speedBinding]))
        XCTAssertEqual(otherTarget.parameters, [speed])
        XCTAssertNotEqual(otherTarget.phase, base.phase, "a modulated speed moves the phase differently")
    }

    func testRefusedBindingThrowsBeforeAnything() {
        let octaves = AudioFeatureBinding(source: .kick, target: definition.parameterID("octaves"), outputStart: 1, outputEnd: 8)
        XCTAssertThrowsError(try AuthoringPreviewSequencer(request: request(bindings: [octaves]))) { (error: Error) -> Void in
            guard case AuthoringPreviewError.binding = error else { return XCTFail("\(error)") }
        }
    }

    func testNoBindingKeepsManualValuesAndStillRecordsMotion() throws {
        let t = try AuthoringPreviewSequencer.record(request(bindings: []))
        XCTAssertEqual(t.parameters, [])
        XCTAssertEqual(t.frameCount, 30)
        XCTAssertTrue(t.audioLevel.contains { (v: Double) -> Bool in v > 0 }, "the fixture music reaches the material")
        let s = try AuthoringPreviewSequencer(request: request(bindings: []))
        let frames: [AuthoringPreviewFrame] = s.run(frames: 100)
        XCTAssertTrue(frames.allSatisfy { (f: AuthoringPreviewFrame) -> Bool in f.values == MaterialParameterValues(self.definition) })
    }

    func testZeroFramesAndFramesBeyondTheFixture() throws {
        XCTAssertEqual(try AuthoringPreviewSequencer.record(request(frames: 0)).frameCount, 0)
        // 1 s of fixture, 60 frames: the second second is silence, so the music level falls back toward 0.
        let t = try AuthoringPreviewSequencer.record(request(frames: 60))
        XCTAssertEqual(t.frameCount, 60)
        XCTAssertLessThan(t.audioLevel[59], t.audioLevel[29])
    }
}
