// SpectrumWaterfall.swift — the spectrum waterfall's history ring, flash cells and shader text (VIS-020-R3 to R8;
// specs/267-vis-020-spectrum-waterfall, research VIS-020-D2 to D6, contracts/waterfall.md C1, C3).
//
// * `SpectrumWaterfallHistory`: a fixed ring of 512 rows × 256 columns of 8-bit levels, allocated in `init` and never
//   reallocated. One row per 117.1875 ms of the injected frame clock (60 s fill the ring exactly; 234.375 ms with Reduce
//   Motion, from the next row), in integer nanoseconds with no drift. A row is the mean of the frames whose timestamps
//   fall in its interval; intervals a frame skips repeat that frame's levels; at most 512 rows per frame; time running
//   backwards re-anchors the clock without writing. Columns are the input bands (ANL-002's log-spaced bands) linearly
//   interpolated across band index, so the axis is log-frequency at any band count. Rows written since the last
//   `drainPending` are listed so the generator copies only those to its texture.
// * `WaterfallFlashCells`: the exact mean linear colour of the history texels each of the 8 × 8 flash estimate cells
//   shows (64 ages × 32 columns), kept from per-row group sums updated only for written rows.
// * `WaterfallShader.function`: the MSL sampling the ring texture newest-at-top; `SpectrumWaterfallHistory.level(atX:…)`
//   is its CPU mirror.
// Pure Swift (every platform). Not Sendable: one thread drives a history.

public final class SpectrumWaterfallHistory {
    public static let columns = 256
    public static let rows = 512
    /// Bytes of level storage (fixed): 131,072.
    public static let byteCount = columns * rows
    /// Time the ring spans: 60 s, or 120 s with Reduce Motion (VIS-020-R4, R8).
    public static let spanNanoseconds: Int64 = 60_000_000_000
    public static let reduceMotionSpanNanoseconds: Int64 = 120_000_000_000

    /// Row-major levels (ring row × 256), 0…255. Its address never changes.
    public let levels: UnsafeMutablePointer<UInt8>
    private let sequences: UnsafeMutablePointer<Int>
    private let sum: UnsafeMutablePointer<Float>
    private let latest: UnsafeMutablePointer<Float>
    private let pendingRows: UnsafeMutablePointer<Int>
    private var pendingCount = 0
    private var allPending = true

    /// Ring index of the newest row (−1 before the first).
    public private(set) var newestRow = -1
    /// Rows written since the last `clear()`.
    public private(set) var rowsWritten = 0
    /// Frames added to the current row.
    public private(set) var framesInRow = 0
    public private(set) var reduceMotion = false
    private var anchored = false
    private var lastTime: Int64 = 0
    /// Row clock: the current row's index `rowInEpoch` (−1 allowed after a span change) ends at
    /// `epochStart + (rowInEpoch + 1) · span / 512`.
    private var epochStart: Int64 = 0
    private var rowInEpoch: Int64 = 0
    private var span: Int64 = SpectrumWaterfallHistory.spanNanoseconds

    public init() {
        levels = .allocate(capacity: Self.byteCount)
        levels.initialize(repeating: 0, count: Self.byteCount)
        sequences = .allocate(capacity: Self.rows)
        sequences.initialize(repeating: -1, count: Self.rows)
        sum = .allocate(capacity: Self.columns)
        sum.initialize(repeating: 0, count: Self.columns)
        latest = .allocate(capacity: Self.columns)
        latest.initialize(repeating: 0, count: Self.columns)
        pendingRows = .allocate(capacity: Self.rows)
        pendingRows.initialize(repeating: 0, count: Self.rows)
    }

    deinit {
        levels.deinitialize(count: Self.byteCount); levels.deallocate()
        sequences.deinitialize(count: Self.rows); sequences.deallocate()
        sum.deinitialize(count: Self.columns); sum.deallocate()
        latest.deinitialize(count: Self.columns); latest.deallocate()
        pendingRows.deinitialize(count: Self.rows); pendingRows.deallocate()
    }

    /// Empty history (every row black, clock unanchored); every row is pending so the texture is cleared too.
    public func clear() {
        levels.update(repeating: 0, count: Self.byteCount)
        sequences.update(repeating: -1, count: Self.rows)
        sum.update(repeating: 0, count: Self.columns)
        newestRow = -1
        rowsWritten = 0
        framesInRow = 0
        anchored = false
        pendingCount = 0
        allPending = true
    }

    /// Nanoseconds per row now (117,187,500 or 234,375,000).
    public var rowNanoseconds: Double { Double(span) / Double(Self.rows) }

    /// Adds one frame of `bands` (0…1, any count) at `timeNanoseconds`, committing every row whose interval ended.
    public func advance(bands: UnsafeBufferPointer<Float>, timeNanoseconds: UInt64, reduceMotion rm: Bool) {
        Self.fillColumns(from: bands, into: latest)
        let t: Int64 = Int64(clamping: timeNanoseconds)
        guard anchored, t >= lastTime else {   // first frame, or time ran backwards: re-anchor, write nothing
            anchor(t, reduceMotion: rm)
            addLatest()
            return
        }
        lastTime = t
        let row: Int64 = rowContaining(t)
        if row > rowInEpoch {
            let crossed: Int64 = row - rowInEpoch
            commit(mean: true)
            let holds: Int = Int(min(crossed - 1, Int64(Self.rows - 1)))
            for _ in 0..<holds { commit(mean: false) }
            rowInEpoch = row
            sum.update(repeating: 0, count: Self.columns)
            framesInRow = 0
        }
        if rm != reduceMotion {   // the next row uses the new step: a new epoch starts where the current row ends
            epochStart = rowEnd()
            rowInEpoch = -1
            span = rm ? Self.reduceMotionSpanNanoseconds : Self.spanNanoseconds
            reduceMotion = rm
        }
        addLatest()
    }

    private func anchor(_ t: Int64, reduceMotion rm: Bool) {
        anchored = true
        lastTime = t
        epochStart = t
        rowInEpoch = 0
        reduceMotion = rm
        span = rm ? Self.reduceMotionSpanNanoseconds : Self.spanNanoseconds
        sum.update(repeating: 0, count: Self.columns)
        framesInRow = 0
    }

    private func rowEnd() -> Int64 {
        epochStart + Int64((Double(rowInEpoch + 1) * Double(span) / Double(Self.rows)).rounded(.down))
    }

    /// Row of the epoch whose interval contains `t` (integer arithmetic while it cannot overflow).
    private func rowContaining(_ t: Int64) -> Int64 {
        if t < epochStart { return -1 }
        let elapsed: Int64 = t - epochStart
        let product = elapsed.multipliedReportingOverflow(by: Int64(Self.rows))
        if !product.overflow { return product.partialValue / span }
        return Int64((Double(elapsed) * Double(Self.rows) / Double(span)).rounded(.down))
    }

    private func addLatest() {
        for c in 0..<Self.columns { sum[c] += latest[c] }
        framesInRow += 1
    }

    /// Writes the next ring row: the current row's mean (when it has frames and `mean`), else the newest frame.
    private func commit(mean: Bool) {
        let ring: Int = (newestRow + 1) % Self.rows
        let base: UnsafeMutablePointer<UInt8> = levels + ring * Self.columns
        let n: Float = Float(framesInRow)
        let useMean: Bool = mean && framesInRow > 0
        for c in 0..<Self.columns {
            let v: Float = useMean ? sum[c] / n : latest[c]
            base[c] = Self.quantize(v)
        }
        sequences[ring] = rowsWritten
        rowsWritten += 1
        newestRow = ring
        if !allPending {
            if pendingCount < Self.rows { pendingRows[pendingCount] = ring; pendingCount += 1 } else { allPending = true }
        }
    }

    /// 0…1 → 0…255 (non-finite → 0).
    @inlinable
    public static func quantize(_ v: Float) -> UInt8 {
        guard v.isFinite else { return 0 }
        return UInt8((min(max(v, 0), 1) * 255).rounded())
    }

    /// Column c samples band position c · (n − 1) / 255, linearly interpolated; non-finite bands count as 0.
    static func fillColumns(from bands: UnsafeBufferPointer<Float>, into out: UnsafeMutablePointer<Float>) {
        let n: Int = bands.count
        guard n > 0 else { out.update(repeating: 0, count: columns); return }
        let scale: Float = n > 1 ? Float(n - 1) / Float(columns - 1) : 0
        for c in 0..<columns {
            let position: Float = Float(c) * scale
            let i: Int = min(Int(position), n - 1)
            let j: Int = min(i + 1, n - 1)
            let f: Float = position - Float(i)
            let a: Float = bands[i].isFinite ? bands[i] : 0
            let b: Float = bands[j].isFinite ? bands[j] : 0
            out[c] = min(max(a + (b - a) * f, 0), 1)
        }
    }

    // MARK: - Reading

    /// Ring index of the row `age` rows older than the newest (age 0 = newest); nil when not written.
    public func ringRow(age: Int) -> Int? {
        guard age >= 0, age < min(rowsWritten, Self.rows), newestRow >= 0 else { return nil }
        return (newestRow - age + Self.rows) % Self.rows
    }

    /// Sequence number of ring row `ring` (−1 when not written since the last clear).
    public func sequence(ofRing ring: Int) -> Int { sequences[min(max(ring, 0), Self.rows - 1)] }

    /// Level 0…255 of `column` in the row `age` rows old; 0 when not written.
    public func level(column: Int, age: Int) -> UInt8 {
        guard let ring = ringRow(age: age) else { return 0 }
        return levels[ring * Self.columns + min(max(column, 0), Self.columns - 1)]
    }

    /// Calls `body` with each ring row written since the last drain (every row after a clear or an overflow), then
    /// empties the list. No allocation.
    public func drainPending(_ body: (Int) -> Void) {
        if allPending {
            for r in 0..<Self.rows { body(r) }
        } else {
            for k in 0..<pendingCount { body(pendingRows[k]) }
        }
        pendingCount = 0
        allPending = false
    }

    /// The CPU mirror of `vis_waterfall_level`: the level 0…1 shown at pixel centre (x, y) of a `width × height`
    /// output (newest row at the top, horizontal linear interpolation between columns).
    public func level(atX x: Float, y: Float, width: Int, height: Int) -> Float {
        let w: Float = Float(max(width, 1)), h: Float = Float(max(height, 1))
        let age: Int = min(Int(max(y, 0) / h * Float(Self.rows)), Self.rows - 1)
        let newest: Int = max(newestRow, 0)
        let ring: Int = (newest + Self.rows - age) % Self.rows
        let position: Float = min(max(x / w * Float(Self.columns) - 0.5, 0), Float(Self.columns - 1))
        let x0: Int = Int(position)
        let x1: Int = min(x0 + 1, Self.columns - 1)
        let f: Float = position - Float(x0)
        let a: Float = Float(levels[ring * Self.columns + x0]) / 255
        let b: Float = Float(levels[ring * Self.columns + x1]) / 255
        return a + (b - a) * f
    }

    /// The colour of level v at gain 1 before brightness: the palette at position v (16 stops) × v (silence is black).
    public static func color(_ v: Float, stops: UnsafePointer<LinearColor>) -> LinearColor {
        let level: Float = min(max(v.isFinite ? v : 0, 0), 1)
        let position: Float = level * Float(NoiseFieldConfiguration.paletteColors - 1)
        let i: Int = min(Int(position), NoiseFieldConfiguration.paletteColors - 2)
        let f: Float = position - Float(i)
        let a: LinearColor = stops[i], b: LinearColor = stops[i + 1]
        return LinearColor(red: (a.red + (b.red - a.red) * f) * level, green: (a.green + (b.green - a.green) * f) * level,
                           blue: (a.blue + (b.blue - a.blue) * f) * level, alpha: 1)
    }
}

/// The waterfall's light per flash estimate cell (VIS-020-R7; research VIS-020-D6). All storage allocated in `init`.
public final class WaterfallFlashCells {
    /// Column groups per row (one per estimate column): 32 columns each.
    public static let groups = NoiseFieldFlashAreas.gridSide
    static let groupWidth = SpectrumWaterfallHistory.columns / groups
    static let agesPerCell = SpectrumWaterfallHistory.rows / NoiseFieldFlashAreas.gridSide

    /// Per ring row, the sum of its texels' colours (at gain 1, before brightness) in each column group.
    private let rowSums: UnsafeMutablePointer<LinearColor>

    public init() {
        rowSums = .allocate(capacity: SpectrumWaterfallHistory.rows * Self.groups)
        rowSums.initialize(repeating: LinearColor(red: 0, green: 0, blue: 0, alpha: 0),
                           count: SpectrumWaterfallHistory.rows * Self.groups)
    }

    deinit {
        rowSums.deinitialize(count: SpectrumWaterfallHistory.rows * Self.groups)
        rowSums.deallocate()
    }

    /// Recomputes ring row `ring`'s group sums from `history` (256 colour evaluations).
    public func update(ring: Int, history: SpectrumWaterfallHistory, stops: UnsafePointer<LinearColor>) {
        let row: Int = min(max(ring, 0), SpectrumWaterfallHistory.rows - 1)
        let base: UnsafeMutablePointer<UInt8> = history.levels + row * SpectrumWaterfallHistory.columns
        for g in 0..<Self.groups {
            var r: Float = 0, gr: Float = 0, b: Float = 0
            for k in 0..<Self.groupWidth {
                let color: LinearColor = SpectrumWaterfallHistory.color(Float(base[g * Self.groupWidth + k]) / 255, stops: stops)
                r += color.red; gr += color.green; b += color.blue
            }
            rowSums[row * Self.groups + g] = LinearColor(red: r, green: gr, blue: b, alpha: 1)
        }
    }

    /// Recomputes every row (a palette change).
    public func updateAll(history: SpectrumWaterfallHistory, stops: UnsafePointer<LinearColor>) {
        for ring in 0..<SpectrumWaterfallHistory.rows { update(ring: ring, history: history, stops: stops) }
    }

    /// The mean colour (gain 1, before brightness) of estimate cell (row, column), rows top first: ages
    /// row · 64 ..< (row + 1) · 64, columns column · 32 ..< (column + 1) · 32 — the same ring rows the shader shows.
    public func cellColor(row: Int, column: Int, history: SpectrumWaterfallHistory) -> LinearColor {
        let newest: Int = max(history.newestRow, 0)
        var r: Float = 0, g: Float = 0, b: Float = 0
        for age in (row * Self.agesPerCell)..<((row + 1) * Self.agesPerCell) {
            let ring: Int = (newest + SpectrumWaterfallHistory.rows - age) % SpectrumWaterfallHistory.rows
            let s: LinearColor = rowSums[ring * Self.groups + column]
            r += s.red; g += s.green; b += s.blue
        }
        let n: Float = Float(Self.agesPerCell * Self.groupWidth)
        return LinearColor(red: r / n, green: g / n, blue: b / n, alpha: 1)
    }
}

/// VIS-020: the MSL of the waterfall's sampling (module-authored; SHD-011). Mirrored by
/// `SpectrumWaterfallHistory.level(atX:y:width:height:)`.
public enum WaterfallShader {
    public static let function = """

    // VIS-020: the level shown at pixel centre p of an output of `size`: newest ring row at the top, columns linearly
    // interpolated. `newest` is the ring index of the newest row.
    static float vis_waterfall_level(texture2d<float, access::read> history, float2 p, float2 size, float newest) {
        uint w = history.get_width();
        uint h = history.get_height();
        uint age = min(uint(max(p.y, 0.0) / size.y * float(h)), h - 1u);
        uint n = uint(clamp(newest, 0.0, float(h - 1u)) + 0.5);
        uint row = (n + h - age) % h;
        float x = clamp(p.x / size.x * float(w) - 0.5, 0.0, float(w - 1u));
        uint x0 = uint(x);
        uint x1 = min(x0 + 1u, w - 1u);
        float f = x - float(x0);
        float a = history.read(uint2(x0, row)).r;
        float b = history.read(uint2(x1, row)).r;
        return a + (b - a) * f;
    }

    """
}
