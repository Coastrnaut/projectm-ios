// LinearSpectrumLayout.swift — the linear spectrum's geometry on the CPU (VIS-002-R2 to R8;
// research VIS-002-D2 to D4; data-model.md).
//
// Screen model: the output is W × H pixels, y down. Geometry is computed on two axes: the cross
// axis (C pixels; slots side by side) and the length axis (L pixels; bars grow along it), then
// mapped: vertical x = cross, y = H − length (bars rise from the bottom edge, band 0 at the left);
// horizontal x = length, y = cross (bars grow from the left edge, band 0 at the top). Turning the
// device changes W and H only.
//
// Bar k (displayed value v ∈ 0…1) occupies the centred (1 − s) of slot k = [k·C/N, (k+1)·C/N) and
// runs from 0 to v·λ·L along the length axis. Its cap, drawn only when the peak P > 0 and t > 0,
// runs from P·λ·L to P·λ·L + t·L. With λ ≤ 1 − t and P ≥ v, bar and cap never overlap and always
// fit the output (bounded height). Every rectangle is drawn as two triangles (6 vertices) in
// normalized device coordinates with premultiplied colors; caps have their bar's color.
//
// The strobe safety envelope (FX-019-R4, R9): the regions are the N bars then the N caps, flat
// rectangles over the background; `SpectrumFlashAreas` clips them exactly to the 4 × 4 tiles.
//
// Real-time safety (Constitution VII): all per-bar storage is allocated in `init`; `layout`,
// `tessellate` and `meanLevels` only touch it. Not Sendable: one owner.
import FlashSafety

/// An axis-aligned rectangle in pixels (y down).
public struct PixelRect: Sendable, Equatable {
    public var minX: Double
    public var minY: Double
    public var maxX: Double
    public var maxY: Double

    public init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
    }

    public var width: Double { maxX - minX }
    public var height: Double { maxY - minY }
    public var area: Double { width * height }
}

/// One bar's geometry on the two axes, in pixels.
public struct LinearBarGeometry: Sendable, Equatable {
    public var crossStart: Double
    public var crossEnd: Double
    /// v·λ·L.
    public var length: Double
    /// P·λ·L.
    public var capStart: Double
    /// capStart + t·L, or capStart when no cap is drawn.
    public var capEnd: Double
    /// Linear, before any gain.
    public var color: LinearColor

    public init(crossStart: Double = 0, crossEnd: Double = 0, length: Double = 0, capStart: Double = 0,
                capEnd: Double = 0, color: LinearColor = .opaqueBlack) {
        self.crossStart = crossStart
        self.crossEnd = crossEnd
        self.length = length
        self.capStart = capStart
        self.capEnd = capEnd
        self.color = color
    }

    public var isLit: Bool { length > 0 && crossEnd > crossStart }
    public var hasCap: Bool { capEnd > capStart && crossEnd > crossStart }
}

public final class LinearSpectrumLayout: FlashAreaLevelSource {
    /// Two rectangles (bar and cap) of 6 vertices per bar.
    public static let maximumVertexCount = SpectrumBarCount.maximum * 12

    private let bars: UnsafeMutablePointer<LinearBarGeometry>
    private let values: UnsafeMutablePointer<Float>
    private let colors: UnsafeMutablePointer<LinearColor>
    private let peaks = PeakCapTracker()
    /// FX-019: the envelope's area levels; bars and caps are separate regions.
    private let flashAreas = SpectrumFlashAreas(regionCapacity: 2 * SpectrumBarCount.maximum)
    private var generation = 0

    /// Always clamped; a new palette or bar count recomputes the colors, a new bar count or
    /// orientation resets the caps (no allocation).
    public var configuration: LinearSpectrumConfiguration {
        didSet {
            configuration = configuration.clamped()
            if configuration.palette != oldValue.palette || configuration.barCount != oldValue.barCount { updateColors() }
            if configuration.barCount != oldValue.barCount || configuration.orientation != oldValue.orientation { peaks.reset() }
            peaks.holdSeconds = configuration.peakHoldSeconds
            peaks.fallPerSecond = configuration.peakFallPerSecond
        }
    }

    public private(set) var width = 0
    public private(set) var height = 0

    public init(configuration: LinearSpectrumConfiguration = LinearSpectrumConfiguration()) {
        self.configuration = configuration.clamped()
        let n = SpectrumBarCount.maximum
        bars = .allocate(capacity: n)
        bars.initialize(repeating: LinearBarGeometry(), count: n)
        values = .allocate(capacity: n)
        values.initialize(repeating: 0, count: n)
        colors = .allocate(capacity: n)
        colors.initialize(repeating: .opaqueBlack, count: n)
        peaks.holdSeconds = self.configuration.peakHoldSeconds
        peaks.fallPerSecond = self.configuration.peakFallPerSecond
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
    private var vertical: Bool { configuration.orientation == .vertical }

    /// Bar `k` of the last layout (k < barCount).
    public func bar(_ k: Int) -> LinearBarGeometry { bars[k] }

    /// The sanitized value bar `k` was laid out with.
    public func value(ofBar k: Int) -> Float { values[k] }

    /// Bar `k`'s cap position (its peak), 0…1.
    public func peak(ofBar k: Int) -> Double { peaks.peak(k) }

    /// Every cap back to 0 (the host's loop restart).
    public func resetPeaks() { peaks.reset() }

    /// Lays out `barCount` bars for an output of `width × height` pixels and advances the caps by
    /// `frameTime` seconds (clamped to 0…0.1). `bands[k]` drives bar k; missing bands read 0, extra
    /// ones are ignored.
    public func layout(values bands: UnsafeBufferPointer<Float>, frameTime: Double, width: Int, height: Int) {
        let c = configuration
        let n = c.barCount.rawValue
        self.width = max(width, 0)
        self.height = max(height, 0)
        for k in 0..<n { values[k] = k < bands.count ? sanitizedBandValue(bands[k]) : 0 }
        peaks.update(values: UnsafeBufferPointer(start: values, count: n), count: n, frameTime: frameTime)
        let cross = Double(vertical ? self.width : self.height)
        let axis = Double(vertical ? self.height : self.width)
        let pitch = cross / Double(n)
        let inset = c.spacing * pitch / 2
        let full = c.lengthScale * axis
        let cap = c.capThickness * axis
        generation &+= 1
        for k in 0..<n {
            let start = Double(k) * pitch + inset
            let peakStart = peaks.peak(k) * full
            bars[k] = LinearBarGeometry(crossStart: start, crossEnd: start + (1 - c.spacing) * pitch,
                                        length: Double(values[k]) * full, capStart: peakStart,
                                        capEnd: peaks.peak(k) > 0 ? peakStart + cap : peakStart, color: colors[k])
        }
    }

    /// Array convenience (tests and callers off the frame path).
    public func layout(_ bands: [Float], frameTime: Double, width: Int, height: Int) {
        bands.withUnsafeBufferPointer { layout(values: $0, frameTime: frameTime, width: width, height: height) }
    }

    /// A span on the two axes as a pixel rectangle.
    @inline(__always)
    private func rect(cross c0: Double, _ c1: Double, length l0: Double, _ l1: Double) -> PixelRect {
        vertical ? PixelRect(minX: c0, minY: Double(height) - l1, maxX: c1, maxY: Double(height) - l0)
                 : PixelRect(minX: l0, minY: c0, maxX: l1, maxY: c1)
    }

    /// Bar `k`'s bar and cap rectangles in pixels; nil when not drawn.
    public func rectangles(ofBar k: Int) -> (bar: PixelRect?, cap: PixelRect?) {
        let b = bars[k]
        return (b.isLit ? rect(cross: b.crossStart, b.crossEnd, length: 0, b.length) : nil,
                b.hasCap ? rect(cross: b.crossStart, b.crossEnd, length: b.capStart, b.capEnd) : nil)
    }

    /// Writes two triangles per drawn rectangle (each bar, then its cap; whole rectangles only, at
    /// most `capacity` vertices) and returns the vertex count. `gain` scales colors.
    public func tessellate(into out: UnsafeMutablePointer<SpectrumVertex>, capacity: Int, gain: Float) -> Int {
        guard width > 0, height > 0 else { return 0 }
        let sx = 2 / Double(width), sy = 2 / Double(height)
        var count = 0
        func emit(_ r: PixelRect, _ color: LinearColor) {
            guard count + 6 <= capacity else { return }
            // NDC: x = 2·px/W − 1, y = 1 − 2·py/H.
            let x0 = Float(r.minX * sx - 1), x1 = Float(r.maxX * sx - 1)
            let y0 = Float(1 - r.minY * sy), y1 = Float(1 - r.maxY * sy)
            let a = SpectrumVertex(x: x0, y: y0, color: color, gain: gain), b = SpectrumVertex(x: x1, y: y0, color: color, gain: gain)
            let c = SpectrumVertex(x: x1, y: y1, color: color, gain: gain), d = SpectrumVertex(x: x0, y: y1, color: color, gain: gain)
            out[count] = a; out[count + 1] = b; out[count + 2] = c
            out[count + 3] = a; out[count + 4] = c; out[count + 5] = d
            count += 6
        }
        for k in 0..<barCount {
            let r = rectangles(ofBar: k)
            if let bar = r.bar { emit(bar, bars[k].color) }
            if let cap = r.cap { emit(cap, bars[k].color) }
        }
        return count
    }

    /// The frame's levels in the strobe safety envelope's 17 areas (FX-019-R4) when drawn with
    /// `gain` and passed through `transfer`. No allocation.
    public func meanLevels<Transfer: FrameLuminanceTransfer>(gain: Float, transfer: Transfer,
                                                             into out: UnsafeMutableBufferPointer<FlashLevels>) {
        flashAreas.levels(of: self, generation: generation, gain: gain, transfer: transfer, into: out)
    }
}

// MARK: - The envelope's region model (FX-019-R4; VIS-002-D4)

extension LinearSpectrumLayout: FlashRegionLayout {
    /// Regions 0…N−1 are the bars, N…2N−1 their caps.
    var flashRegionCount: Int { 2 * barCount }
    var flashBackground: LinearColor { configuration.background }

    private func flashRect(_ k: Int) -> PixelRect? {
        let n = barCount
        return k < n ? rectangles(ofBar: k).bar : rectangles(ofBar: k - n).cap
    }

    func flashRegionArea(_ k: Int) -> Double { flashRect(k)?.area ?? 0 }

    func flashRegionColor(_ k: Int) -> LinearColor { bars[k < barCount ? k : k - barCount].color }

    func forEachFlashQuad(ofRegion k: Int,
                          _ body: (Double, Double, Double, Double, Double, Double, Double, Double) -> Void) {
        guard let r = flashRect(k) else { return }
        body(r.minX, r.minY, r.maxX, r.minY, r.maxX, r.maxY, r.minX, r.maxY)
    }
}
