// GoldenPaths.swift — where the scenes, goldens and diff artifacts live (QA-002 research D2). Found
// from this file's path, so record mode writes into the source tree from the host and the simulator.
import Foundation
import GoldenImages

enum GoldenPaths {
    /// `Packages/RenderGoldens/` from this file's path; on a device (QA-011, DeviceTests.yml), where the source tree
    /// does not exist, the test bundle's copy of `Scenes`, `Goldens` and `GeneratorGoldens` instead.
    static let packageRoot: URL = {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // RenderGoldensTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // RenderGoldens
        if FileManager.default.fileExists(atPath: source.appendingPathComponent("Scenes").path) { return source }
        if let bundled = Bundle(for: BundleMarker.self).resourceURL,
           FileManager.default.fileExists(atPath: bundled.appendingPathComponent("Scenes").path) {
            return bundled
        }
        return source
    }()

    private final class BundleMarker {}

    /// True when the scenes and goldens come from the test bundle (read-only; diffs go to a temporary folder).
    static var isBundled: Bool { packageRoot.path.contains(".xctest") }

    static var scenes: URL { packageRoot.appendingPathComponent("Scenes", isDirectory: true) }
    static var goldens: URL { packageRoot.appendingPathComponent("Goldens", isDirectory: true) }

    static func goldens(_ platform: GoldenPlatformClass) -> URL {
        goldens.appendingPathComponent(platform.rawValue, isDirectory: true)
    }

    /// `GOLDEN_DIFF_DIR`, else `Packages/RenderGoldens/.build/golden-diffs/` (gitignored).
    static var diffRoot: URL {
        if let custom = ProcessInfo.processInfo.environment["GOLDEN_DIFF_DIR"], !custom.isEmpty {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        if isBundled { return FileManager.default.temporaryDirectory.appendingPathComponent("golden-diffs", isDirectory: true) }
        return packageRoot.appendingPathComponent(".build/golden-diffs", isDirectory: true)
    }

    static func sceneBytes(_ run: GoldenSceneRun) throws -> [UInt8] {
        [UInt8](try Data(contentsOf: scenes.appendingPathComponent(run.fileName)))
    }
}
