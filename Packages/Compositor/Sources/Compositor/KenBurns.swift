// KenBurns.swift — pan and zoom of a still between two crop rectangles (MED-007-R1 to R5, R12;
// specs/251-med-007-ken-burns, contracts/ken-burns.md K1; research MED-007-D3, D4).
//
// Plain Swift (every host, Linux included). A crop rectangle is x, y, width, height in fractions of the image
// (0…1, top-left origin). A movement goes from `start` to `end` over a duration with an easing:
//
//     u = elapsed / duration (integer nanoseconds)     each edge = a + (b − a) · easing(u)
//
// At elapsed 0 the stored start is returned as is, at elapsed ≥ duration the stored end (SHOW-008's rule: at a key
// time, the stored sample itself), so the first and the end frame are exact. Both easings are monotonic on 0…1 and
// a linear mix of two rectangles inside the image stays inside it, so every edge moves monotonically and every
// intermediate rectangle is valid. `KenBurnsPlayhead` counts elapsed time from the frame clock's (clamped) frame
// durations, so a pause or a stall never makes the movement jump. Value types, no allocation per frame.
//
// Every intermediate is a named, typed value (type-check budget on Linux and Xcode 26).

/// A crop rectangle in image fractions (0…1, top-left origin).
public struct KenBurnsRect: Sendable, Hashable, Codable {
    /// The smallest width or height (at most 20× zoom).
    public static let minimumSize: Double = 0.05
    static let tolerance: Double = 1e-9
    /// The whole image.
    public static let full = KenBurnsRect(uncheckedX: 0, y: 0, width: 1, height: 1)

    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    init(uncheckedX x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// nil unless every value is finite, the size is at least `minimumSize` and the rectangle lies inside the image.
    public init?(validatingX x: Double, y: Double, width: Double, height: Double) {
        guard Self.isValid(x: x, y: y, width: width, height: height) else { return nil }
        self.init(uncheckedX: x, y: y, width: width, height: height)
    }

    /// Always valid: non-finite values read as the whole image's, the size is clamped to `minimumSize…1` first, then
    /// the origin so the rectangle lies inside the image.
    public static func clamped(x: Double, y: Double, width: Double, height: Double) -> KenBurnsRect {
        let w: Double = clampSize(width)
        let h: Double = clampSize(height)
        let cx: Double = clampOrigin(x, size: w)
        let cy: Double = clampOrigin(y, size: h)
        return KenBurnsRect(uncheckedX: cx, y: cy, width: w, height: h)
    }

    /// An image-shaped rectangle for a zoom (1…20; 1 = the whole image) and a position (0…1 of the free range on each
    /// axis; 0.5 = centred) (research MED-007-D9).
    public static func zoom(_ zoom: Double, positionX: Double, positionY: Double) -> KenBurnsRect {
        let z: Double = zoom.isFinite ? min(max(zoom, 1), 1 / minimumSize) : 1
        let size: Double = 1 / z
        let free: Double = 1 - size
        let px: Double = positionX.isFinite ? min(max(positionX, 0), 1) : 0.5
        let py: Double = positionY.isFinite ? min(max(positionY, 0), 1) : 0.5
        return clamped(x: px * free, y: py * free, width: size, height: size)
    }

    /// 1 / the larger side (the zoom of an image-shaped rectangle).
    public var zoom: Double { 1 / max(width, height) }

    /// Where the rectangle sits in the free range on each axis (0.5 when there is none).
    public var position: (x: Double, y: Double) {
        let freeX: Double = 1 - width
        let freeY: Double = 1 - height
        let px: Double = freeX > Self.tolerance ? x / freeX : 0.5
        let py: Double = freeY > Self.tolerance ? y / freeY : 0.5
        return (min(max(px, 0), 1), min(max(py, 0), 1))
    }

    public static func isValid(x: Double, y: Double, width: Double, height: Double) -> Bool {
        guard x.isFinite, y.isFinite, width.isFinite, height.isFinite else { return false }
        guard width >= minimumSize - tolerance, height >= minimumSize - tolerance else { return false }
        guard x >= -tolerance, y >= -tolerance else { return false }
        let right: Double = x + width
        let bottom: Double = y + height
        return right <= 1 + tolerance && bottom <= 1 + tolerance
    }

    private static func clampSize(_ v: Double) -> Double {
        guard v.isFinite else { return 1 }
        return min(max(v, minimumSize), 1)
    }

    private static func clampOrigin(_ v: Double, size: Double) -> Double {
        guard v.isFinite else { return 0 }
        let c: Double = min(max(v, 0), 1 - size)
        return c == 0 ? 0 : c   // −0 is stored as 0
    }

    /// The mix `self + (other − self) · f` per edge (f in 0…1).
    public func mixed(with other: KenBurnsRect, fraction f: Double) -> KenBurnsRect {
        let nx: Double = x + (other.x - x) * f
        let ny: Double = y + (other.y - y) * f
        let nw: Double = width + (other.width - width) * f
        let nh: Double = height + (other.height - height) * f
        return KenBurnsRect(uncheckedX: nx, y: ny, width: nw, height: nh)
    }

    // MARK: JSON (validated)

    private enum CodingKeys: String, CodingKey { case x, y, width, height }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let x: Double = try c.decode(Double.self, forKey: .x)
        let y: Double = try c.decode(Double.self, forKey: .y)
        let w: Double = try c.decode(Double.self, forKey: .width)
        let h: Double = try c.decode(Double.self, forKey: .height)
        guard let rect = KenBurnsRect(validatingX: x, y: y, width: w, height: h) else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: c.codingPath, debugDescription: "invalid crop rectangle"))
        }
        self = rect
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(x, forKey: .x)
        try c.encode(y, forKey: .y)
        try c.encode(width, forKey: .width)
        try c.encode(height, forKey: .height)
    }
}

/// How the movement accelerates. Raw values are the saved names.
public enum KenBurnsEasing: String, Sendable, Hashable, Codable, CaseIterable {
    case linear
    /// Smoothstep 3u² − 2u³: starts and ends gently; monotonic.
    case easeInOut

    /// The eased fraction for `u` (clamped to 0…1).
    public func shaped(_ u: Double) -> Double {
        let t: Double = u.isFinite ? min(max(u, 0), 1) : 0
        switch self {
        case .linear:
            return t
        case .easeInOut:
            let t2: Double = t * t
            let a: Double = 3 * t2
            let b: Double = 2 * t2 * t
            return a - b
        }
    }
}

/// A pan and zoom between two crop rectangles (data-model "KenBurnsMotion").
public struct KenBurnsMotion: Sendable, Hashable, Codable {
    public static let durationRangeMilliseconds: ClosedRange<Int> = 2_000...60_000
    public static let defaultDurationMilliseconds = 10_000

    public let start: KenBurnsRect
    public let end: KenBurnsRect
    /// 2000…60000 (clamped).
    public let durationMilliseconds: Int
    public let easing: KenBurnsEasing

    public init(start: KenBurnsRect, end: KenBurnsRect, durationMilliseconds: Int = KenBurnsMotion.defaultDurationMilliseconds,
                easing: KenBurnsEasing = .easeInOut) {
        self.start = start
        self.end = end
        self.durationMilliseconds = Self.clampDuration(durationMilliseconds)
        self.easing = easing
    }

    public static func clampDuration(_ ms: Int) -> Int {
        min(max(ms, durationRangeMilliseconds.lowerBound), durationRangeMilliseconds.upperBound)
    }

    /// The duration in nanoseconds.
    public var durationNanoseconds: UInt64 { UInt64(durationMilliseconds) * 1_000_000 }

    /// Start and end are the same rectangle (a still crop).
    public var isStill: Bool { start == end }

    /// The rectangle `elapsedNanoseconds` into a movement lasting `durationNanoseconds`: exactly `start` at 0, exactly
    /// `end` at or after the duration (and for a zero duration), the eased mix between.
    public func crop(elapsedNanoseconds: UInt64, durationNanoseconds: UInt64) -> KenBurnsRect {
        if elapsedNanoseconds >= durationNanoseconds { return end }
        if elapsedNanoseconds == 0 { return start }
        let u: Double = Double(elapsedNanoseconds) / Double(durationNanoseconds)
        let f: Double = easing.shaped(u)
        return start.mixed(with: end, fraction: f)
    }

    /// The rectangle at `elapsedNanoseconds` over this movement's own duration.
    public func crop(elapsedNanoseconds: UInt64) -> KenBurnsRect {
        crop(elapsedNanoseconds: elapsedNanoseconds, durationNanoseconds: durationNanoseconds)
    }

    public func with(start: KenBurnsRect? = nil, end: KenBurnsRect? = nil, durationMilliseconds: Int? = nil,
                     easing: KenBurnsEasing? = nil) -> KenBurnsMotion {
        KenBurnsMotion(start: start ?? self.start, end: end ?? self.end, durationMilliseconds: durationMilliseconds ?? self.durationMilliseconds,
                       easing: easing ?? self.easing)
    }

    // MARK: JSON (the scene field's keys; durations clamped, unknown easing refused)

    private enum CodingKeys: String, CodingKey { case start, end, durationMilliseconds, easing }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let start: KenBurnsRect = try c.decode(KenBurnsRect.self, forKey: .start)
        let end: KenBurnsRect = try c.decode(KenBurnsRect.self, forKey: .end)
        let ms: Int = try c.decode(Int.self, forKey: .durationMilliseconds)
        let easing: KenBurnsEasing = try c.decode(KenBurnsEasing.self, forKey: .easing)
        self.init(start: start, end: end, durationMilliseconds: ms, easing: easing)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(start, forKey: .start)
        try c.encode(end, forKey: .end)
        try c.encode(durationMilliseconds, forKey: .durationMilliseconds)
        try c.encode(easing, forKey: .easing)
    }
}

/// The movements Settings offers (MED-007-R11). `custom` is any other pair of rectangles.
public enum KenBurnsPreset: String, Sendable, CaseIterable {
    case zoomIn
    case zoomOut
    case panLeftToRight
    case panRightToLeft
    case custom

    /// The centre 2/3 of the image.
    public static let zoomedCentre = KenBurnsRect(uncheckedX: 1.0 / 6, y: 1.0 / 6, width: 2.0 / 3, height: 2.0 / 3)
    /// 80 % of the image at its left and right edges, vertically centred.
    public static let panLeft = KenBurnsRect(uncheckedX: 0, y: 0.1, width: 0.8, height: 0.8)
    public static let panRight = KenBurnsRect(uncheckedX: 0.2, y: 0.1, width: 0.8, height: 0.8)

    /// The preset's start and end (nil for custom).
    public var rectangles: (start: KenBurnsRect, end: KenBurnsRect)? {
        switch self {
        case .zoomIn: (KenBurnsRect.full, Self.zoomedCentre)
        case .zoomOut: (Self.zoomedCentre, KenBurnsRect.full)
        case .panLeftToRight: (Self.panLeft, Self.panRight)
        case .panRightToLeft: (Self.panRight, Self.panLeft)
        case .custom: nil
        }
    }

    /// The preset a movement's rectangles match (custom when none).
    public static func matching(_ motion: KenBurnsMotion) -> KenBurnsPreset {
        for preset in allCases {
            if let r = preset.rectangles, r.start == motion.start, r.end == motion.end { return preset }
        }
        return .custom
    }

    /// The preset's movement with the given duration and easing.
    public func motion(durationMilliseconds: Int = KenBurnsMotion.defaultDurationMilliseconds,
                       easing: KenBurnsEasing = .easeInOut) -> KenBurnsMotion? {
        rectangles.map { (r: (start: KenBurnsRect, end: KenBurnsRect)) -> KenBurnsMotion in
            KenBurnsMotion(start: r.start, end: r.end, durationMilliseconds: durationMilliseconds, easing: easing)
        }
    }
}

/// Elapsed time of a running movement, counted from the frame clock (research MED-007-D4).
public struct KenBurnsPlayhead: Sendable, Equatable {
    /// Nanoseconds since the first drawn frame, saturating at the limit given to `advance`.
    public private(set) var elapsedNanoseconds: UInt64 = 0
    /// False until the first frame after a restart.
    public private(set) var started = false

    public init() {}

    /// The next frame starts at the start rectangle again.
    public mutating func restart() {
        elapsedNanoseconds = 0
        started = false
    }

    /// One drawn frame: the first after a restart stays at 0; later frames add their duration (seconds, as the frame
    /// clock gives it: 0…0.1; non-finite or negative adds nothing). Returns the elapsed time to draw.
    @discardableResult
    public mutating func advance(frameDuration: Double, limit: UInt64) -> UInt64 {
        guard started else {
            started = true
            elapsedNanoseconds = 0
            return 0
        }
        let seconds: Double = frameDuration.isFinite ? min(max(frameDuration, 0), 1) : 0
        let step: UInt64 = UInt64((seconds * 1e9).rounded())
        let (sum, overflow) = elapsedNanoseconds.addingReportingOverflow(step)
        elapsedNanoseconds = overflow ? limit : min(sum, limit)
        return elapsedNanoseconds
    }

    /// The movement reached its end.
    public func isFinished(limit: UInt64) -> Bool { started && elapsedNanoseconds >= limit }
}
