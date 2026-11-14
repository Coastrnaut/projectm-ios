// RadialWaveformLayout.swift — the radial waveform's geometry on the CPU (VIS-005-R2 to R8, R14; research
// VIS-005-D2 to D4; contracts/radial-waveform.md C1).
//
// Per frame: the newest `inputSamples` (N + k = 1,280) of the mono history (oldest first; missing samples
// and non-finite ones read 0, samples clamped to ±1) give the window x[k]…x[k + N − 1]. No seam (VIS-005-R4):
// the last k = 256 window points are crossfaded into the k samples that precede the window,
// s_j = (1 − c)·x[k + j] + c·x[j + k − N] with raised-cosine c = ½ − ½·cos(π(j − (N − k) + ½)/k), so the
// newest point ends beside x[k − 1], the sample just before the oldest point x[k]; the closing segment is an
// ordinary step. The weights sum to 1, so a constant stays exactly constant. VIS-004's `LissajousAutoGain`
// scales the tapered window by its peak |s|; silence (peak < 0.0001) gives s = 0, the base circle.
//
// Point j lies at θ_j = 2π·j/N clockwise from the top, radius r_j = R₀ + A·s_j (fractions of half the
// shorter side; screen model W × H pixels, y down): (W/2 + r_j·R·sin θ_j, H/2 − r_j·R·cos θ_j), R =
// min(W, H)/2. The ring is N flat rectangles (thickness T = max(thickness × the shorter side, 1 px), butt
// ends, no joins; a zero-length segment is not drawn), segment j from point j to point (j + 1) mod N — the
// last one closes the ring — in palette color j of N (oldest to newest).
//
// The strobe safety envelope (FX-019-R4, R9): regions are the segments; neighbours overlap a little on a
// turn's inner side, where the light is counted twice: an overestimate, never an underestimate.
//
// Real-time safety (Constitution VII): every buffer (and the sine, cosine and taper tables) is allocated in
// `init`. Not Sendable: one owner.
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif
import FlashSafety

public final class RadialWaveformLayout: FlashAreaLevelSource {
    /// N: samples (and points) around the ring (≈ 23 ms at 44.1 kHz).
    public static let windowSamples = 1_024
    /// k: points crossfaded at the seam.
    public static let taperSamples = 256
    /// Samples read from the history: the window and the k before it.
    public static let inputSamples = windowSamples + taperSamples
    public static let segmentCapacity = windowSamples
    /// A window whose peak |s| is below this is silence (−80 dBFS).
    public static let silenceThreshold = 0.000_1
    /// Six vertices per segment.
    public static let maximumVertexCount = segmentCapacity * 6

    public var configuration: RadialWaveformConfiguration {
        didSet { configuration = configuration.clamped() }
    }

    /// The seam crossfade (VIS-005-R4). Tests turn it off for the negative control; the app never does.
    var taperEnabled = true

    public private(set) var autoGain = LissajousAutoGain()
    public private(set) var width = 0
    public private(set) var height = 0
    /// Points of the last layout (N, or 0 at size 0).
    public private(set) var pointCount = 0
    /// T in pixels of the last layout.
    public private(set) var thicknessPixels = 1.0
    /// The last window's peak |s| before the gain.
    public private(set) var lastPeak = 0.0

    private let raw: UnsafeMutablePointer<Double>        // N + k sanitized samples
    private let samples: UnsafeMutablePointer<Double>    // N tapered, normalized samples (−1…1)
    private let radii: UnsafeMutablePointer<Double>      // N radii (fractions of R)
    private let xs: UnsafeMutablePointer<Double>
    private let ys: UnsafeMutablePointer<Double>
    private let sines: UnsafeMutablePointer<Double>
    private let cosines: UnsafeMutablePointer<Double>
    private let taper: UnsafeMutablePointer<Double>      // k crossfade weights c
    /// Per segment: 4 corners (x, y interleaved), and its area.
    private let rectangles: UnsafeMutablePointer<Double>
    private let areas: UnsafeMutablePointer<Double>
    private let colors: UnsafeMutablePointer<LinearColor>
    private var colorPalette: VisualPalette?
    private let flashAreas = SpectrumFlashAreas(regionCapacity: RadialWaveformLayout.segmentCapacity)
    private var generation = 0

    public init(configuration: RadialWaveformConfiguration = RadialWaveformConfiguration()) {
        self.configuration = configuration.clamped()
        let n = Self.windowSamples, k = Self.taperSamples, input = Self.inputSamples
        raw = .allocate(capacity: input); raw.initialize(repeating: 0, count: input)
        samples = .allocate(capacity: n); samples.initialize(repeating: 0, count: n)
        radii = .allocate(capacity: n); radii.initialize(repeating: 0, count: n)
        xs = .allocate(capacity: n); xs.initialize(repeating: 0, count: n)
        ys = .allocate(capacity: n); ys.initialize(repeating: 0, count: n)
        sines = .allocate(capacity: n); cosines = .allocate(capacity: n)
        for j in 0..<n {
            let theta: Double = 2 * Double.pi * Double(j) / Double(n)
            (sines + j).initialize(to: sin(theta))
            (cosines + j).initialize(to: cos(theta))
        }
        taper = .allocate(capacity: k)
        for i in 0..<k {
            let phase: Double = Double.pi * (Double(i) + 0.5) / Double(k)
            (taper + i).initialize(to: 0.5 - 0.5 * cos(phase))
        }
        rectangles = .allocate(capacity: 8 * n); rectangles.initialize(repeating: 0, count: 8 * n)
        areas = .allocate(capacity: n); areas.initialize(repeating: 0, count: n)
        colors = .allocate(capacity: n); colors.initialize(repeating: .opaqueBlack, count: n)
    }

    deinit {
        let n = Self.windowSamples
        raw.deinitialize(count: Self.inputSamples); raw.deallocate()
        samples.deinitialize(count: n); samples.deallocate()
        radii.deinitialize(count: n); radii.deallocate()
        xs.deinitialize(count: n); xs.deallocate()
        ys.deinitialize(count: n); ys.deallocate()
        sines.deinitialize(count: n); sines.deallocate()
        cosines.deinitialize(count: n); cosines.deallocate()
        taper.deinitialize(count: Self.taperSamples); taper.deallocate()
        rectangles.deinitialize(count: 8 * n); rectangles.deallocate()
        areas.deinitialize(count: n); areas.deallocate()
        colors.deinitialize(count: n); colors.deallocate()
    }

    // Storage introspection for the allocation tests (VIS-005-R14).
    var storageAddresses: [UInt] {
        [UInt(bitPattern: raw), UInt(bitPattern: samples), UInt(bitPattern: radii), UInt(bitPattern: xs),
         UInt(bitPattern: ys), UInt(bitPattern: sines), UInt(bitPattern: cosines), UInt(bitPattern: taper),
         UInt(bitPattern: rectangles), UInt(bitPattern: areas), UInt(bitPattern: colors)]
    }

    /// The loop restart: the gain starts afresh.
    public func reset() {
        autoGain.reset()
    }

    /// Segments drawn in the last layout (N, closing segment included; 0 at size 0).
    public var segmentCount: Int { pointCount }

    /// Point `j` of the last layout, in pixels (y down).
    public func point(_ j: Int) -> (x: Double, y: Double) { (xs[j], ys[j]) }
    /// Tapered, gain-normalized sample `j` (−1…1) of the last layout.
    public func normalizedSample(_ j: Int) -> Double { samples[j] }
    /// Radius of point `j` as a fraction of half the shorter side.
    public func radius(_ j: Int) -> Double { radii[j] }

    /// Lays out the newest window of the mono history `history` (oldest first) for a `width × height`
    /// output after a frame lasting `frameDuration` seconds.
    public func layout(samples history: UnsafeBufferPointer<Float>, frameDuration: Double, width: Int, height: Int) {
        let c = configuration
        generation &+= 1
        self.width = max(width, 0)
        self.height = max(height, 0)
        refreshColors(c.palette)
        readWindow(history)
        let peak: Double = taperWindow()
        lastPeak = peak
        let level: Double = autoGain.update(peak: peak, frameDuration: frameDuration)
        let silent: Bool = !(peak >= Self.silenceThreshold)
        let scale: Double = silent ? 0 : 1 / level
        for j in 0..<Self.windowSamples {
            let s: Double = min(max(samples[j] * scale, -1), 1)
            samples[j] = s
            radii[j] = c.baseRadius + c.amplitude * s
        }
        guard self.width > 0, self.height > 0 else {
            pointCount = 0   // nothing is drawn at size 0
            return
        }
        pointCount = Self.windowSamples
        buildGeometry()
    }

    /// Copies the newest `inputSamples` into `raw` (missing → 0, non-finite → 0, clamped to ±1).
    private func readWindow(_ history: UnsafeBufferPointer<Float>) {
        let count: Int = history.count
        for i in 0..<Self.inputSamples {
            let index: Int = count - Self.inputSamples + i
            var value: Double = 0
            if index >= 0 {
                let s: Float = history[index]
                value = s.isFinite ? Double(min(max(s, -1), 1)) : 0
            }
            raw[i] = value
        }
    }

    /// Fills `samples` with the tapered window (VIS-005-R4) and returns its peak |s|.
    private func taperWindow() -> Double {
        let n = Self.windowSamples, k = Self.taperSamples
        var peak: Double = 0
        for j in 0..<n {
            var s: Double = raw[k + j]
            if taperEnabled, j >= n - k {
                let w: Double = taper[j - (n - k)]
                s = (1 - w) * s + w * raw[j + k - n]
            }
            samples[j] = s
            peak = max(peak, abs(s))
        }
        return peak
    }

    private func refreshColors(_ palette: VisualPalette) {
        guard palette != colorPalette else { return }
        let n = Self.segmentCapacity
        for j in 0..<n { colors[j] = palette.color(bar: j, of: n) }
        colorPalette = palette
    }

    private func buildGeometry() {
        let n = Self.windowSamples
        let fw = Double(width), fh = Double(height)
        let shorter: Double = min(fw, fh)
        let big: Double = shorter / 2
        let cx: Double = fw / 2, cy: Double = fh / 2
        let t: Double = max(configuration.lineThickness * shorter, 1)
        thicknessPixels = t
        for j in 0..<n {
            let r: Double = radii[j] * big
            xs[j] = cx + r * sines[j]
            ys[j] = cy - r * cosines[j]
        }
        for j in 0..<n {
            let next: Int = j + 1 == n ? 0 : j + 1   // the last segment closes the ring
            setRectangle(j, xs[j], ys[j], xs[next], ys[next], half: t / 2)
        }
    }

    /// Region `k`: the rectangle from a to b of thickness 2 × `half`; area 0 when a = b.
    private func setRectangle(_ k: Int, _ ax: Double, _ ay: Double, _ bx: Double, _ by: Double, half: Double) {
        let dx: Double = bx - ax, dy: Double = by - ay
        let length: Double = (dx * dx + dy * dy).squareRoot()
        guard length > 1e-9 else {
            areas[k] = 0
            return
        }
        let nx: Double = -dy / length * half, ny: Double = dx / length * half
        let q = rectangles + 8 * k
        q[0] = ax + nx; q[1] = ay + ny
        q[2] = bx + nx; q[3] = by + ny
        q[4] = bx - nx; q[5] = by - ny
        q[6] = ax - nx; q[7] = ay - ny
        areas[k] = length * 2 * half
    }

    /// Two triangles per drawn segment (whole shapes only, at most `capacity` vertices); returns the vertex
    /// count. `gain` scales colors.
    public func tessellate(into out: UnsafeMutablePointer<SpectrumVertex>, capacity: Int, gain: Float) -> Int {
        guard width > 0, height > 0 else { return 0 }
        let sx: Double = 2 / Double(width), sy: Double = 2 / Double(height)
        var count = 0
        for k in 0..<segmentCount where areas[k] > 0 {
            guard count + 6 <= capacity else { return count }
            let q = rectangles + 8 * k
            let color = colors[k]
            // NDC: x = 2·px/W − 1, y = 1 − 2·py/H.
            let a = SpectrumVertex(x: Float(q[0] * sx - 1), y: Float(1 - q[1] * sy), color: color, gain: gain)
            let b = SpectrumVertex(x: Float(q[2] * sx - 1), y: Float(1 - q[3] * sy), color: color, gain: gain)
            let c = SpectrumVertex(x: Float(q[4] * sx - 1), y: Float(1 - q[5] * sy), color: color, gain: gain)
            let d = SpectrumVertex(x: Float(q[6] * sx - 1), y: Float(1 - q[7] * sy), color: color, gain: gain)
            out[count] = a; out[count + 1] = b; out[count + 2] = c
            out[count + 3] = a; out[count + 4] = c; out[count + 5] = d
            count += 6
        }
        return count
    }

    /// The frame's levels in the strobe safety envelope's 17 areas (FX-019-R4) when drawn with `gain` and
    /// passed through `transfer`. No allocation.
    public func meanLevels<Transfer: FrameLuminanceTransfer>(gain: Float, transfer: Transfer,
                                                             into out: UnsafeMutableBufferPointer<FlashLevels>) {
        flashAreas.levels(of: self, generation: generation, gain: gain, transfer: transfer, into: out)
    }
}

// MARK: - The envelope's region model (FX-019-R4; VIS-005-R8)

extension RadialWaveformLayout: FlashRegionLayout {
    var flashRegionCount: Int { segmentCount }
    var flashBackground: LinearColor { configuration.background }

    func flashRegionArea(_ k: Int) -> Double { areas[k] }

    func flashRegionColor(_ k: Int) -> LinearColor { colors[k] }

    func forEachFlashQuad(ofRegion k: Int,
                          _ body: (Double, Double, Double, Double, Double, Double, Double, Double) -> Void) {
        guard areas[k] > 0 else { return }
        let q = rectangles + 8 * k
        body(q[0], q[1], q[2], q[3], q[4], q[5], q[6], q[7])
    }
}
