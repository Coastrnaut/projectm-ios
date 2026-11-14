// LissajousLayout.swift — the Lissajous scope's geometry on the CPU (VIS-004-R3 to R9, R13, R17; research
// VIS-004-D2 to D5; contracts/lissajous-scope.md C2).
//
// Per frame: the newest `windowFrames` stereo frames (interleaved L, R, oldest first; missing frames and
// non-finite samples read 0, samples clamped to ±1) are mapped by the plot mode, the window's peak
// |coordinate| drives `LissajousAutoGain`, and each point is (u, v) = mapped / level clamped to ±1, drawn at
// (W/2 + u·r, H/2 − v·r) with r = 0.9 × min(W, H)/2 (screen model W × H pixels, y down). The trace is 1,023
// flat rectangles (thickness T = max(thickness × the shorter side, 1 px), butt ends, no joins; a zero-length
// segment is not drawn), segment k in palette color k of 1,023 (oldest to newest). Silence (peak < 0.0001)
// draws no trace.
//
// Persistence (VIS-004-R8): with a half-life h > 0, a snapshot of 128 of the trace's normalized points is
// taken whenever h/2 of frame time passed since the newest one (never in silence), at most 8, each drawn
// behind the trace, oldest first, with its colors' alpha = w = (0.5^(age / h) − 1/16) / (15/16) (premultiplied
// when tessellated): a half-life decay shifted to reach 0 at age 4h, where the snapshot is dropped. (A snapshot
// retraces a steady shape about 10 times, so its coverage builds up like a phosphor's; unshifted, a circle's
// ghost still covered about half its pixels at the cut and vanished with a pop.) Frame time is the sum of the clamped frame durations (no wall clock).
// A mode change, h = 0 and `reset()` clear the snapshots.
//
// The strobe safety envelope (FX-019-R4, R9): regions are the snapshots' segments (oldest first), then the
// trace's; each region's color carries its weight as alpha. Regions overlap where the trace crosses itself
// or a ghost: the light is counted twice there, an overestimate, never an underestimate.
//
// Real-time safety (Constitution VII): every buffer is allocated in `init`. Not Sendable: one owner.
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif
import FlashSafety

public final class LissajousLayout: FlashAreaLevelSource {
    /// Stereo frames plotted (≈ 23 ms at 44.1 kHz).
    public static let windowFrames = 1_024
    public static let traceSegments = windowFrames - 1
    public static let snapshotCapacity = 8
    public static let snapshotPoints = 128
    public static let snapshotSegments = snapshotPoints - 1
    /// A window whose peak |coordinate| is below this is silence (−80 dBFS).
    public static let silenceThreshold = 0.000_1
    /// The level's coordinate reaches this fraction of half the shorter side.
    public static let reach = 0.9
    /// Snapshots older than this many half-lives are dropped (weight 1/16).
    public static let snapshotLifetimeHalfLives = 4.0
    public static let maximumRegions = traceSegments + snapshotCapacity * snapshotSegments
    /// Six vertices per segment.
    public static let maximumVertexCount = maximumRegions * 6

    public var configuration: LissajousConfiguration {
        didSet {
            configuration = configuration.clamped()
            if configuration.mode != oldValue.mode || !configuration.persistenceEnabled { clearSnapshots() }
        }
    }

    public private(set) var autoGain = LissajousAutoGain()
    public private(set) var width = 0
    public private(set) var height = 0
    /// Points of the trace in the last layout (0 when silent).
    public private(set) var pointCount = 0
    public private(set) var snapshotCount = 0
    /// T in pixels of the last layout.
    public private(set) var thicknessPixels = 1.0
    /// Frame time in seconds since the last reset.
    public private(set) var clock = 0.0

    private let us: UnsafeMutablePointer<Double>
    private let vs: UnsafeMutablePointer<Double>
    private let xs: UnsafeMutablePointer<Double>
    private let ys: UnsafeMutablePointer<Double>
    /// Per region (snapshots first, then the trace): 4 corners (x, y interleaved) and the area.
    private let rectangles: UnsafeMutablePointer<Double>
    private let areas: UnsafeMutablePointer<Double>
    /// Snapshot ring: normalized points (u, v interleaved) and the time each was taken.
    private let snapshotUV: UnsafeMutablePointer<Double>
    private let snapshotTimes: UnsafeMutablePointer<Double>
    private var snapshotHead = 0   // the next slot to write
    /// Per drawn snapshot, oldest first: its weight.
    private let weights: UnsafeMutablePointer<Double>
    private let traceColors: UnsafeMutablePointer<LinearColor>
    private let snapshotColors: UnsafeMutablePointer<LinearColor>
    private var colorPalette: VisualPalette?
    private let flashAreas = SpectrumFlashAreas(regionCapacity: LissajousLayout.maximumRegions)
    private var generation = 0

    public init(configuration: LissajousConfiguration = LissajousConfiguration()) {
        self.configuration = configuration.clamped()
        let n = Self.windowFrames, regions = Self.maximumRegions
        us = .allocate(capacity: n); us.initialize(repeating: 0, count: n)
        vs = .allocate(capacity: n); vs.initialize(repeating: 0, count: n)
        xs = .allocate(capacity: n); xs.initialize(repeating: 0, count: n)
        ys = .allocate(capacity: n); ys.initialize(repeating: 0, count: n)
        rectangles = .allocate(capacity: 8 * regions); rectangles.initialize(repeating: 0, count: 8 * regions)
        areas = .allocate(capacity: regions); areas.initialize(repeating: 0, count: regions)
        let uv = 2 * Self.snapshotPoints * Self.snapshotCapacity
        snapshotUV = .allocate(capacity: uv); snapshotUV.initialize(repeating: 0, count: uv)
        snapshotTimes = .allocate(capacity: Self.snapshotCapacity)
        snapshotTimes.initialize(repeating: 0, count: Self.snapshotCapacity)
        weights = .allocate(capacity: Self.snapshotCapacity); weights.initialize(repeating: 0, count: Self.snapshotCapacity)
        traceColors = .allocate(capacity: Self.traceSegments)
        traceColors.initialize(repeating: .opaqueBlack, count: Self.traceSegments)
        snapshotColors = .allocate(capacity: Self.snapshotSegments)
        snapshotColors.initialize(repeating: .opaqueBlack, count: Self.snapshotSegments)
    }

    deinit {
        let n = Self.windowFrames, regions = Self.maximumRegions
        us.deinitialize(count: n); us.deallocate()
        vs.deinitialize(count: n); vs.deallocate()
        xs.deinitialize(count: n); xs.deallocate()
        ys.deinitialize(count: n); ys.deallocate()
        rectangles.deinitialize(count: 8 * regions); rectangles.deallocate()
        areas.deinitialize(count: regions); areas.deallocate()
        snapshotUV.deinitialize(count: 2 * Self.snapshotPoints * Self.snapshotCapacity); snapshotUV.deallocate()
        snapshotTimes.deinitialize(count: Self.snapshotCapacity); snapshotTimes.deallocate()
        weights.deinitialize(count: Self.snapshotCapacity); weights.deallocate()
        traceColors.deinitialize(count: Self.traceSegments); traceColors.deallocate()
        snapshotColors.deinitialize(count: Self.snapshotSegments); snapshotColors.deallocate()
    }

    // Storage introspection for the allocation tests (VIS-004-R17).
    var storageAddresses: [UInt] {
        [UInt(bitPattern: us), UInt(bitPattern: vs), UInt(bitPattern: xs), UInt(bitPattern: ys),
         UInt(bitPattern: rectangles), UInt(bitPattern: areas), UInt(bitPattern: snapshotUV),
         UInt(bitPattern: snapshotTimes), UInt(bitPattern: weights), UInt(bitPattern: traceColors),
         UInt(bitPattern: snapshotColors)]
    }

    /// The loop restart: gain, snapshots and the frame clock start afresh.
    public func reset() {
        autoGain.reset()
        clearSnapshots()
        clock = 0
    }

    private func clearSnapshots() {
        snapshotCount = 0
        snapshotHead = 0
    }

    public var segmentCount: Int { max(pointCount - 1, 0) }
    private var snapshotRegionCount: Int { snapshotCount * Self.snapshotSegments }

    /// Point `j` of the trace in pixels (y down).
    public func point(_ j: Int) -> (x: Double, y: Double) { (xs[j], ys[j]) }
    /// Point `j` of the trace normalized (−1…1, y up).
    public func normalizedPoint(_ j: Int) -> (u: Double, v: Double) { (us[j], vs[j]) }
    /// Weight of drawn snapshot `i` (0 = oldest) in the last layout.
    public func snapshotWeight(_ i: Int) -> Double { weights[i] }
    /// Age in seconds of drawn snapshot `i` (0 = oldest) in the last layout.
    public func snapshotAge(_ i: Int) -> Double { clock - snapshotTimes[slot(i)] }

    private func slot(_ i: Int) -> Int {
        (snapshotHead - snapshotCount + i + 2 * Self.snapshotCapacity) % Self.snapshotCapacity
    }

    /// Lays out the newest window of `stereo` (interleaved L, R, oldest first) for a `width × height`
    /// output after a frame lasting `frameDuration` seconds.
    public func layout(stereo: UnsafeBufferPointer<Float>, frameDuration: Double, width: Int, height: Int) {
        let c = configuration
        let dt: Double = LissajousAutoGain.clampedDuration(frameDuration)
        clock += dt
        generation &+= 1
        self.width = max(width, 0)
        self.height = max(height, 0)
        refreshColors(c.palette)
        let h: Double = c.persistenceHalfLife
        pruneSnapshots(halfLife: h)
        let peak: Double = mapWindow(stereo, mode: c.mode)
        let level: Double = autoGain.update(peak: peak, frameDuration: dt)
        let silent: Bool = !(peak >= Self.silenceThreshold)
        pointCount = silent ? 0 : Self.windowFrames
        if !silent {
            let scale: Double = 1 / level
            for j in 0..<Self.windowFrames {
                us[j] = min(max(us[j] * scale, -1), 1)
                vs[j] = min(max(vs[j] * scale, -1), 1)
            }
            if h > 0, snapshotCount == 0 || clock - newestSnapshotTime >= h / 2 - 1e-12 { takeSnapshot() }
        }
        for i in 0..<snapshotCount {
            let age: Double = clock - snapshotTimes[slot(i)]
            weights[i] = Self.snapshotWeight(age: age, halfLife: h)
        }
        guard self.width > 0, self.height > 0 else {
            pointCount = 0   // nothing is drawn at size 0; the snapshots are kept
            return
        }
        buildGeometry()
    }

    /// The weight of a snapshot `age` seconds old: (0.5^(age / h) − 1/16) / (15/16), 0 from 4 half-lives.
    public static func snapshotWeight(age: Double, halfLife h: Double) -> Double {
        guard h > 0, age.isFinite else { return 0 }
        let tail: Double = pow(0.5, snapshotLifetimeHalfLives)
        let w: Double = (pow(0.5, max(age, 0) / h) - tail) / (1 - tail)
        return min(max(w, 0), 1)
    }

    private var newestSnapshotTime: Double {
        snapshotTimes[(snapshotHead - 1 + Self.snapshotCapacity) % Self.snapshotCapacity]
    }

    private func refreshColors(_ palette: VisualPalette) {
        guard palette != colorPalette else { return }
        for k in 0..<Self.traceSegments { traceColors[k] = palette.color(bar: k, of: Self.traceSegments) }
        for k in 0..<Self.snapshotSegments { snapshotColors[k] = palette.color(bar: k, of: Self.snapshotSegments) }
        colorPalette = palette
    }

    private func pruneSnapshots(halfLife h: Double) {
        guard h > 0 else {
            clearSnapshots()
            return
        }
        let lifetime: Double = Self.snapshotLifetimeHalfLives * h
        while snapshotCount > 0, clock - snapshotTimes[slot(0)] >= lifetime - 1e-12 { snapshotCount -= 1 }
    }

    /// Fills `us`/`vs` with the mapped window (not yet scaled) and returns its peak |coordinate|.
    private func mapWindow(_ stereo: UnsafeBufferPointer<Float>, mode: LissajousMode) -> Double {
        let n = Self.windowFrames
        let frames: Int = stereo.count / 2
        var peak: Double = 0
        for j in 0..<n {
            let index: Int = frames - n + j
            var l: Double = 0, r: Double = 0
            if index >= 0 {
                l = Self.sanitized(stereo[2 * index])
                r = Self.sanitized(stereo[2 * index + 1])
            }
            let p = mode.map(left: l, right: r)
            us[j] = p.x
            vs[j] = p.y
            peak = max(peak, abs(p.x), abs(p.y))
        }
        return peak
    }

    @inline(__always)
    private static func sanitized(_ s: Float) -> Double {
        s.isFinite ? Double(min(max(s, -1), 1)) : 0
    }

    private func takeSnapshot() {
        let base = snapshotUV + 2 * Self.snapshotPoints * snapshotHead
        let last = Self.windowFrames - 1
        for i in 0..<Self.snapshotPoints {
            let j: Int = i * last / (Self.snapshotPoints - 1)
            base[2 * i] = us[j]
            base[2 * i + 1] = vs[j]
        }
        snapshotTimes[snapshotHead] = clock
        snapshotHead = (snapshotHead + 1) % Self.snapshotCapacity
        snapshotCount = min(snapshotCount + 1, Self.snapshotCapacity)
    }

    private func buildGeometry() {
        let fw = Double(width), fh = Double(height)
        let shorter: Double = min(fw, fh)
        let r: Double = Self.reach * shorter / 2
        let cx: Double = fw / 2, cy: Double = fh / 2
        let t: Double = max(configuration.lineThickness * shorter, 1)
        thicknessPixels = t
        for j in 0..<pointCount {
            xs[j] = cx + us[j] * r
            ys[j] = cy - vs[j] * r
        }
        var region = 0
        for i in 0..<snapshotCount {
            let base = snapshotUV + 2 * Self.snapshotPoints * slot(i)
            for k in 0..<Self.snapshotSegments {
                let ax: Double = cx + base[2 * k] * r, ay: Double = cy - base[2 * k + 1] * r
                let bx: Double = cx + base[2 * k + 2] * r, by: Double = cy - base[2 * k + 3] * r
                setRectangle(region, ax, ay, bx, by, half: t / 2)
                region += 1
            }
        }
        for k in 0..<segmentCount {
            setRectangle(region, xs[k], ys[k], xs[k + 1], ys[k + 1], half: t / 2)
            region += 1
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

    /// Two triangles per drawn region (snapshots oldest first, then the trace; whole shapes only, at most
    /// `capacity` vertices); returns the vertex count. `gain` scales colors.
    public func tessellate(into out: UnsafeMutablePointer<SpectrumVertex>, capacity: Int, gain: Float) -> Int {
        guard width > 0, height > 0 else { return 0 }
        let sx: Double = 2 / Double(width), sy: Double = 2 / Double(height)
        var count = 0
        for k in 0..<flashRegionCount where areas[k] > 0 {
            guard count + 6 <= capacity else { return count }
            let q = rectangles + 8 * k
            let color = flashRegionColor(k)
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

// MARK: - The envelope's region model (FX-019-R4; VIS-004-R13)

extension LissajousLayout: FlashRegionLayout {
    /// Snapshot segments (oldest first), then the trace's.
    var flashRegionCount: Int { snapshotRegionCount + segmentCount }
    var flashBackground: LinearColor { configuration.background }

    func flashRegionArea(_ k: Int) -> Double { areas[k] }

    func flashRegionColor(_ k: Int) -> LinearColor {
        let s = snapshotRegionCount
        if k >= s { return traceColors[k - s] }
        var color = snapshotColors[k % Self.snapshotSegments]
        color.alpha = Float(weights[k / Self.snapshotSegments])
        return color
    }

    func forEachFlashQuad(ofRegion k: Int,
                          _ body: (Double, Double, Double, Double, Double, Double, Double, Double) -> Void) {
        guard areas[k] > 0 else { return }
        let q = rectangles + 8 * k
        body(q[0], q[1], q[2], q[3], q[4], q[5], q[6], q[7])
    }
}
