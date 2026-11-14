// CMP-012-T05, T06 (US1; CMP-012-S1, S5, R2, R8): solo and mute never reach the scene document. A scene
// with four layers (one in a switched-off group) is loaded into a live stack; an overlay solos and mutes;
// the encoded document, every saved opacity and the group's `enabled` flag are byte-identical before,
// during and after; capture is unchanged; an undo record of the state during the solo is suppressed.
// The acceptance itself runs through the real compositor where Metal exists: solo one layer and only it
// is drawn, with the saved document byte-identical before, during and after. The CPU part runs on Linux.
import Compositor
import ParameterGraph
@testable import SceneFormat
import XCTest
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Metal
#endif

final class SceneSoloMuteTests: XCTestCase {
    /// #1 camera, #2 circular spectrum at opacity 0.5, #3 linear spectrum, #4 material in switched-off group 5.
    private func scene() -> SceneDocument {
        SceneDocument(id: SceneFixtures.sceneID, name: "Overlay check",
                      layers: [SceneLayer(instance: 1, content: .camera),
                               SceneLayer(instance: 2, content: .circularSpectrum, composite: SceneComposite(opacity: 0.5)),
                               SceneLayer(instance: 3, content: .linearSpectrum),
                               SceneLayer(instance: 4, content: .material(id: "material.plasma"))],
                      groups: [SceneGroup(id: 5, name: "Hidden", enabled: false, children: [.layer(4)])])
    }

    private func savedFlags(_ document: SceneDocument) -> [String] {
        document.layers.map { (l: SceneLayer) -> String in "\(l.instance):\(l.composite.opacity)" }
            + document.groups.map { (g: SceneGroup) -> String in "group\(g.id):\(g.enabled)" }
    }

    private func id(_ raw: UInt64) -> LayerInstanceID { LayerInstanceID(rawValue: raw) }

    func testSoloAndMuteNeverChangeTheDocumentCaptureOrUndoHistory() throws {
        let registry = try SceneFixtures.registry()
        let document = scene()
        let bytes = document.encoded()
        let state = try document.liveState(registry: registry).state
        let flags = savedFlags(document)
        var history = SceneHistory(current: SceneHistoryState(document))

        var overlay = LayerSoloMute()
        overlay.setSolo(true, layer: id(2))
        overlay.setMute(true, layer: id(3))
        overlay.setSolo(true, group: LayerGroupID(rawValue: 5))
        XCTAssertEqual(overlay.visibleLayers(in: state.stack), [id(2)], "the overlay is in effect")

        // During: the stack, capture and encoding cannot see the overlay.
        let during = try SceneDocument(capturing: state, id: document.id, name: document.name)
        XCTAssertEqual(during.encoded(), bytes, "capture → encode during the solo: byte-identical")
        XCTAssertEqual(savedFlags(during), flags, "saved opacities and enabled flags unchanged")
        XCTAssertEqual(history.record(SceneHistoryState(during), label: "Solo"), .unchanged, "no undo step (CMP-012-S5)")
        XCTAssertFalse(history.canUndo)
        XCTAssertFalse(String(decoding: bytes, as: UTF8.self).lowercased().contains("solo"))
        XCTAssertFalse(String(decoding: bytes, as: UTF8.self).lowercased().contains("mute"))

        // After: cleared, still identical.
        overlay.clear()
        let after = try SceneDocument(capturing: state, id: document.id, name: document.name)
        XCTAssertEqual(after.encoded(), bytes)
        XCTAssertEqual(savedFlags(after), flags)
        XCTAssertEqual(history.record(SceneHistoryState(after), label: "Unsolo"), .unchanged)
    }

    #if canImport(Metal) && !COMPOSITOR_NO_METAL
    /// Clears its picture to one premultiplied colour every frame and counts its preparations.
    private final class Flat: LayerSource {
        let layerName: String
        let fallback = LayerFallback.transparent
        let color: MTLClearColor
        private(set) var preparations = 0

        init(_ name: String, _ color: MTLClearColor) {
            layerName = name
            self.color = color
        }

        func prepare(picture: LayerPictureDescriptor, device: MTLDevice) throws(LayerSourceError) { preparations += 1 }

        func render(into picture: MTLTexture, commandBuffer: MTLCommandBuffer, frame: LayerFrameContext,
                    audio: LayerAudioContext) throws(LayerSourceError) {
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = picture
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor = color
            commandBuffer.makeRenderCommandEncoder(descriptor: pass)?.endEncoding()
        }
    }

    /// The row's acceptance: "Solo isolates selected layer without changing saved enable flags."
    func testSoloIsolatesTheSelectedLayerWithoutChangingTheSavedScene() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw XCTSkip("No Metal device (CI simulator or Linux); the CPU test covers the document.")
        }
        let registry = try SceneFixtures.registry()
        let document = scene()
        let bytes = document.encoded()
        let flags = savedFlags(document)
        let state = try document.liveState(registry: registry).state
        let colors: [UInt64: MTLClearColor] = [1: MTLClearColor(red: 1, green: 0, blue: 0, alpha: 1),
                                               2: MTLClearColor(red: 0, green: 1, blue: 0, alpha: 1),
                                               3: MTLClearColor(red: 0, green: 0, blue: 1, alpha: 1),
                                               4: MTLClearColor(red: 1, green: 1, blue: 1, alpha: 1)]
        var layers: [UInt64: Flat] = [:]
        let compositor = try Compositor(device: device)
        try compositor.apply(state.stack) { (entry: LayerStackEntry) throws(LayerSourceError) -> any LayerSource in
            guard let color = colors[entry.id.rawValue] else { throw .notReady }
            let layer = Flat("cmp012.\(entry.id.rawValue)", color)
            layers[entry.id.rawValue] = layer
            return layer
        }
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: 32, height: 16, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .private
        let output = try XCTUnwrap(device.makeTexture(descriptor: d))
        var time: UInt64 = 0
        func frame() throws -> [Float] {
            let commands = try XCTUnwrap(queue.makeCommandBuffer())
            XCTAssertTrue(compositor.composite(into: output, commandBuffer: commands, presentationTimeNanoseconds: time, contentScale: 2,
                                               reduceFlashing: false, audio: .empty))
            time += 16_666_667
            let rowBytes = 32 * 8
            let buffer = try XCTUnwrap(device.makeBuffer(length: rowBytes * 16, options: .storageModeShared))
            let blit = try XCTUnwrap(commands.makeBlitCommandEncoder())
            blit.copy(from: output, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                      sourceSize: MTLSize(width: 32, height: 16, depth: 1), to: buffer, destinationOffset: 0,
                      destinationBytesPerRow: rowBytes, destinationBytesPerImage: rowBytes * 16)
            blit.endEncoding()
            commands.commit()
            commands.waitUntilCompleted()
            XCTAssertNil(commands.error)
            let halves = buffer.contents().bindMemory(to: UInt16.self, capacity: 32 * 16 * 4)
            return (0..<(32 * 16 * 4)).map { (k: Int) -> Float in Float(Float16(bitPattern: halves[k])) }
        }
        func uniform(_ pixels: [Float]) -> [Float]? {
            let first = Array(pixels[0..<4])
            for p in stride(from: 0, to: pixels.count, by: 4) where Array(pixels[p..<(p + 4)]) != first { return nil }
            return first
        }
        _ = try frame()
        let before = try frame()
        XCTAssertEqual(uniform(before), [0, 0, 1, 1], "blue (#3) on top; #4's group is switched off")
        let preparations = layers.values.map(\.preparations).reduce(0, +)

        var overlay = LayerSoloMute()
        overlay.setSolo(true, layer: id(2))
        compositor.setSoloMute(overlay)
        let soloed = try frame()
        XCTAssertEqual(uniform(soloed), [0, 0.5, 0, 0.5], "only #2, at its saved opacity 0.5, over transparent")
        XCTAssertEqual(compositor.lastFlashGain, 1, accuracy: 1e-6)
        XCTAssertEqual(compositor.soloMuteHiddenLayers, 2, "#1 and #3 left out (#4 is hidden by its switched-off group)")
        let during = try SceneDocument(capturing: state, id: document.id, name: document.name)
        XCTAssertEqual(during.encoded(), bytes, "the saved scene is byte-identical during the solo")
        XCTAssertEqual(savedFlags(during), flags, "saved opacities and enabled flags unchanged")
        XCTAssertEqual(compositor.appliedStack, state.stack)

        // Soloing a layer of the switched-off group shows nothing of it: solo never overrides a saved flag.
        overlay.setSolo(true, layer: id(4))
        compositor.setSoloMute(overlay)
        XCTAssertEqual(uniform(try frame()), [0, 0.5, 0, 0.5])

        compositor.setSoloMute(LayerSoloMute())
        let after = try frame()
        XCTAssertEqual(after, before, "clearing the solo restores the previous frame bit for bit")
        XCTAssertEqual(try SceneDocument(capturing: state, id: document.id, name: document.name).encoded(), bytes)
        XCTAssertEqual(layers.values.map(\.preparations).reduce(0, +), preparations, "no layer prepared again")
    }
    #endif
}
