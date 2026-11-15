// EchoFeedback.swift — FX-010 "Echo feedback": the value, the echo cap, the weights, the bounded history size, the
// storing schedule and the CPU references of the two passes (specs/297-fx-010-echo-feedback,
// contracts/echo-feedback.md C2 to C4, research FX-010-D2 to D6, D9; ADR-0108). Plain Swift (builds on Linux).
//
// * At most `cap` (4) echoes. The history is a ring of exactly `cap` pictures at `historySize` (half the output per
//   axis, rounded to a multiple of 16, longer side ≤ 960): at most `historyBytesBound` bytes at any output size.
// * `EchoSchedule` stores one picture each time the delay has passed on the frame clock (at most once per frame,
//   after the frame's echoes are drawn); echo k is the k-th most recent store.
// * Output (`cmp_echo`): c non-finite → c; else max(c, Σ w_k × bilinear(history_k, (p + 0.5) ÷ size)) per channel,
//   w_k = decay^k scaled together so Σ w_k ≤ weightCap (≤ 1): never brighter than the frames it is made of.
// * Store (`cmp_echo_capture`): each history pixel is the mean of 4 sanitised bilinear samples of the input at ±¼
//   history pixel around its centre (an exact 2 × 2 box at a 2× ratio).
import FlashSafety
import Foundation

public struct EchoFeedback: Sendable, Equatable, Codable {
    /// The echo cap (the shader's `cmp_echo_cap` and the ring's length).
    public static let cap = 4
    public static let countRange: ClosedRange<Int> = 0...cap
    public static let defaultCount = 3
    /// Seconds between stored frames.
    public static let delayRange: ClosedRange<Double> = 0.01...0.5
    public static let defaultDelay = 0.1
    public static let delayStep = 0.01
    /// Each echo is this much weaker than the one before.
    public static let decayRange: ClosedRange<Double> = 0.1...0.9
    public static let defaultDecay = 0.6
    public static let decayStep = 0.05
    /// The weights never sum above this (ACC-012 lowers it per value).
    public static let maximumWeightSum = 1.0
    /// While Reduce flashing is effective (research FX-010-D9).
    public static let reduceFlashingWeightSum = 0.5
    /// The history's longer side at most (pixels), and its size step.
    public static let maxHistorySide = 960
    public static let historyStep = 16
    /// rgba16Float.
    public static let bytesPerHistoryPixel = 8
    /// The history's picture data never exceeds this: 4 × 960 × 960 × 8 = 29,491,200 bytes.
    public static let historyBytesBound = cap * maxHistorySide * maxHistorySide * bytesPerHistoryPixel

    /// Off (the default; output bit-identical to before FX-010).
    public static let off = EchoFeedback()

    public var isEnabled: Bool
    public var count: Int
    public var delaySeconds: Double
    public var decay: Double
    /// Not user-set: 1, or lower under ACC-012 (`limited(by:)`).
    public var weightCap: Double

    public init(isEnabled: Bool = false, count: Int = EchoFeedback.defaultCount, delaySeconds: Double = EchoFeedback.defaultDelay,
                decay: Double = EchoFeedback.defaultDecay, weightCap: Double = EchoFeedback.maximumWeightSum) {
        self.isEnabled = isEnabled
        self.count = count
        self.delaySeconds = delaySeconds
        self.decay = decay
        self.weightCap = weightCap
    }

    // MARK: - Ranges

    /// Above the cap → the cap; below 0 → 0.
    public static func clampCount(_ value: Int) -> Int { min(max(value, countRange.lowerBound), countRange.upperBound) }

    /// From a stored number: NaN → the default, rounded, then clamped (±Inf → the nearest bound).
    public static func clampCount(_ value: Double) -> Int {
        if value.isNaN { return defaultCount }
        if value >= Double(cap) { return cap }
        if value <= 0 { return 0 }
        return clampCount(Int(value.rounded()))
    }

    public static func clampDelay(_ value: Double) -> Double {
        if value.isNaN { return defaultDelay }
        return min(max(value, delayRange.lowerBound), delayRange.upperBound)
    }

    public static func clampDecay(_ value: Double) -> Double {
        if value.isNaN { return defaultDecay }
        return min(max(value, decayRange.lowerBound), decayRange.upperBound)
    }

    public static func clampWeightCap(_ value: Double) -> Double {
        guard value.isFinite else { return value == .infinity ? maximumWeightSum : 0 }
        return min(max(value, 0), maximumWeightSum)
    }

    /// A user value made valid.
    public var clamped: EchoFeedback {
        EchoFeedback(isEnabled: isEnabled, count: Self.clampCount(count), delaySeconds: Self.clampDelay(delaySeconds),
                     decay: Self.clampDecay(decay), weightCap: Self.clampWeightCap(weightCap))
    }

    /// The echoes drawn at most (0…cap).
    public var effectiveCount: Int { isEnabled ? Self.clampCount(count) : 0 }

    /// The compositor runs the pass: on, at least one echo and a positive weight cap.
    public var isActive: Bool { effectiveCount > 0 && Self.clampWeightCap(weightCap) > 0 }

    // MARK: - Weights (research FX-010-D4)

    /// The weights of the n = min(count, valid, cap) echoes drawn: decay^k (k = 1…n), scaled together so their sum
    /// never exceeds the weight cap. Empty when inactive or nothing is stored.
    public func weights(valid: Int) -> [Float] {
        guard isActive else { return [] }
        let n: Int = min(effectiveCount, max(valid, 0), Self.cap)
        guard n > 0 else { return [] }
        let d: Double = Self.clampDecay(decay)
        let raw: [Double] = (1...n).map { (k: Int) -> Double in pow(d, Double(k)) }
        let sum: Double = raw.reduce(0, +)
        let limit: Double = Self.clampWeightCap(weightCap)
        let scale: Double = sum > limit ? limit / sum : 1
        var out: [Float] = raw.map { (w: Double) -> Float in Float(w * scale) }
        // Float rounding must never push the sum over the cap.
        while out.reduce(Float(0), +) > Float(limit) {
            out = out.map { (w: Float) -> Float in w * (1 - 1.0 / 1_048_576) }
        }
        return out
    }

    // MARK: - ACC-012 (research FX-010-D9)

    /// What the compositors use under `clamp`: an intensity-capping profile scales the weight cap by its limit,
    /// Reduce flashing caps it at 0.5; a cap of 0 turns Echo off. Standard with Reduce flashing off returns `self`.
    public func limited(by clamp: SafetyClamp) -> EchoFeedback {
        guard isEnabled else { return self }
        var limit: Double = Self.clampWeightCap(weightCap)
        if clamp.capsIntensity { limit *= clamp.limits.intensityLimit }
        if clamp.reducesFlashing { limit = min(limit, Self.reduceFlashingWeightSum) }
        var out: EchoFeedback = self
        out.weightCap = limit
        if !(limit > 0) { out.isEnabled = false }
        return out
    }

    // MARK: - History size (research FX-010-D2)

    /// Nearest multiple of 16, at least 16.
    static func roundToStep(_ value: Int) -> Int {
        max(historyStep, ((value + historyStep / 2) / historyStep) * historyStep)
    }

    /// The history pictures' size for an output (nil for an empty output). This is also the size class: the ring is
    /// replaced only when it changes.
    public static func historySize(width: Int, height: Int) -> (width: Int, height: Int)? {
        guard width > 0, height > 0 else { return nil }
        var w: Int = roundToStep((width + 1) / 2)
        var h: Int = roundToStep((height + 1) / 2)
        let longer: Int = max(w, h)
        if longer > maxHistorySide {
            w = max(historyStep, (w * maxHistorySide / longer) / historyStep * historyStep)
            h = max(historyStep, (h * maxHistorySide / longer) / historyStep * historyStep)
        }
        return (w, h)
    }

    /// The ring's picture data for an output (bytes; 0 for an empty output).
    public static func historyBytes(width: Int, height: Int) -> Int {
        guard let size = historySize(width: width, height: height) else { return 0 }
        return cap * size.width * size.height * bytesPerHistoryPixel
    }

    // MARK: - CPU references (contract C2, C3)

    /// Per channel: non-finite → 0, negative → 0; alpha ≤ 1.
    static func sanitize(_ v: SIMD4<Float>) -> SIMD4<Float> {
        var out: SIMD4<Float> = v
        for c in 0..<4 { out[c] = out[c].isFinite ? max(out[c], 0) : 0 }
        out.w = min(out.w, 1)
        return out
    }

    /// Hardware-style bilinear sample (clamp to edge) at index-space position (x, y) (pixel centres at integers).
    public static func bilinear(_ pixels: [SIMD4<Float>], width: Int, height: Int, x: Float, y: Float) -> SIMD4<Float> {
        let x0f: Float = x.rounded(.down), y0f: Float = y.rounded(.down)
        let fx: Float = x - x0f, fy: Float = y - y0f
        let x0 = Int(x0f), y0 = Int(y0f)
        let xa: Int = min(max(x0, 0), width - 1), xb: Int = min(max(x0 + 1, 0), width - 1)
        let ya: Int = min(max(y0, 0), height - 1), yb: Int = min(max(y0 + 1, 0), height - 1)
        let top: SIMD4<Float> = lerp(pixels[ya * width + xa], pixels[ya * width + xb], fx)
        let bottom: SIMD4<Float> = lerp(pixels[yb * width + xa], pixels[yb * width + xb], fx)
        return lerp(top, bottom, fy)
    }

    /// `a` when `t` is exactly 0 (a non-finite `b` with weight 0 cannot leak in), else a + t × (b − a).
    static func lerp(_ a: SIMD4<Float>, _ b: SIMD4<Float>, _ t: Float) -> SIMD4<Float> {
        t == 0 ? a : a * (1 - t) + b * t
    }

    /// Bilinear sample at normalised coordinates (u, v).
    static func sampleNormalized(_ pixels: [SIMD4<Float>], width: Int, height: Int, u: Float, v: Float) -> SIMD4<Float> {
        bilinear(pixels, width: width, height: height, x: u * Float(width) - 0.5, y: v * Float(height) - 0.5)
    }

    /// The stored picture of `pixels` (width × height) at `historyWidth` × `historyHeight` (contract C3).
    public static func downsample(_ pixels: [SIMD4<Float>], width: Int, height: Int, historyWidth: Int,
                                  historyHeight: Int) -> [SIMD4<Float>] {
        var out: [SIMD4<Float>] = []
        out.reserveCapacity(historyWidth * historyHeight)
        let du: Float = 0.25 / Float(historyWidth), dv: Float = 0.25 / Float(historyHeight)
        for j in 0..<historyHeight {
            for i in 0..<historyWidth {
                let u: Float = (Float(i) + 0.5) / Float(historyWidth)
                let v: Float = (Float(j) + 0.5) / Float(historyHeight)
                var sum = SIMD4<Float>(repeating: 0)
                for (su, sv) in [(-du, -dv), (du, -dv), (-du, dv), (du, dv)] {
                    sum += sanitize(sampleNormalized(pixels, width: width, height: height, u: u + su, v: v + sv))
                }
                out.append(sum * 0.25)
            }
        }
        return out
    }

    /// One output pixel (contract C2): `history` most recent first, each `historyWidth` × `historyHeight`.
    public static func referencePixel(current: SIMD4<Float>, x: Int, y: Int, width: Int, height: Int,
                                      history: [[SIMD4<Float>]], historyWidth: Int, historyHeight: Int,
                                      weights: [Float]) -> SIMD4<Float> {
        for c in 0..<4 where !current[c].isFinite { return current }
        let u: Float = (Float(x) + 0.5) / Float(width), v: Float = (Float(y) + 0.5) / Float(height)
        var echo = SIMD4<Float>(repeating: 0)
        for k in 0..<min(weights.count, history.count, cap) {
            echo += weights[k] * sampleNormalized(history[k], width: historyWidth, height: historyHeight, u: u, v: v)
        }
        return pointwiseMax(current, echo)
    }

    /// The whole frame (the input itself when no echo is drawn).
    public static func reference(_ pixels: [SIMD4<Float>], width: Int, height: Int, history: [[SIMD4<Float>]],
                                 historyWidth: Int, historyHeight: Int, weights: [Float]) -> [SIMD4<Float>] {
        guard !weights.isEmpty, !history.isEmpty else { return pixels }
        var out: [SIMD4<Float>] = []
        out.reserveCapacity(pixels.count)
        for y in 0..<height {
            for x in 0..<width {
                out.append(referencePixel(current: pixels[y * width + x], x: x, y: y, width: width, height: height,
                                          history: history, historyWidth: historyWidth, historyHeight: historyHeight,
                                          weights: weights))
            }
        }
        return out
    }
}

/// FX-010 (research FX-010-D3): which ring slot each echo reads and when a frame stores (sample and hold on the frame
/// clock). Plain Swift; the compositor's `EchoPass` owns one.
public struct EchoSchedule: Sendable, Equatable {
    /// Seconds of tolerance when the time since the last store is compared with the delay.
    public static let tolerance = 1e-6

    /// Stored pictures that hold content (0…cap).
    public private(set) var valid = 0
    /// The ring slot of the newest store (−1 before the first).
    public private(set) var newest = -1
    /// Seconds since the last store.
    public private(set) var sinceStore = 0.0
    /// The next frame stores at once (after a reset).
    public private(set) var storeDue = true

    public init() {}

    /// Empties the history: no echo until frames are stored again; the next frame stores at once.
    public mutating func reset() { self = EchoSchedule() }

    /// The slot echo k (1…valid) reads: the k-th most recent store.
    public func slot(echo k: Int) -> Int {
        (newest - (k - 1) + EchoFeedback.cap * 2) % EchoFeedback.cap
    }

    /// The slot the next store writes (the oldest).
    public var nextSlot: Int { (newest + 1) % EchoFeedback.cap }

    /// Advances the clock by one frame; true when this frame stores (call `stored(delay:)` once it did).
    public mutating func advance(frameDuration: Double, delay: Double) -> Bool {
        if storeDue { return true }
        let dt: Double = frameDuration.isFinite && frameDuration > 0 ? frameDuration : 0
        sinceStore += dt
        return sinceStore + Self.tolerance >= EchoFeedback.clampDelay(delay)
    }

    /// The frame stored into `nextSlot`.
    public mutating func stored(delay: Double) {
        let d: Double = EchoFeedback.clampDelay(delay)
        if storeDue {
            sinceStore = 0
        } else {
            sinceStore = max(sinceStore - d, 0)
            if sinceStore + Self.tolerance >= d { sinceStore = 0 }   // at most one store per frame: drop the excess
        }
        storeDue = false
        newest = nextSlot
        valid = min(valid + 1, EchoFeedback.cap)
    }
}
