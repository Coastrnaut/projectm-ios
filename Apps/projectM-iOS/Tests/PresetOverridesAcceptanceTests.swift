// PresetOverridesAcceptanceTests.swift — PRE-016-T10, T11: the roadmap acceptance in the app
// ("Overrides apply on load and reset restores original values"; PRE-016-S1 to S3). A real Included
// preset from the app bundle gets three overrides through PresetOverridesCoordinator; loading it hands
// the renderer text that carries the three values while the bundled file stays byte-identical; the
// preset on screen is reloaded by the change; a relaunch (new store and loader over the same folder)
// still applies them; Reset to Original loads the original file again (no overlay data), and the
// values read are the original ones. Refusals change nothing. Runs in about a second.
import AudioCore
import PresetLibrary
import Rendering
import UIKit
import XCTest
@testable import projectM_iOS

@MainActor
final class PresetOverridesAcceptanceTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var directory: URL!
    private var announcements: [String] = []

    override func setUp() async throws {
        suite = "PresetOverridesAcceptanceTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        announcements = []
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }

    final class RecordingRenderer: VisualizerRenderer {
        let view = UIView()
        var reduceFlashing = false
        let supportsReduceFlashing = false
        var metrics = RenderMetrics.zero
        var presentedFrameCount = 0
        var loaded: [Preset] = []
        func attach(pcm: any NormalizedPCMReader) {}
        func setTextureSearchPaths(_ paths: [URL]) {}
        func pause() {}
        func resume() {}
        func setPreset(_ preset: Preset) async throws { loaded.append(preset) }
    }

    private struct Rig {
        let renderer: RecordingRenderer
        let loader: RendererPresetLoader
        let presets: PresetCoordinator
        let overrides: PresetOverridesCoordinator
    }

    /// A "launch": a new store, loader and coordinators over the same folder.
    private func launch(_ library: PresetLibrary) -> Rig {
        let renderer = RecordingRenderer()
        let loader = RendererPresetLoader()
        loader.renderer = renderer
        loader.library = library
        let store = PresetOverrideStore(directory: directory)
        loader.overrides = store
        let presets = PresetCoordinator(store: FavoritesStore(defaults: defaults),
                                        settings: AppSettings(defaults: defaults, systemReduceMotion: false), loader: loader,
                                        collections: PresetCollectionStore(directory: directory))
        presets.attach(library)
        presets.announceLibrary = { [weak self] (text: String) in self?.announcements.append(text) }
        let overrides = PresetOverridesCoordinator(store: store, presets: presets) { [loader] (preset: IndexedPreset) async throws -> Data in
            try await loader.originalData(for: preset)
        }
        presets.overrides = overrides
        return Rig(renderer: renderer, loader: loader, presets: presets, overrides: overrides)
    }

    private func includedPreset(_ library: PresetLibrary) throws -> (IndexedPreset, URL) {
        let preset = try XCTUnwrap(library.presets.first { $0.isIncluded && $0.source != PresetLibrary.userSource })
        let url = try XCTUnwrap(Bundle.main.resourceURL).appendingPathComponent(preset.path)
        return (preset, url)
    }

    func testOverridesApplyOnLoadSurviveARelaunchAndResetRestoresTheOriginal() async throws {
        let library = try await PresetLibrary.load(from: .main)
        let (preset, fileURL) = try includedPreset(library)
        let originalBytes = try Data(contentsOf: fileURL)
        let original = PresetTextOverlay.originalValues(originalBytes)

        let rig = launch(library)
        await rig.presets.select(preset)   // on screen, so a change reloads it
        XCTAssertNil(rig.renderer.loaded.last?.data, "an Included preset without overrides loads from its file")
        let wanted: [PresetOverrideParameter: Double] = [.zoom: original[.zoom] == 1.05 ? 1.1 : 1.05,
                                                         .decay: original[.decay] == 0.95 ? 0.96 : 0.95,
                                                         .waveRed: original[.waveRed] == 0.25 ? 0.3 : 0.25]
        for (parameter, value) in wanted.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            let stored = await rig.overrides.set(value, for: parameter, preset: preset)
            XCTAssertEqual(stored, value)
        }
        XCTAssertEqual(rig.renderer.loaded.count, 4, "the first selection plus one reload per change")
        let adjusted = try XCTUnwrap(rig.renderer.loaded.last?.data, "overrides load as data")
        let read = PresetTextOverlay.originalValues(adjusted)
        for (parameter, value) in wanted { XCTAssertEqual(read[parameter], value, parameter.label) }
        for parameter in PresetOverrideParameter.allCases where wanted[parameter] == nil {
            XCTAssertEqual(read[parameter], original[parameter], "untouched: \(parameter.label)")
        }
        XCTAssertEqual(try Data(contentsOf: fileURL), originalBytes, "the bundled file is byte-identical")
        XCTAssertTrue(announcements.contains("Zoom set to \(PresetTextOverlay.valueText(wanted[.zoom]!)) for \(preset.name)."), "\(announcements)")

        // Relaunch: the overrides still apply.
        let relaunched = launch(library)
        try await relaunched.loader.load(preset)
        let afterRelaunch = PresetTextOverlay.originalValues(try XCTUnwrap(relaunched.renderer.loaded.last?.data))
        for (parameter, value) in wanted { XCTAssertEqual(afterRelaunch[parameter], value, parameter.label) }

        // Reset to Original: the original bytes, exactly.
        await relaunched.presets.select(preset)
        let before = relaunched.renderer.loaded.count
        await relaunched.overrides.resetAll(preset)
        XCTAssertEqual(relaunched.renderer.loaded.count, before + 1, "the preset on screen reloads")
        let reset = try XCTUnwrap(relaunched.renderer.loaded.last)
        XCTAssertNil(reset.data, "no overlay: the engine reads the file itself")
        XCTAssertEqual(try Data(contentsOf: reset.fileURL), originalBytes)
        XCTAssertTrue(relaunched.overrides.overrides(for: preset).isEmpty)
        XCTAssertTrue(PresetOverrideStore(directory: directory).map.isEmpty, "the reset is saved")
        XCTAssertEqual(announcements.last, "\(preset.name) restored to its original values.")
        let originals = await relaunched.overrides.originals(for: preset)
        XCTAssertEqual(originals, original)
    }

    func testRefusalsAndRowResetsChangeOnlyWhatTheySay() async throws {
        let library = try await PresetLibrary.load(from: .main)
        let (preset, _) = try includedPreset(library)
        let rig = launch(library)
        let clamped = await rig.overrides.set(9, for: .zoom, preset: preset)
        XCTAssertEqual(clamped, 1.2, "clamped to the safe range")
        let refused = await rig.overrides.set(.nan, for: .warp, preset: preset)
        XCTAssertNil(refused)
        XCTAssertEqual(rig.overrides.message, PresetOverrideError.invalidValue.message)
        await rig.overrides.set(0.3, for: .rotation, preset: preset)
        XCTAssertEqual(rig.overrides.overrides(for: preset), ["zoom": 1.2, "rot": 0.2])
        await rig.overrides.reset(.zoom, preset: preset)
        XCTAssertEqual(rig.overrides.overrides(for: preset), ["rot": 0.2])
        XCTAssertEqual(announcements.last, "Zoom restored for \(preset.name).")
        rig.overrides.prune(preset.id)
        XCTAssertFalse(rig.overrides.hasOverrides(preset))
    }
}
