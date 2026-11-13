// CircularSpectrumLayout.swift — the circular spectrum's geometry on the CPU (VIS-001-R2, R3, R5,
// R7, R8; research VIS-001-D2; data-model.md).
//
// Screen model: the output is W × H pixels with y growing downward; the ring's centre is (W/2, H/2)
// and one radius unit is min(W, H)/2 pixels in both axes, so circles stay circular and the whole ring
// (at most 1 radius unit) fits at any aspect ratio. An angle θ is measured clockwise from the top
// of the output; the point at radius r is (cx + r·sin θ, cy − r·cos θ). Turning the device changes
// W and H only: bar k keeps its angle relative to the screen ("survives rotation", User Story 3).
//
// Bar k (value v ∈ 0…1) is the annular sector θ(k) ± halfWidth between innerRadius and
// innerRadius + v·lengthScale (radius units). Tessellation: 4 arc segments per bar, two triangles
// each (24 vertices), in normalized device coordinates (x right, y up), premultiplied colors. The
// radial sides are exact; the arcs are chords (error below 0.08 % of the radius).
//
// Real-time safety (Constitution VII): bars, values and colors for 128 bars are allocated in
// `init`; `layout`, `tessellate` and the luminance only touch that memory. Not Sendable: one owner.
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif
import FlashSafety

/// One bar's geometry in pixels.
public struct BarGeometry: Sendable, Equatable {
    /// θ(k) in [0, 360), clockwise from the top.
    public var centerDegrees: Double
    public var halfWidthDegrees: Double
    public var innerRadius: Double
    public var outerRadius: Double
    /// Linear, before the Reduce-flashing gain.
    public var color: LinearColor

    public init(centerDegrees: Double = 0, halfWidthDegrees: Double = 0, innerRadius: Double = 0,
                outerRadius: Double = 0, color: LinearColor = .opaqueBlack) {
        self.centerDegrees = centerDegrees
        self.halfWidthDegrees = halfWidthDegrees
        self.innerRadius = innerRadius
        self.outerRadius = outerRadius
        self.color = color
    }

    /// The bar has a visible length.
    public var isLit: Bool { outerRadius > innerRadius }
}

/// One vertex as the shader reads it: `packed_float2` position (NDC) + `packed_float4` color
/// (linear, premultiplied). 24 bytes.
public struct SpectrumVertex: Sendable, Equatable {
    public var x: Float = 0
    public var y: Float = 0
    public var r: Float = 0
    public var g: Float = 0
    public var b: Float = 0
    public var a: Float = 0

    public init() {}

    @inlinable
    init(x: Float, y: Float, color: LinearColor, gain: Float) {
        self.x = x
        self.y = y
        r = color.red * gain * color.alpha
        g = color.green * gain * color.alpha
        b = color.blue * gain * color.alpha
        a = color.alpha
    }
}

/// Clamps a band value to 0…1; NaN and negative values read 0 (VIS-001-R8).
@inlinable
func sanitizedBandValue(_ v: Float) -> Float {
    v > 0 ? min(v, 1) : 0
}

public final class CircularSpectrumLayout {
    public static let segmentsPerBar = 4
    public static let verticesPerBar = segmentsPerBar * 6
    public static let maximumVertexCount = SpectrumBarCount.maximum * verticesPerBar

    private let bars: UnsafeMutablePointer<BarGeometry>
    private let values: UnsafeMutablePointer<Float>
    private let colors: UnsafeMutablePointer<LinearColor>
    /// FX-019: the strobe safety envelope's area levels (`meanLevels`).
    private let flashAreas = SpectrumFlashAreas()
    private var generation = 0

    /// Always clamped; setting it recomputes the palette colors (no allocation).
    public var configuration: CircularSpectrumConfiguration {
        didSet {
            configuration = configuration.clamped()
            if configuration.palette != oldValue.palette || configuration.barCount != oldValue.barCount {
                updateColors()
            }
        }
    }

    public private(set) var width = 0
    public private(set) var height = 0
    /// min(W, H)/2 pixels.
    public private(set) var radiusUnit = 0.0
    public private(set) var centerX = 0.0
    public private(set) var centerY = 0.0

    public init(configuration: CircularSpectrumConfiguration = CircularSpectrumConfiguration()) {
        self.configuration = configuration.clamped()
        let n = SpectrumBarCount.maximum
        bars = .allocate(capacity: n)
        bars.initialize(repeating: BarGeometry(), count: n)
        values = .allocate(capacity: n)
        values.initialize(repeating: 0, count: n)
        colors = .allocate(capacity: n)
        colors.initialize(repeating: .opaqueBlack, count: n)
        updateColors()
    }

    deinit {
        let n = SpectrumBarCount.maximum
        bars.deinitialize(count: n); bars.deallocate()
        values.deinitialize(count: n); values.deallocate()
        colors.deinitialize(count: n); colors.deallocate()
    }

    private func updateColors() {
        let n = configuration.barCount.rawValue
        for k in 0..<n { colors[k] = configuration.palette.color(bar: k, of: n) }
    }

    public var barCount: Int { configuration.barCount.rawValue }

    /// Bar `k` of the last layout (k < barCount).
    public func bar(_ k: Int) -> BarGeometry { bars[k] }

    /// The sanitized value bar `k` was laid out with.
    public func value(ofBar k: Int) -> Float { values[k] }

    /// Lays out `barCount` bars for an output of `width × height` pixels. `bands[k]` drives bar k;
    /// missing bands read 0, extra ones are ignored.
    public func layout(values bands: UnsafeBufferPointer<Float>, width: Int, height: Int) {
        let c = configuration
        let n = c.barCount.rawValue
        self.width = max(width, 0)
        self.height = max(height, 0)
        radiusUnit = Double(min(self.width, self.height)) / 2
        centerX = Double(self.width) / 2
        centerY = Double(self.height) / 2
        let inner = c.innerRadius * radiusUnit
        let length = c.lengthScale * radiusUnit
        let half = c.halfWidthDegrees
        generation &+= 1
        for k in 0..<n {
            let v = k < bands.count ? sanitizedBandValue(bands[k]) : 0
            values[k] = v
            bars[k] = BarGeometry(centerDegrees: c.centerDegrees(ofBar: k), halfWidthDegrees: half,
                                  innerRadius: inner, outerRadius: inner + Double(v) * length, color: colors[k])
        }
    }

    /// Array convenience (tests and callers off the frame path).
    public func layout(_ bands: [Float], width: Int, height: Int) {
        bands.withUnsafeBufferPointer { layout(values: $0, width: width, height: height) }
    }

    /// Writes the triangles of every lit bar (whole bars only, at most `capacity` vertices) and
    /// returns the vertex count. `gain` scales colors (Reduce flashing).
    public func tessellate(into out: UnsafeMutablePointer<SpectrumVertex>, capacity: Int, gain: Float) -> Int {
        guard width > 0, height > 0 else { return 0 }
        let sx = 2 / Double(width)
        let sy = 2 / Double(height)
        var count = 0
        let segments = Self.segmentsPerBar
        for k in 0..<barCount {
            let bar = bars[k]
            guard bar.isLit, count + Self.verticesPerBar <= capacity else { continue }
            let start = (bar.centerDegrees - bar.halfWidthDegrees) * .pi / 180
            let step = 2 * bar.halfWidthDegrees * .pi / 180 / Double(segments)
            var s0 = sin(start), c0 = cos(start)
            for s in 1...segments {
                let a1 = start + Double(s) * step
                let s1 = sin(a1), c1 = cos(a1)
                // NDC: x = 2·px/W − 1 with px = cx + r·sinθ  →  (r·sinθ)·2/W; y = 1 − 2·py/H → (r·cosθ)·2/H.
                func vertex(_ r: Double, _ sn: Double, _ cs: Double) -> SpectrumVertex {
                    SpectrumVertex(x: Float(r * sn * sx), y: Float(r * cs * sy), color: bar.color, gain: gain)
                }
                let i0 = vertex(bar.innerRadius, s0, c0), o0 = vertex(bar.outerRadius, s0, c0)
                let i1 = vertex(bar.innerRadius, s1, c1), o1 = vertex(bar.outerRadius, s1, c1)
                out[count] = i0; out[count + 1] = o0; out[count + 2] = o1
                out[count + 3] = i0; out[count + 4] = o1; out[count + 5] = i1
                count += 6
                s0 = s1; c0 = c1
            }
        }
        return count
    }

    /// The mean relative luminance of the output split into the bars' part (scaled by any gain) and
    /// the background's part (VIS-001-D7). Exact sector areas: halfWidth·(r_out² − r_in²).
    public func luminanceComponents() -> (bars: Double, background: Double) {
        guard width > 0, height > 0 else { return (0, 0) }
        let total = Double(width) * Double(height)
        var covered = 0.0
        var lit = 0.0
        for k in 0..<barCount {
            let bar = bars[k]
            guard bar.isLit else { continue }
            let area = bar.halfWidthDegrees * .pi / 180 * (bar.outerRadius * bar.outerRadius - bar.innerRadius * bar.innerRadius)
            covered += area
            lit += area * Double(bar.color.relativeLuminance * bar.color.alpha)
        }
        let background = Double(configuration.background.relativeLuminance) * max(0, total - covered) / total
        return (lit / total, background)
    }

    /// Mean relative luminance of the frame drawn with `gain`.
    public func meanRelativeLuminance(gain: Float = 1) -> Double {
        let parts = luminanceComponents()
        return parts.bars * Double(gain) + parts.background
    }

    /// Mean relative luminance of the frame drawn with `gain` after downstream stages described by
    /// `transfer` (FX-001-R10). Each lit bar is a flat region of its pixel color (the bar's color
    /// × gain composited "over" the background); the rest is background. With the identity
    /// transfer this equals `meanRelativeLuminance(gain:)` for opaque palettes. No allocation.
    public func meanLuminance<Transfer: FrameLuminanceTransfer>(gain: Float, transfer: Transfer) -> Double {
        guard width > 0, height > 0 else { return 0 }
        let total = Double(width) * Double(height)
        let background = configuration.background
        var covered = 0.0
        var sum = 0.0
        for k in 0..<barCount {
            let bar = bars[k]
            guard bar.isLit else { continue }
            let area = bar.halfWidthDegrees * .pi / 180 * (bar.outerRadius * bar.outerRadius - bar.innerRadius * bar.innerRadius)
            covered += area
            let c = bar.color
            let a = c.alpha
            let pixel = LinearColor(red: c.red * gain * a + (1 - a) * background.red,
                                    green: c.green * gain * a + (1 - a) * background.green,
                                    blue: c.blue * gain * a + (1 - a) * background.blue,
                                    alpha: a + (1 - a) * background.alpha)
            sum += area * transfer.outputLuminance(ofFlatColor: pixel)
        }
        sum += max(0, total - covered) * transfer.outputLuminance(ofFlatColor: background)
        return sum / total
    }

    /// The frame's levels in the strobe safety envelope's 17 areas (tiles 0…15 row-major from the
    /// top, then the whole frame) when drawn with `gain` and passed through `transfer` (FX-019-R4;
    /// SpectrumFlashAreas.swift). The whole frame equals `meanLuminance(gain:transfer:)`. Writes
    /// `FlashZones.count` values; no allocation.
    public func meanLevels<Transfer: FrameLuminanceTransfer>(gain: Float, transfer: Transfer,
                                                             into out: UnsafeMutableBufferPointer<FlashLevels>) {
        flashAreas.levels(of: self, generation: generation, gain: gain, transfer: transfer, into: out)
    }
}
