// VectorPathEditorTests.swift — SHD-008-T15 (R5, R6, R8, R9): the app side of the path editor. "Path" in the mask
// picker gives the default path; a committed path replaces it keeping placement, feather and invert; the live
// compositor settings carry it; the change is one history step; it is saved as a "path" mask (the scene bytes are
// ScenePathMaskTests'). The emitter's path persists through AppSettings, and a damaged stored path reads as the default.
import Compositor
import SceneFormat
import VisualGenerators
import XCTest
@testable import projectM_iOS

@MainActor
final class VectorPathEditorTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() async throws {
        suite = "VectorPathEditorTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }

    private static func arrow() throws -> VectorPath {
        try VectorPath([VectorPoint(x: 0.1, y: 0.1), VectorPoint(x: 0.9, y: 0.5), VectorPoint(x: 0.1, y: 0.9),
                        VectorPoint(x: 0.5, y: 0.5)])
    }

    func testMaskPathIsChosenEditedMappedAndSaved() throws {
        let start: SceneComposite = LayerCompositeEdit.settingMask("path", on: SceneComposite())
        XCTAssertEqual(LayerMaskPathEdit.path(of: start), .default, "Path starts as the default diamond")
        XCTAssertEqual(LayerCompositeEdit.maskTitle(start), "Path (4 points)")
        var feathered: SceneComposite = LayerCompositeEdit.setting(.maskFeather, to: 0.05, on: start)
        feathered = LayerCompositeEdit.setting(.maskInverted, to: 1, on: feathered)
        let arrow = try Self.arrow()
        let edited: SceneComposite = LayerMaskPathEdit.settingPath(arrow, on: feathered)
        let mask = try XCTUnwrap(LayerCompositeEdit.knownMask(edited))
        XCTAssertEqual(mask.shape, .path(arrow))
        XCTAssertEqual(mask.feather, 0.05)
        XCTAssertTrue(mask.inverted, "invert kept")
        XCTAssertEqual(LayerCompositeMapping.settings(edited).mask, mask, "the compositor receives the path mask")
        XCTAssertEqual(LayerHistoryEdit.changedParameters(from: feathered, to: edited), [.maskShape], "one history step")
        XCTAssertEqual(edited.mask?.shape, "path", "saved as a path mask (ScenePathMaskTests proves the bytes)")
        XCTAssertEqual(LayerCompositeEdit.settingMask("ellipse", on: edited).mask?.shape, "ellipse", "the picker can leave Path")
    }

    func testEmitterPathPersistsAndADamagedPathReadsAsTheDefault() throws {
        let settings = AppSettings(defaults: defaults, systemReduceMotion: false)
        var choice = ParticleEmitterChoice(enabled: true)
        choice.settings.shape = .path
        choice.settings.path = try Self.arrow()
        settings.particleEmitter = choice
        let reloaded = AppSettings(defaults: defaults, systemReduceMotion: false)
        XCTAssertEqual(reloaded.particleEmitter.settings.shape, .path)
        XCTAssertEqual(reloaded.particleEmitter.settings.path.points, try Self.arrow().points, "every point exactly")
        let bowTie = #"{"enabled":true,"settings":{"shape":"path","path":{"points":[{"x":0.1,"y":0.1},{"x":0.9,"y":0.9},{"x":0.9,"y":0.1},{"x":0.1,"y":0.9}]}}}"#
        defaults.set(Data(bowTie.utf8), forKey: AppSettings.particleEmitterKey)
        let damaged = AppSettings(defaults: defaults, systemReduceMotion: false).particleEmitter
        XCTAssertTrue(damaged.enabled)
        XCTAssertEqual(damaged.settings.shape, .path)
        XCTAssertEqual(damaged.settings.path, .default)
    }
}
