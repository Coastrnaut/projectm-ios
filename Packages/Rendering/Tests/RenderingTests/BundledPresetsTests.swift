// Task T073: the bundled starter presets (Apps/projectM-iOS/Resources/Presets). Every file has a
// complete LICENSES.md row (FR-047), there are at least 20, and each one loads in the engine within
// 1 s (SC-007) and renders on the iOS Simulator.
import XCTest
import ProjectMBridge
@testable import Rendering

@MainActor
final class BundledPresetsTests: XCTestCase {
    private static let presetsFolder = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Apps/projectM-iOS/Resources/Presets")

    func testEveryBundledPresetIsLicensed() throws {
        let catalog = try PresetRepository(presetsFolder: Self.presetsFolder).load()
        XCTAssertEqual(catalog.excluded, [], "every preset file needs a complete LICENSES.md row")
        XCTAssertGreaterThanOrEqual(catalog.presets.count, 20)
    }

    func testEveryBundledPresetLoadsWithinOneSecondAndRenders() async throws {
        let catalog = try PresetRepository(presetsFolder: Self.presetsFolder).load()
        let renderer = try GLESRenderer.make()
        renderer.view.frame = CGRect(x: 0, y: 0, width: 96, height: 96)
        renderer.view.layoutIfNeeded()
        var slowest = (name: "", seconds: 0.0)
        var failures: [String] = []
        for preset in catalog.presets {
            let start = Date()
            do {
                try await renderer.setPreset(preset)
            } catch {
                failures.append("\(preset.name): \((error as NSError).localizedDescription)")
                continue
            }
            let seconds = Date().timeIntervalSince(start)
            if seconds > slowest.seconds { slowest = (preset.name, seconds) }
            XCTAssertLessThan(seconds, 1.0, "\(preset.name) took \(seconds) s to load (SC-007)")
            for _ in 0..<3 { XCTAssertTrue(renderer.renderFrame()) }
        }
        XCTAssertEqual(failures, [], "presets that failed to load")
        print("BundledPresetsTests: \(catalog.presets.count) presets; slowest load \(slowest.name) \(String(format: "%.3f", slowest.seconds)) s")
    }
}
