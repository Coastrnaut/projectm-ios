// PaletteAppTests.swift — UIX-011-T06 (acceptance "Palette changes update linked layers and survive relaunch";
// UIX-011-S1, S2, R5 to R8, R10): through the real PaletteStore (a file in a temporary folder) and the real scene
// capture. Two spectrum layers link a user palette; one swatch edit changes both layers' resolved colours at once and
// the native visual's palette; a new store reading the file and the scene read back from its bytes resolve to the same
// colours. Deleting the palette falls back to Spectrum with the notice, announced once. CPU only.
import Foundation
import SceneFormat
import TextLayer
import VisualGenerators
import XCTest
@testable import projectM_iOS

@MainActor
final class PaletteAppTests: XCTestCase {
    private var folder: URL!
    private let teal = PaletteColor(red: 0x00, green: 0x80, blue: 0x80)

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("PaletteAppTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: folder)
    }

    /// A scene whose two spectrum layers link `id` (as the app writes a chosen palette).
    private func linkedScene(_ id: String) -> SceneDocument {
        var document = SceneDocument(id: UUID().uuidString, name: "Two layers",
                                     layers: [SceneLayer(instance: 1, content: .circularSpectrum),
                                              SceneLayer(instance: 2, content: .linearSpectrum)])
        SceneAutosaveCapture.linkPalette(id, in: &document)
        return document
    }

    private func colors(_ library: PaletteLibrary, layer: Int, in document: SceneDocument) -> [LinearColor] {
        PaletteCoordinator.resolvedColors(library.resolve(layer: layer, in: document).palette, count: 8)
    }

    func testAnEditUpdatesBothLinkedLayersAndSurvivesRelaunch() throws {
        let palettes = PaletteCoordinator(store: PaletteStore(directory: folder))
        var redraws = 0
        palettes.onChange = { redraws += 1 }
        let id = try XCTUnwrap(palettes.create())
        palettes.choose(id)
        let document = linkedScene(id)
        let before0 = colors(palettes.library, layer: 0, in: document)
        let before1 = colors(palettes.library, layer: 1, in: document)
        let drawnBefore = palettes.visualPalette(colorBlindSafe: false)
        XCTAssertEqual(before0, before1, "both layers draw the palette")

        redraws = 0
        palettes.setColor(id, at: 0, to: teal)
        XCTAssertEqual(redraws, 1, "the edit redraws the visual at once")
        let after0 = colors(palettes.library, layer: 0, in: document)
        let after1 = colors(palettes.library, layer: 1, in: document)
        XCTAssertNotEqual(after0, before0, "layer 1 changed")
        XCTAssertNotEqual(after1, before1, "layer 2 changed")
        XCTAssertEqual(after0, after1)
        XCTAssertEqual(after0[0], LinearColor.fromSRGB(red: 0x00, green: 0x80, blue: 0x80), "the new first colour")
        XCTAssertNotEqual(palettes.visualPalette(colorBlindSafe: false), drawnBefore, "the native visual's palette changed")
        XCTAssertEqual(palettes.visualPalette(colorBlindSafe: true), .colorBlindSafe, "ACC-003 wins")

        // Relaunch: a new store reads the file; the scene is read back from its saved bytes.
        let relaunched = PaletteCoordinator(store: PaletteStore(directory: folder))
        let reread = try SceneDocument.decode(document.encoded()).document
        relaunched.restore(SceneAutosaveCapture.paletteLink(in: reread))
        XCTAssertEqual(relaunched.library, palettes.library)
        XCTAssertEqual(colors(relaunched.library, layer: 0, in: reread), after0)
        XCTAssertEqual(colors(relaunched.library, layer: 1, in: reread), after1)
        XCTAssertEqual(relaunched.visualPalette(colorBlindSafe: false), palettes.visualPalette(colorBlindSafe: false))
        XCTAssertNil(relaunched.store.issue)
    }

    func testTheSceneCaptureWritesAndRestoresTheLink() {
        let id = "0000C011-0000-4000-8000-0000000000AA"
        let carry = SceneAutosaveCarry(id: UUID().uuidString, name: "Scene")
        var inputs = SceneInputs(visual: .circularSpectrum, bars: 64, orientation: .vertical, spacing: 0.2, glowEnabled: false,
                                 glowIntensity: 0.5, glowRadius: 0.02, glowThreshold: 0.7, text: TextOverlaySpec.default, photoID: nil, videoID: nil)
        inputs.palette = ScenePaletteChoice(id: id)
        let document = SceneAutosaveCapture.document(inputs, carry: carry, liveBindings: nil).document
        XCTAssertEqual(document.paletteID, id)
        XCTAssertEqual(document.layers.first?.paletteID, id, "the spectrum layer links it too")
        XCTAssertEqual(SceneAutosaveCapture.paletteLink(in: document), id)
        inputs.palette = nil
        XCTAssertNil(SceneAutosaveCapture.document(inputs, carry: carry, liveBindings: nil).document.paletteID, "untracked: nothing written")
    }

    func testADeletedPaletteFallsBackWithANoticeAnnouncedOnce() throws {
        let palettes = PaletteCoordinator(store: PaletteStore(directory: folder))
        var spoken: [String] = []
        palettes.announce = { spoken.append($0) }
        let id = try XCTUnwrap(palettes.create())
        palettes.choose(id)
        palettes.delete(id)
        XCTAssertEqual(palettes.sceneLink, id, "the link is kept")
        XCTAssertEqual(palettes.missingNotice, PaletteCoordinator.missingNoticeText)
        XCTAssertEqual(palettes.visualPalette(colorBlindSafe: false), .spectrum)
        _ = palettes.create()
        XCTAssertEqual(spoken, [PaletteCoordinator.missingNoticeText], "announced once")
        palettes.choose(ColorPalette.spectrumID)
        XCTAssertNil(palettes.sceneLink)
        XCTAssertNil(palettes.missingNotice)
    }

    func testANewerFileIsNeverOverwritten() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let newer = Data(#"{"format":"projectm-ios.palettes","palettes":[],"version":2}"#.utf8)
        try newer.write(to: folder.appendingPathComponent(PaletteStore.fileName))
        let palettes = PaletteCoordinator(store: PaletteStore(directory: folder))
        XCTAssertTrue(palettes.store.isReadOnly)
        XCTAssertNil(palettes.create())
        XCTAssertEqual(palettes.lastError, PaletteEditError.readOnly.message)
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent(PaletteStore.fileName)), newer)
    }
}
