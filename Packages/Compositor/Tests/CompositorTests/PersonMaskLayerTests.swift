// CAM-008-T07, T08: the person mask through the real Metal compositor with the stand-in camera and a
// fixture segmenter (CAM-008-S1, S2). The stand-in's marker picture is 32 × 18; the fixture mask marks a
// rectangle of it ("the person"). Each case renders the same frame with the mask Off (the reference)
// and with Person or Background, reads both back, and checks every output pixel whose centre lies at
// least 1.5 mask texels from the rectangle's edge (linear filtering softens the edge): outside the person
// the Person result is transparent (every channel ≤ 1/255), inside it equals the reference within 1/255;
// Background is the inverse. The prediction uses the CPU geometry (`CameraPictureGeometry`), so it
// follows rotation, mirror, Fill/Fit, anchor and zoom. Unsupported, failing, paused and no-mask-yet
// segmentation must equal the reference at every pixel. Skipped without a Metal device.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import CameraLayer
import Compositor
import CoreVideo
import Metal
import XCTest

private struct MaskCase {
    let name: String
    let width: Int
    let height: Int
    let rotation: CameraRotation
    let crop: CameraCrop
    let mirrored: Bool
    let space: PersonMaskSpace
}

final class PersonMaskLayerTests: XCTestCase {
    private typealias Color = StubCameraFrameProvider.Color
    private let pictureWidth = 32
    private let pictureHeight = 18
    private let immediately: PersonMasker.Runner = { (job: @escaping @Sendable () -> Void) -> Void in job() }

    private struct Rig {
        let gpu: GPURig
        let stub: StubCameraFrameProvider
        let layer: CameraLayerSource
        let compositor: Compositor
    }

    private func makeRig() throws -> Rig {
        let gpu = try GPURig()
        let red = Color(red: 255, green: 0, blue: 0)
        let blue = Color(red: 0, green: 0, blue: 255)
        let stub = StubCameraFrameProvider(device: gpu.device, scenario: .granted, pattern: .marker(background: blue, marker: red),
                                           width: pictureWidth, height: pictureHeight)
        let layer = CameraLayerSource(provider: stub)
        let compositor = try Compositor(device: gpu.device, layers: [layer])
        return Rig(gpu: gpu, stub: stub, layer: layer, compositor: compositor)
    }

    /// The fixture person (off-centre, so a half turn changes it): columns 6..<20, rows 2..<12 of the picture (texture space), or the same
    /// rectangle of the upright picture for a quarter turn (upright space, 18 × 32).
    private func fixture(_ c: MaskCase) -> PersonMaskBitmap {
        if c.space == .upright && c.rotation.swapsAxes {
            return PersonMaskBitmap.rectangle(width: pictureHeight, height: pictureWidth, x0: 3, y0: 5, x1: 12, y1: 20, space: .upright)!
        }
        return PersonMaskBitmap.rectangle(width: pictureWidth, height: pictureHeight, x0: 6, y0: 2, x1: 20, y1: 12, space: c.space)!
    }

    private func render(_ rig: Rig, _ c: MaskCase, mode: CameraPersonMaskMode, time: UInt64) throws -> [Pixel] {
        rig.stub.rotation = c.rotation
        rig.layer.crop = c.crop
        rig.layer.mirrored = c.mirrored
        rig.layer.personMaskMode = mode
        rig.layer.personMasker?.reset()
        rig.stub.deliverNextPicture()   // the next camera picture: analysed at once (synchronous runner)
        let output = try rig.gpu.output(width: c.width, height: c.height)
        rig.compositor.resetFlashHistory()
        try rig.gpu.frame(rig.compositor, into: output, time: time)
        XCTAssertEqual(rig.compositor.outcome(ofLayer: 0), .rendered)
        return try rig.gpu.read(output)
    }

    /// Where the output pixel's centre falls in the mask: (coverage, distance to the edge in mask texels),
    /// or nil in Fit's bars.
    private func predicted(_ c: MaskCase, _ mask: PersonMaskBitmap, x: Int, y: Int) -> (inside: Bool, edge: Float)? {
        let g = CameraPictureGeometry(pictureWidth: pictureWidth, pictureHeight: pictureHeight, rotation: c.rotation,
                                      outputWidth: c.width, outputHeight: c.height, mirrored: c.mirrored, crop: c.crop)
        let px: Float = (Float(x) + 0.5) / Float(c.width)
        let py: Float = (Float(y) + 0.5) / Float(c.height)
        guard g.contains(x: px, y: py) else { return nil }
        let u: Float
        let v: Float
        if mask.space == .upright {
            let a: Float = g.offsetX + px * g.visibleWidth
            u = c.mirrored ? 1 - a : a
            v = g.offsetY + py * g.visibleHeight
        } else {
            let t = g.textureCoordinate(x: px, y: py)
            u = t.x
            v = t.y
        }
        let mx: Float = u * Float(mask.width)
        let my: Float = v * Float(mask.height)
        // Distance in texels to the nearest coverage change (the rectangle's edges).
        var edge: Float = .infinity
        let inside: Bool = mask.coverage(u: u, v: v) > 0.5
        let rows: [Int] = (0..<mask.height).filter { (r: Int) -> Bool in mask.bytes[r * mask.width + mask.width / 2] > 0 }
        let cols: [Int] = (0..<mask.width).filter { (k: Int) -> Bool in mask.bytes[(mask.height / 2) * mask.width + k] > 0 }
        if let r0 = rows.first, let r1 = rows.last, let c0 = cols.first, let c1 = cols.last {
            for e in [Float(c0), Float(c1 + 1)] { edge = min(edge, abs(mx - e)) }
            for e in [Float(r0), Float(r1 + 1)] { edge = min(edge, abs(my - e)) }
        }
        return (inside, edge)
    }

    private func maxDifference(_ a: Pixel, _ b: Pixel) -> Float {
        var d: Float = 0
        for k in 0..<4 { d = max(d, abs(a[k] - b[k])) }
        return d
    }

    /// CAM-008-S1: Person and Background through four framings, texture and upright mask spaces.
    func testFixtureMaskCutsTheLayerToThePersonInEveryFraming() throws {
        let rig = try makeRig()
        rig.layer.personMasker = PersonMasker(segmenter: FixturePersonSegmenter(mask: nil), runner: immediately)
        rig.layer.start()
        let cases: [MaskCase] = [
            MaskCase(name: "landscape fill", width: 64, height: 48, rotation: .none, crop: .fill, mirrored: false, space: .texture),
            MaskCase(name: "portrait fill top 1.5x mirrored", width: 48, height: 64, rotation: .clockwise90,
                     crop: CameraCrop(mode: .fill, anchor: .top, zoom: 1.5), mirrored: true, space: .texture),
            MaskCase(name: "portrait fit upright", width: 48, height: 64, rotation: .clockwise90,
                     crop: CameraCrop(mode: .fit, anchor: .center, zoom: 1), mirrored: false, space: .upright),
            MaskCase(name: "upside down fill 2x mirrored upright", width: 64, height: 48, rotation: .clockwise180,
                     crop: CameraCrop(mode: .fill, anchor: .bottom, zoom: 2), mirrored: true, space: .upright),
        ]
        var time: UInt64 = 1
        for c in cases {
            let mask: PersonMaskBitmap = fixture(c)
            rig.layer.personMasker = PersonMasker(segmenter: FixturePersonSegmenter(mask: mask), runner: immediately)
            time += 16_666_667
            let reference: [Pixel] = try render(rig, c, mode: .off, time: time)
            for mode in [CameraPersonMaskMode.person, .background] {
                time += 16_666_667
                let shownBefore: Int = rig.layer.framesMasked
                let masked: [Pixel] = try render(rig, c, mode: mode, time: time)
                XCTAssertEqual(rig.layer.framesMasked, shownBefore + 1, c.name + ": drawn with the mask")
                var kept = 0, cut = 0, bars = 0, worstKept: Float = 0, worstCut: Float = 0
                for y in 0..<c.height {
                    for x in 0..<c.width {
                        let i: Int = y * c.width + x
                        guard let p = predicted(c, mask, x: x, y: y) else {
                            XCTAssertLessThanOrEqual(masked[i].w, 1.0 / 255, c.name + ": Fit's bars stay transparent")
                            bars += 1
                            continue
                        }
                        guard p.edge >= 1.5 else { continue }
                        let shows: Bool = mode == .person ? p.inside : !p.inside
                        if shows {
                            worstKept = max(worstKept, maxDifference(masked[i], reference[i])); kept += 1
                        } else {
                            worstCut = max(worstCut, maxDifference(masked[i], .zero)); cut += 1
                        }
                    }
                }
                let label: String = c.name + " " + mode.rawValue
                XCTAssertGreaterThan(kept, 20, label + ": pixels kept were checked")
                XCTAssertGreaterThan(cut, 20, label + ": pixels cut were checked")
                XCTAssertLessThanOrEqual(worstKept, 1.0 / 255, label + ": kept pixels equal the unmasked picture")
                XCTAssertLessThanOrEqual(worstCut, 1.0 / 255, label + ": cut pixels are transparent")
                if c.crop.mode == .fit { XCTAssertGreaterThan(bars, 0, label) }
            }
        }
    }

    /// CAM-008-S2: unsupported, failing, paused and not-yet-analysed segmentation draw the Off picture.
    func testUnavailableSegmentationDrawsTheUnmaskedPicture() throws {
        let rig = try makeRig()
        rig.layer.start()
        let c = MaskCase(name: "portrait fill", width: 48, height: 64, rotation: .clockwise90, crop: .fill, mirrored: true, space: .texture)
        let mask: PersonMaskBitmap = fixture(c)
        let neverRuns: PersonMasker.Runner = { (_: @escaping @Sendable () -> Void) -> Void in }
        let paused = PersonMasker(segmenter: FixturePersonSegmenter(mask: mask), runner: immediately)
        paused.plan = .paused
        let maskers: [(String, PersonMasker?)] = [
            ("no masker", nil),
            ("unsupported", PersonMasker(segmenter: FixturePersonSegmenter(mask: mask, supported: false), runner: immediately)),
            ("failing", PersonMasker(segmenter: FixturePersonSegmenter(mask: mask, fails: true), runner: immediately)),
            ("paused", paused),
            ("no mask yet", PersonMasker(segmenter: FixturePersonSegmenter(mask: mask), runner: neverRuns)),
        ]
        var time: UInt64 = 1
        rig.layer.personMasker = nil
        time += 16_666_667
        let reference: [Pixel] = try render(rig, c, mode: .off, time: time)
        for (name, masker) in maskers {
            rig.layer.personMasker = masker
            for mode in [CameraPersonMaskMode.person, .background] {
                time += 16_666_667
                let pixels: [Pixel] = try render(rig, c, mode: mode, time: time)
                var worst: Float = 0
                for i in pixels.indices { worst = max(worst, maxDifference(pixels[i], reference[i])) }
                XCTAssertLessThanOrEqual(worst, 1.0 / 255, name + " " + mode.rawValue + ": identical to Off")
            }
        }
        XCTAssertEqual(rig.layer.framesMasked, 0, "no frame was drawn with a mask")
        rig.layer.personMasker = PersonMasker(segmenter: FixturePersonSegmenter(mask: mask), runner: immediately)
        time += 16_666_667
        _ = try render(rig, c, mode: .person, time: time)
        XCTAssertEqual(rig.layer.framesMasked, 1, "the same rig masks once segmentation is available")
        rig.layer.stop()
        XCTAssertNil(rig.layer.personMasker?.latestMask(), "stopping the camera drops the mask (CAM-008-R7)")
    }
}
#endif
