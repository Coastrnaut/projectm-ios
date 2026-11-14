// Task T073: the bundled starter presets (Apps/projectM-iOS/Resources/Presets). Every file has a
// complete LICENSES.md row (FR-047), there are at least 20, and a representative sample loads in the
// engine and renders on the iOS Simulator (the 1 s SC-007 check over every preset is an on-demand bench).
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

    /// Owner rule 7 (2026-11-14): CI's iOS 27 simulator took 146 s for every preset and failed the 1 s
    /// wall-clock limit (run 43578387762). The suite now loads and renders a representative sample with
    /// no timing assertion; SC-007's load time is device evidence (T079 sweeps). The full set with the
    /// 1 s check runs on demand: `RENDERING_FULL_PRESETS=1`.
    func testRepresentativeBundledPresetsLoadAndRender() async throws {
        let catalog = try PresetRepository(presetsFolder: Self.presetsFolder).load()
        try await loadAndRender(Self.sample(catalog.presets), timeLimit: nil)
    }

    func testEveryBundledPresetLoadsWithinOneSecondBench() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RENDERING_FULL_PRESETS"] == "1",
                          "bench: set RENDERING_FULL_PRESETS=1")
        let catalog = try PresetRepository(presetsFolder: Self.presetsFolder).load()
        try await loadAndRender(catalog.presets, timeLimit: 1.0)
    }

    /// The largest presets by file size (the slowest to compile) plus an even spread of the rest.
    private static func sample(_ presets: [Preset]) -> [Preset] {
        let count: Int = 6
        guard presets.count > count else { return presets }
        let bySize: [Preset] = presets.sorted { (a: Preset, b: Preset) -> Bool in
            fileSize(a) > fileSize(b)
        }
        var chosen: [Preset] = Array(bySize.prefix(2))
        let stride: Int = presets.count / (count - 2)
        var index: Int = 0
        while chosen.count < count && index < presets.count {
            let candidate: Preset = presets[index]
            if !chosen.contains(where: { (p: Preset) -> Bool in p.id == candidate.id }) { chosen.append(candidate) }
            index += max(stride, 1)
        }
        return chosen
    }

    private static func fileSize(_ preset: Preset) -> Int {
        let size = try? FileManager.default.attributesOfItem(atPath: preset.fileURL.path)[.size] as? Int
        return size ?? 0
    }

    private func loadAndRender(_ presets: [Preset], timeLimit: Double?) async throws {
        let renderer = try GLESRenderer.make()
        renderer.view.frame = CGRect(x: 0, y: 0, width: 96, height: 96)
        renderer.view.layoutIfNeeded()
        var slowest = (name: "", seconds: 0.0)
        var failures: [String] = []
        for preset in presets {
            let start = Date()
            do {
                try await renderer.setPreset(preset)
            } catch {
                failures.append("\(preset.name): \((error as NSError).localizedDescription)")
                continue
            }
            let seconds: Double = Date().timeIntervalSince(start)
            if seconds > slowest.seconds { slowest = (preset.name, seconds) }
            if let timeLimit { XCTAssertLessThan(seconds, timeLimit, "\(preset.name) took \(seconds) s to load (SC-007)") }
            for _ in 0..<3 { XCTAssertTrue(renderer.renderFrame()) }
        }
        XCTAssertEqual(failures, [], "presets that failed to load")
        print("BundledPresetsTests: \(presets.count) presets; slowest load \(slowest.name) \(String(format: "%.3f", slowest.seconds)) s")
    }
}
