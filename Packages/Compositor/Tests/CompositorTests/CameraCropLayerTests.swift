// CAM-007-T06: the crop through the real Metal compositor with the stand-in camera (CAM-007-R2 to R5,
// S2, S5). The stand-in's marker picture (red top-left quarter of the camera texture, blue elsewhere)
// is 32 × 18 (16:9). Portrait: the camera turned 90° into a 48 × 64 output; landscape: upright (0°)
// into 64 × 48, as on a device turned from portrait to landscape. Every output pixel is classified
// from the read-back (red, blue or transparent) and compared with the class the CPU geometry predicts
// for its center; only pixels within 2 px of a predicted boundary (linear filtering) may differ. The
// picture's center lines (the marker's edges) are then measured and checked against the anchor
// rule. Skipped without a Metal device.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import CameraLayer
import Compositor
import Metal
import XCTest

/// The output pixel classes compared.
private enum PixelClass: Equatable {
    case red, blue, bar, mixed
}

/// One layout: output size and the camera picture's turn.
private struct Orientation {
    let name: String
    let width: Int
    let height: Int
    let rotation: CameraRotation
}

final class CameraCropLayerTests: XCTestCase {
    private typealias Color = StubCameraFrameProvider.Color
    private let pictureWidth = 32
    private let pictureHeight = 18
    private let orientations: [Orientation] = [
        Orientation(name: "portrait", width: 48, height: 64, rotation: .clockwise90),
        Orientation(name: "landscape", width: 64, height: 48, rotation: .none),
    ]

    private func geometry(_ o: Orientation, crop: CameraCrop, mirrored: Bool) -> CameraPictureGeometry {
        CameraPictureGeometry(pictureWidth: pictureWidth, pictureHeight: pictureHeight, rotation: o.rotation,
                              outputWidth: o.width, outputHeight: o.height, mirrored: mirrored, crop: crop)
    }

    /// The class the geometry predicts at output pixel (`x`, `y`)'s center.
    private func predicted(_ g: CameraPictureGeometry, x: Int, y: Int, width: Int, height: Int) -> PixelClass {
        let px: Float = (Float(x) + 0.5) / Float(width)
        let py: Float = (Float(y) + 0.5) / Float(height)
        guard g.contains(x: px, y: py) else { return .bar }
        let t = g.textureCoordinate(x: px, y: py)
        return t.x < 0.5 && t.y < 0.5 ? .red : .blue
    }

    private func measured(_ p: Pixel) -> PixelClass {
        if p.w < 0.02 { return .bar }
        if p.w > 0.98 && p.x > 0.9 && p.z < 0.1 { return .red }
        if p.w > 0.98 && p.z > 0.9 && p.x < 0.1 { return .blue }
        return .mixed
    }

    /// True when a predicted class change lies within `radius` pixels of (`x`, `y`).
    private func nearBoundary(_ classes: [PixelClass], x: Int, y: Int, width: Int, height: Int, radius: Int) -> Bool {
        let here: PixelClass = classes[y * width + x]
        for dy in -radius...radius {
            for dx in -radius...radius {
                let nx: Int = x + dx
                let ny: Int = y + dy
                guard nx >= 0, ny >= 0, nx < width, ny < height else { continue }
                if classes[ny * width + nx] != here { return true }
            }
        }
        return false
    }

    /// Linear filtering blends red and blue within one camera texel of the marker's edges (texture
    /// x = 0.5 or y = 0.5); at high zoom that is several output pixels.
    private func withinATexelOfTheMarkerEdge(_ g: CameraPictureGeometry, x: Int, y: Int, width: Int, height: Int) -> Bool {
        let px: Float = (Float(x) + 0.5) / Float(width)
        let py: Float = (Float(y) + 0.5) / Float(height)
        let t = g.textureCoordinate(x: px, y: py)
        let texelsX: Float = abs(t.x - 0.5) * Float(pictureWidth)
        let texelsY: Float = abs(t.y - 0.5) * Float(pictureHeight)
        return texelsX < 1 || texelsY < 1
    }

    /// Output x (0…1) where upright x = 0.5 is shown, and output y where upright y = 0.5 is shown.
    private func predictedCenterLines(_ g: CameraPictureGeometry) -> (x: Float, y: Float) {
        let x: Float = (0.5 - g.offsetX) / g.visibleWidth
        let y: Float = (0.5 - g.offsetY) / g.visibleHeight
        return (x, y)
    }

    /// The first index along `line` whose measured class differs from the class at index 0 and from
    /// `.mixed`-only runs: the midpoint of the transition, in pixels.
    private func transition(_ line: [PixelClass]) -> Float? {
        guard let first = line.first, first == .red || first == .blue else { return nil }
        let other: PixelClass = first == .red ? .blue : .red
        guard let end = line.firstIndex(of: other) else { return nil }
        var start: Int = end
        while start > 0 && line[start - 1] != first { start -= 1 }
        return (Float(start) + Float(end)) / 2
    }

    private struct Outcome {
        let mismatches: Int
        let verticalLine: Float?
        let horizontalLine: Float?
        let classes: [PixelClass]
    }

    private func render(_ rig: GPURig, _ layer: CameraLayerSource, _ stub: StubCameraFrameProvider, _ compositor: Compositor,
                        _ o: Orientation, crop: CameraCrop, mirrored: Bool, time: UInt64) throws -> Outcome {
        stub.rotation = o.rotation
        layer.crop = crop
        layer.mirrored = mirrored
        let output = try rig.output(width: o.width, height: o.height)
        // Each case jumps between unrelated red/blue pictures; the composite flash guard (FX-019) would
        // rightly damp such a jump, so each case starts a new flash scene, as the host does on start.
        compositor.resetFlashHistory()
        try rig.frame(compositor, into: output, time: time)
        XCTAssertEqual(compositor.outcome(ofLayer: 0), .rendered)
        let pixels: [Pixel] = try rig.read(output)
        let g = geometry(o, crop: crop, mirrored: mirrored)
        var expected: [PixelClass] = []
        var got: [PixelClass] = []
        for y in 0..<o.height {
            for x in 0..<o.width {
                expected.append(predicted(g, x: x, y: y, width: o.width, height: o.height))
                got.append(measured(pixels[y * o.width + x]))
            }
        }
        var mismatches: Int = 0
        for y in 0..<o.height {
            for x in 0..<o.width where got[y * o.width + x] != expected[y * o.width + x] {
                if nearBoundary(expected, x: x, y: y, width: o.width, height: o.height, radius: 1) { continue }
                if withinATexelOfTheMarkerEdge(g, x: x, y: y, width: o.width, height: o.height) { continue }
                mismatches += 1
            }
        }
        // Measure the center lines: along the middle row of the picture's top half, and down a column
        // inside the marker's side.
        let lines = predictedCenterLines(g)
        var vertical: Float?
        var horizontal: Float?
        let topHalfY: Float = (0.25 - g.offsetY) / g.visibleHeight
        let rowIndex: Int = Int((topHalfY * Float(o.height)).rounded(.down))
        if rowIndex >= 0 && rowIndex < o.height {
            let row: [PixelClass] = (0..<o.width).map { (x: Int) -> PixelClass in got[rowIndex * o.width + x] }
            let firstPicture: Int? = row.firstIndex { (c: PixelClass) -> Bool in c == .red || c == .blue }
            if let firstPicture, let t = transition(Array(row[firstPicture...])) { vertical = (Float(firstPicture) + t + 0.5) / Float(o.width) }
        }
        // Down a column halfway between the vertical center line and each edge: the marker's side has
        // the red/blue transition at the horizontal center line.
        let sides: [Float] = [lines.x / 2, (lines.x + 1) / 2]
        for side in sides where horizontal == nil && lines.y > 0 && lines.y < 1 {
            let columnIndex: Int = Int((side * Float(o.width)).rounded(.down))
            guard columnIndex >= 0, columnIndex < o.width else { continue }
            let column: [PixelClass] = (0..<o.height).map { (y: Int) -> PixelClass in got[y * o.width + columnIndex] }
            let firstPicture: Int? = column.firstIndex { (c: PixelClass) -> Bool in c == .red || c == .blue }
            if let firstPicture, let t = transition(Array(column[firstPicture...])) { horizontal = (Float(firstPicture) + t + 0.5) / Float(o.height) }
        }
        return Outcome(mismatches: mismatches, verticalLine: vertical, horizontalLine: horizontal, classes: got)
    }

    /// CAM-007-S2: portrait then landscape for each crop; mirror off and on for Fill Top 2×.
    func testPortraitToLandscapeKeepsTheChosenCropInPixels() throws {
        let rig = try GPURig()
        let red = Color(red: 255, green: 0, blue: 0)
        let blue = Color(red: 0, green: 0, blue: 255)
        let stub = StubCameraFrameProvider(device: rig.device, scenario: .granted, pattern: .marker(background: blue, marker: red),
                                           width: pictureWidth, height: pictureHeight, rotation: .clockwise90)
        let layer = CameraLayerSource(provider: stub)
        let compositor = try Compositor(device: rig.device, layers: [layer])
        layer.start()
        let cases: [(CameraCrop, Bool)] = [
            (.fill, false),
            (CameraCrop(mode: .fill, anchor: .top, zoom: 2), false),
            (CameraCrop(mode: .fill, anchor: .top, zoom: 2), true),
            (CameraCrop(mode: .fill, anchor: .bottom, zoom: 1), false),
            (CameraCrop(mode: .fill, anchor: .center, zoom: 1.5), true),
            (CameraCrop(mode: .fit, anchor: .center, zoom: 1), false),
            (CameraCrop(mode: .fit, anchor: .top, zoom: 1), true),
        ]
        var time: UInt64 = 1
        var rows: [String] = []
        for (crop, mirrored) in cases {
            let label: String = "\(crop.mode.rawValue)/\(crop.anchor.rawValue)/\(crop.zoom)" + (mirrored ? " mirrored" : "")
            for o in orientations {
                time += 16_666_667
                let outcome = try render(rig, layer, stub, compositor, o, crop: crop, mirrored: mirrored, time: time)
                let g = geometry(o, crop: crop, mirrored: mirrored)
                let lines = predictedCenterLines(g)
                let where_: String = label + " " + o.name
                XCTAssertEqual(outcome.mismatches, 0, where_ + ": pixels away from boundaries match the geometry")
                // The anchor is on the vertical center line: the picture's vertical center line is at the
                // output's horizontal center in every orientation (2 px tolerance).
                let pixelX: Float = 2 / Float(o.width)
                let pixelY: Float = 2 / Float(o.height)
                let vertical = try XCTUnwrap(outcome.verticalLine, where_ + ": vertical center line found")
                XCTAssertEqual(vertical, 0.5, accuracy: pixelX, where_ + ": vertical center line at the output's center")
                if lines.y > 0.05 && lines.y < 0.95 {
                    let horizontal = try XCTUnwrap(outcome.horizontalLine, where_ + ": horizontal center line found")
                    XCTAssertEqual(horizontal, lines.y, accuracy: pixelY, where_ + ": horizontal center line where predicted")
                    if crop.anchor == .center {
                        XCTAssertEqual(horizontal, 0.5, accuracy: pixelY, where_ + ": Center anchor at the output's center")
                    }
                }
                let bars: Int = outcome.classes.filter { (c: PixelClass) -> Bool in c == .bar }.count
                if crop.mode == .fill {
                    XCTAssertEqual(bars, 0, where_ + ": Fill covers the output")
                } else {
                    XCTAssertGreaterThan(bars, 0, where_ + ": Fit shows bars")
                    if crop.anchor == .top {
                        let topMiddle: PixelClass = outcome.classes[o.width / 2]
                        let bottomMiddle: PixelClass = outcome.classes[(o.height - 1) * o.width + o.width / 2]
                        XCTAssertNotEqual(topMiddle, .bar, where_ + ": Fit Top sits against the top edge")
                        if g.visibleHeight > 1.01 { XCTAssertEqual(bottomMiddle, .bar, where_ + ": the bar is below") }
                    }
                }
                let lineText: String = outcome.horizontalLine.map { String($0) } ?? "off-screen"
                rows.append(where_ + ": mismatches \(outcome.mismatches), vertical line \(vertical), horizontal line " + lineText
                            + ", bars \(bars)")
            }
        }
        XCTAssertEqual(stub.startCount, 1, "crop, mirror and turn changes never restart the camera")
        XCTAssertEqual(layer.framesShown, cases.count * orientations.count, "each change showed on the very next frame")
        print("CAM-007 crop pixels:\n" + rows.joined(separator: "\n"))
    }
}
#endif
