// OscilloscopeLayout.swift — the oscilloscope's geometry on the CPU (VIS-003-R3 to R9; research
// VIS-003-D2, D3; data-model.md).
//
// Per frame: the trigger (`WaveformTrigger`) picks the window start in the sample history; the W
// samples from there are resampled at P = min(W, 1,024) points spread over the output's width
// (x = j·width/(P − 1)), each at y = H/2 − s·a·H/2 (s sanitized: NaN/±∞ → 0, clamped to ±1; a = the
// amplitude). Screen model: W × H pixels, y down. The line is drawn as one rectangle per segment
// (thickness T = max(thickness × the shorter side, 1 px), butt ends) and, at each turn, a bevel
// triangle on the outer side (the point and the two rectangles' outer corners there), so joints have
// no gap. Segment k's color is palette color k of the segment count (never the sample value).
//
// The strobe safety envelope (FX-019-R4, R9): regions 0…S−1 are the rectangles, S…S+P−3 the bevels
// (a triangle passed as a quad with a repeated corner); flat colors over a flat background, clipped
// exactly to the 4 × 4 tiles by `SpectrumFlashAreas`. Regions overlap only on a turn's inner side,
// where the light is counted twice: an overestimate, never an underestimate.
//
// Real-time safety (Constitution VII): every buffer is allocated in `init`; `layout`, `tessellate` and
// `meanLevels` only touch it. Not Sendable: one owner.
import FlashSafety

public final class OscilloscopeLayout: FlashAreaLevelSource {
    public static let maximumPoints = 1_024
    public static let maximumSegments = maximumPoints - 1
    public static let maximumBevels = maximumPoints - 2
    /// Six vertices per rectangle, three per bevel.
    public static let maximumVertexCount = maximumSegments * 6 + maximumBevels * 3

    /// The trigger stabilizer (its reference follows the frames laid out here).
    public let trigger = WaveformTrigger()
    /// The trigger's result for the last frame laid out with `layout(samples:width:height:)`.
    public private(set) var lastTrigger = WaveformTriggerResult(start: 0, mode: .freeRun(.silence), crossingCount: 0, periodSamples: nil)

    /// Always clamped. A new window length starts the trigger afresh (it matches same-length windows only).
    public var configuration: OscilloscopeConfiguration {
        didSet { configuration = configuration.clamped() }
    }

    public private(set) var width = 0
    public private(set) var height = 0
    public private(set) var pointCount = 0
    /// T in pixels of the last layout.
    public private(set) var thicknessPixels = 1.0

    private let xs: UnsafeMutablePointer<Double>
    private let ys: UnsafeMutablePointer<Double>
    /// Per segment: 4 corners (x, y interleaved).
    private let rectangles: UnsafeMutablePointer<Double>
    /// Per bevel: 3 corners (x, y interleaved) and the area.
    private let bevels: UnsafeMutablePointer<Double>
    private let bevelAreas: UnsafeMutablePointer<Double>
    private let colors: UnsafeMutablePointer<LinearColor>
    private var colorCount = -1
    private var colorPalette = VisualPalette.spectrum
    private let flashAreas = SpectrumFlashAreas(regionCapacity: OscilloscopeLayout.maximumSegments + OscilloscopeLayout.maximumBevels)
    private var generation = 0

    public init(configuration: OscilloscopeConfiguration = OscilloscopeConfiguration()) {
        self.configuration = configuration.clamped()
        let p = Self.maximumPoints
        xs = .allocate(capacity: p); xs.initialize(repeating: 0, count: p)
        ys = .allocate(capacity: p); ys.initialize(repeating: 0, count: p)
        rectangles = .allocate(capacity: 8 * Self.maximumSegments)
        rectangles.initialize(repeating: 0, count: 8 * Self.maximumSegments)
        bevels = .allocate(capacity: 6 * Self.maximumBevels)
        bevels.initialize(repeating: 0, count: 6 * Self.maximumBevels)
        bevelAreas = .allocate(capacity: Self.maximumBevels)
        bevelAreas.initialize(repeating: 0, count: Self.maximumBevels)
        colors = .allocate(capacity: Self.maximumSegments)
        colors.initialize(repeating: .opaqueBlack, count: Self.maximumSegments)
    }

    deinit {
        let p = Self.maximumPoints
        xs.deinitialize(count: p); xs.deallocate()
        ys.deinitialize(count: p); ys.deallocate()
        rectangles.deinitialize(count: 8 * Self.maximumSegments); rectangles.deallocate()
        bevels.deinitialize(count: 6 * Self.maximumBevels); bevels.deallocate()
        bevelAreas.deinitialize(count: Self.maximumBevels); bevelAreas.deallocate()
        colors.deinitialize(count: Self.maximumSegments); colors.deallocate()
    }

    // Storage introspection for the allocation tests (VIS-003-S3).
    var storageAddresses: [UInt] {
        [UInt(bitPattern: xs), UInt(bitPattern: ys), UInt(bitPattern: rectangles), UInt(bitPattern: bevels),
         UInt(bitPattern: bevelAreas), UInt(bitPattern: colors)] + trigger.storageAddresses
    }

    public var segmentCount: Int { max(pointCount - 1, 0) }
    private var bevelCount: Int { max(pointCount - 2, 0) }

    /// Point `j` of the last layout, in pixels.
    public func point(_ j: Int) -> (x: Double, y: Double) { (xs[j], ys[j]) }

    /// Triggers on `samples` (the history, oldest first) and lays out the window for a
    /// `width × height` output.
    public func layout(samples: UnsafeBufferPointer<Float>, width: Int, height: Int) {
        lastTrigger = trigger.locate(in: samples, windowSamples: configuration.windowSamples)
        layout(samples: samples, start: lastTrigger.start, width: width, height: height)
    }

    /// Lays out the window starting at the fractional history index `start` (no trigger).
    public func layout(samples: UnsafeBufferPointer<Float>, start: Double, width: Int, height: Int) {
        let c = configuration
        self.width = max(width, 0)
        self.height = max(height, 0)
        generation &+= 1
        guard self.width > 0, self.height > 0 else {
            pointCount = 0
            return
        }
        let w = c.windowSamples
        let p = min(max(w, 2), Self.maximumPoints)
        pointCount = p
        if p - 1 != colorCount || c.palette != colorPalette {
            for k in 0..<(p - 1) { colors[k] = c.palette.color(bar: k, of: p - 1) }
            colorCount = p - 1
            colorPalette = c.palette
        }
        let fw = Double(self.width), fh = Double(self.height)
        let half: Double = fh / 2
        let reach: Double = c.amplitude * half
        let sampleStep: Double = Double(w - 1) / Double(p - 1)
        let xStep: Double = fw / Double(p - 1)
        for j in 0..<p {
            let raw = WaveformTrigger.interpolate(samples, start + Double(j) * sampleStep)
            let s: Double = raw.isFinite ? Double(min(max(raw, -1), 1)) : 0
            xs[j] = j == p - 1 ? fw : Double(j) * xStep
            ys[j] = half - s * reach
        }
        let t: Double = max(c.lineThickness * min(fw, fh), 1)
        thicknessPixels = t
        let h: Double = t / 2
        // Rectangles: corners a + n, b + n, b − n, a − n with n the unit normal × T/2.
        for k in 0..<(p - 1) {
            let dx: Double = xs[k + 1] - xs[k], dy: Double = ys[k + 1] - ys[k]
            let length: Double = (dx * dx + dy * dy).squareRoot()
            let nx: Double = -dy / length * h, ny: Double = dx / length * h
            let r = rectangles + 8 * k
            r[0] = xs[k] + nx; r[1] = ys[k] + ny
            r[2] = xs[k + 1] + nx; r[3] = ys[k + 1] + ny
            r[4] = xs[k + 1] - nx; r[5] = ys[k + 1] - ny
            r[6] = xs[k] - nx; r[7] = ys[k] - ny
        }
        // Bevels at points 1…P−2: the point and the two rectangles' corners on the outer side.
        for j in 0..<max(p - 2, 0) {
            let before = rectangles + 8 * j, after = rectangles + 8 * (j + 1)
            let d0x: Double = xs[j + 1] - xs[j], d0y: Double = ys[j + 1] - ys[j]
            let d1x: Double = xs[j + 2] - xs[j + 1], d1y: Double = ys[j + 2] - ys[j + 1]
            let turn: Double = d0x * d1y - d0y * d1x
            let b = bevels + 6 * j
            b[0] = xs[j + 1]; b[1] = ys[j + 1]
            // Turning toward +n leaves the gap on the −n side (corners 2 of `before`, 3 of `after`).
            if turn > 0 {
                b[2] = before[4]; b[3] = before[5]; b[4] = after[6]; b[5] = after[7]
            } else {
                b[2] = before[2]; b[3] = before[3]; b[4] = after[0]; b[5] = after[1]
            }
            let twice: Double = (b[2] - b[0]) * (b[5] - b[1]) - (b[4] - b[0]) * (b[3] - b[1])
            let area: Double = abs(twice) / 2
            bevelAreas[j] = area > 1e-9 ? area : 0
        }
    }

    /// Two triangles per rectangle, one per bevel with an area (whole shapes only, at most
    /// `capacity` vertices); returns the vertex count. `gain` scales colors.
    public func tessellate(into out: UnsafeMutablePointer<SpectrumVertex>, capacity: Int, gain: Float) -> Int {
        guard width > 0, height > 0, pointCount >= 2 else { return 0 }
        let sx: Double = 2 / Double(width), sy: Double = 2 / Double(height)
        @inline(__always) func vertex(_ x: Double, _ y: Double, _ color: LinearColor) -> SpectrumVertex {
            // NDC: x = 2·px/W − 1, y = 1 − 2·py/H.
            SpectrumVertex(x: Float(x * sx - 1), y: Float(1 - y * sy), color: color, gain: gain)
        }
        var count = 0
        for k in 0..<segmentCount {
            guard count + 6 <= capacity else { return count }
            let r = rectangles + 8 * k
            let color = colors[k]
            let a = vertex(r[0], r[1], color), b = vertex(r[2], r[3], color)
            let c = vertex(r[4], r[5], color), d = vertex(r[6], r[7], color)
            out[count] = a; out[count + 1] = b; out[count + 2] = c
            out[count + 3] = a; out[count + 4] = c; out[count + 5] = d
            count += 6
        }
        for j in 0..<bevelCount where bevelAreas[j] > 0 {
            guard count + 3 <= capacity else { return count }
            let b = bevels + 6 * j
            let color = colors[j]
            out[count] = vertex(b[0], b[1], color)
            out[count + 1] = vertex(b[2], b[3], color)
            out[count + 2] = vertex(b[4], b[5], color)
            count += 3
        }
        return count
    }

    /// The frame's levels in the strobe safety envelope's 17 areas (FX-019-R4) when drawn with `gain`
    /// and passed through `transfer`. No allocation.
    public func meanLevels<Transfer: FrameLuminanceTransfer>(gain: Float, transfer: Transfer,
                                                             into out: UnsafeMutableBufferPointer<FlashLevels>) {
        flashAreas.levels(of: self, generation: generation, gain: gain, transfer: transfer, into: out)
    }
}

// MARK: - The envelope's region model (FX-019-R4; VIS-003-R9)

extension OscilloscopeLayout: FlashRegionLayout {
    /// Rectangles 0…S−1, then bevels.
    var flashRegionCount: Int { segmentCount + bevelCount }
    var flashBackground: LinearColor { configuration.background }

    func flashRegionArea(_ k: Int) -> Double {
        let s = segmentCount
        if k < s {
            let dx: Double = xs[k + 1] - xs[k], dy: Double = ys[k + 1] - ys[k]
            return (dx * dx + dy * dy).squareRoot() * thicknessPixels
        }
        return bevelAreas[k - s]
    }

    func flashRegionColor(_ k: Int) -> LinearColor {
        let s = segmentCount
        return colors[k < s ? k : k - s]
    }

    func forEachFlashQuad(ofRegion k: Int,
                          _ body: (Double, Double, Double, Double, Double, Double, Double, Double) -> Void) {
        let s = segmentCount
        if k < s {
            let r = rectangles + 8 * k
            body(r[0], r[1], r[2], r[3], r[4], r[5], r[6], r[7])
        } else if bevelAreas[k - s] > 0 {
            let b = bevels + 6 * (k - s)
            body(b[0], b[1], b[2], b[3], b[4], b[5], b[4], b[5])
        }
    }
}
