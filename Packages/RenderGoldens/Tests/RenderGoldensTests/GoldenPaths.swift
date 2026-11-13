// GoldenPaths.swift — where the scenes, goldens and diff artifacts live (QA-002 research D2). Found
// from this file's path, so record mode writes into the source tree from the host and the simulator.
import Foundation
import GoldenImages

enum GoldenPaths {
    /// `Packages/RenderGoldens/`.
    static let packageRoot: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // RenderGoldensTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // RenderGoldens

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
        return packageRoot.appendingPathComponent(".build/golden-diffs", isDirectory: true)
    }

    static func sceneBytes(_ run: GoldenSceneRun) throws -> [UInt8] {
        [UInt8](try Data(contentsOf: scenes.appendingPathComponent(run.fileName)))
    }
}
