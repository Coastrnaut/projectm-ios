// SHD-012-T10: the Noise editor's fixture preview store — the default binding (Warp amount ← kick, full range), two
// plays give the same run digest and trajectory, a seed change clears the run and gives another trajectory, a settings
// change (invalidate) stops the loop, Reduce Motion does not auto-play, and without the GPU only the trajectory runs.
import AuthoringPreview
import ParameterGraph
import ProceduralMaterials
import XCTest
@testable import projectM_iOS

@MainActor
final class FixturePreviewStoreTests: XCTestCase {
    private let definition: MaterialDefinition = ProceduralMaterialCatalog.definition(.noiseFlow)

    func testDefaultBindingIsWarpFollowingTheKick() {
        let store = FixturePreviewStore(useGPU: false)
        XCTAssertEqual(store.target, definition.parameterID("warpAmount"))
        XCTAssertEqual(store.bindings, [AudioFeatureBinding(source: .kick, target: definition.parameterID("warpAmount"),
                                                            outputStart: 0, outputEnd: 4)])
        XCTAssertTrue(store.targets.allSatisfy { (d: ParameterDescriptor) -> Bool in d.modulation.isModulatable })
        XCTAssertFalse(store.targets.contains { (d: ParameterDescriptor) -> Bool in d.id == self.definition.parameterID("seed") })
        store.target = nil
        XCTAssertEqual(store.bindings, [])
        XCTAssertEqual(store.summary, "Not rendered")
    }

    func testTwoPlaysGiveTheSameRunAndSettingsChangesClearIt() async {
        let store = FixturePreviewStore()
        let values = MaterialParameterValues(definition)
        await store.play(values: values)
        XCTAssertEqual(store.phase, .ready)
        let first: AuthoringPreviewTrajectory? = store.trajectory
        let digest: String? = store.runDigest
        XCTAssertEqual(first?.frameCount, 120)
        XCTAssertTrue(store.summary.hasPrefix("120 frames · Warp amount 0.00…4.00"), store.summary)
        if digest != nil {   // Metal is available on the simulator and the Mac
            XCTAssertEqual(store.frames.count, 120)
            XCTAssertTrue(store.isPlaying)
            XCTAssertTrue(store.summary.hasSuffix("run " + String(digest!.prefix(8))), store.summary)
        }
        store.stop()
        await store.play(values: values)
        XCTAssertEqual(store.trajectory, first, "same inputs, same trajectory")
        XCTAssertEqual(store.runDigest, digest, "same inputs, same frames")
        XCTAssertEqual(store.runCount, 2)

        store.seed = 2
        XCTAssertEqual(store.phase, .idle, "a seed change clears the run")
        XCTAssertFalse(store.isPlaying)
        await store.play(values: values, autoPlay: false)
        XCTAssertFalse(store.isPlaying, "Reduce Motion: no auto-play")
        XCTAssertNotEqual(store.trajectory, first, "another fixture seed")
        store.invalidate()
        XCTAssertEqual(store.summary, "Not rendered")
        XCTAssertTrue(store.frames.isEmpty)
    }

    func testWithoutTheGPUOnlyTheTrajectoryRuns() async {
        let store = FixturePreviewStore(useGPU: false)
        store.seed = 500
        XCTAssertEqual(store.seed, 99, "clamped to 1…99")
        await store.play(values: MaterialParameterValues(definition))
        XCTAssertEqual(store.phase, .ready)
        XCTAssertNil(store.runDigest)
        XCTAssertTrue(store.frames.isEmpty)
        XCTAssertFalse(store.isPlaying)
        XCTAssertFalse(store.summary.contains("run "), store.summary)
    }
}
