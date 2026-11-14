// LayerInspectorRenderTests.swift — CMP-015-T13 (CMP-015-S2, S5, S6): the inspector's live path on a real
// Photo visual, offscreen at 64 × 64. Opacity and transform edits on layer 2 (the circular spectrum,
// fed fixed band values) change the frame; Undo through a real SceneHistoryCoordinator returns the exact
// prior frame, byte for byte. A placement edit re-renders no cached picture (CMP-013), and solo hides
// the other layer without touching the history. Needs a Metal device; skipped without one. Simulator
// pixels are never device evidence (Constitution X).
import Compositor
import ImageLayer
import Metal
import SceneFormat
import XCTest
@testable import projectM_iOS

@MainActor
final class LayerInspectorRenderTests: XCTestCase {
    private static let side = 64
    private static let bands = [Float](repeating: 0.8, count: 32)

    private func makeHost() throws -> PhotoVisualHost {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device in this simulator") }
        let host = try PhotoVisualHost.make(device: device, reader: nil, barCount: .b32)
        let data = try XCTUnwrap(UITestPhotoFixture.png(alpha: false))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cmp015-\(UUID().uuidString).png")
        try data.write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        host.content = .file(url)
        for _ in 0..<200 {   // a ceiling for the background decode, not a timing assertion
            if case .ready = host.imageState { break }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        }
        guard case .ready = host.imageState else { throw XCTSkip("the photo did not decode: \(host.imageState)") }
        return host
    }

    /// One offscreen composite; returns the read-back BGRA bytes.
    private func frame(_ host: PhotoVisualHost) throws -> [UInt8] {
        let device = host.compositor.device
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: Self.side, height: Self.side, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .private
        let output = try XCTUnwrap(device.makeTexture(descriptor: d))
        let commands = try XCTUnwrap(queue.makeCommandBuffer())
        let ok: Bool = Self.bands.withUnsafeBufferPointer { (bands: UnsafeBufferPointer<Float>) -> Bool in
            let audio = LayerAudioContext(frame: nil, bands: bands, events: UnsafeBufferPointer(start: nil, count: 0), droppedEvents: 0)
            return host.compositor.composite(into: output, commandBuffer: commands, presentationTimeNanoseconds: 1_000_000_000,
                                             contentScale: 2, reduceFlashing: false, audio: audio)
        }
        XCTAssertTrue(ok)
        commands.commit()
        commands.waitUntilCompleted()
        let rowBytes: Int = Self.side * 4
        let length: Int = rowBytes * Self.side
        let buffer = try XCTUnwrap(device.makeBuffer(length: length, options: .storageModeShared))
        let copy = try XCTUnwrap(queue.makeCommandBuffer())
        let blit = try XCTUnwrap(copy.makeBlitCommandEncoder())
        blit.copy(from: output, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: Self.side, height: Self.side, depth: 1), to: buffer,
                  destinationOffset: 0, destinationBytesPerRow: rowBytes, destinationBytesPerImage: length)
        blit.endEncoding()
        copy.commit()
        copy.waitUntilCompleted()
        let bytes = buffer.contents().bindMemory(to: UInt8.self, capacity: length)
        return Array(UnsafeBufferPointer(start: bytes, count: length))
    }

    /// The inspector and history over the host, wired as AppCoordinator wires them.
    private func makeInspector(_ host: PhotoVisualHost) -> (LayerInspectorCoordinator, SceneHistoryCoordinator) {
        let layers = LayerInspectorCoordinator()
        layers.onCompositesChange = { [weak host] () -> Void in host?.compositor.applyLayerComposites(layers.composites) }
        layers.onSoloMuteChange = { [weak host] () -> Void in host?.compositor.applySoloMute(soloed: layers.soloed, muted: layers.muted) }
        var base = SceneAutosaveFixtures.inputs(visual: .photo, bars: 32)
        base.photoID = UUID()
        let history = SceneHistoryCoordinator()
        history.inputs = { () -> SceneInputs in
            var current = base
            current.layerComposites = layers.composites
            return current
        }
        history.carry = { () -> SceneAutosaveCarry in SceneAutosaveFixtures.carry }
        history.apply = { (inputs: SceneInputs) -> Void in layers.restore(inputs.layerComposites ?? [:]) }
        layers.onEditEnded = { () -> Void in history.endCoalescing() }
        layers.restore(UITestLayerInspectorFixture.composites)
        history.start(observing: false)
        return (layers, history)
    }

    func testUndoOfOpacityAndTransformOnLayerTwoRestoresTheFramePixelForPixel() throws {
        let host = try makeHost()
        let (layers, history) = makeInspector(host)
        let kind = "spectrum.circular"
        for _ in 0..<3 { _ = try frame(host) }   // warm up: pictures cached, spectrum settled
        let before = try frame(host)
        XCTAssertEqual(try frame(host), before, "the frame is stable without edits")

        layers.setValue(.opacity, 0.3, kind: kind)
        history.capture()
        layers.endEdit()
        layers.setValue(.positionY, -0.3, kind: kind)
        history.capture()
        layers.setValue(.scale, 0.5, kind: kind)
        history.capture()
        layers.endEdit()
        XCTAssertEqual(host.compositor.shownOpacity(ofLayer: 1), 0.3, accuracy: 1e-6, "applied from the next frame, no fade")
        let edited = try frame(host)
        XCTAssertNotEqual(edited, before, "the edit is drawn")
        XCTAssertTrue(host.compositor.wasReused(layer: 0), "CMP-013: the photo's picture is reused after a placement edit")

        history.undo()
        history.undo()
        history.undo()
        XCTAssertEqual(layers.composite(for: kind), UITestLayerInspectorFixture.composites[kind], "the prior values")
        XCTAssertEqual(try frame(host), before, "the frame before the edits, byte for byte")
    }

    func testSoloHidesTheOtherLayerWithoutAnUndoStep() throws {
        let host = try makeHost()
        let (layers, history) = makeInspector(host)
        _ = try frame(host)
        layers.toggleSolo(kind: "photo", title: "Photo")
        history.capture()
        XCTAssertFalse(host.compositor.isHiddenBySoloMute(layer: 0), "the soloed photo is drawn")
        XCTAssertTrue(host.compositor.isHiddenBySoloMute(layer: 1), "the spectrum is hidden")
        XCTAssertFalse(history.canUndo, "solo is not undoable")
        XCTAssertEqual(host.compositor.appliedStack?.entries.map(\.settings.opacity), [0.8, 0.6], "the stack is unchanged")
        layers.clearSoloMute()
        XCTAssertFalse(host.compositor.isHiddenBySoloMute(layer: 1))
    }
}
