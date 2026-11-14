// BandSmoother.swift — independent attack and release smoothing of band values (ANL-003-R1 to R5,
// R7; research ANL-003-D2, D3; contract C1).
//
// Per band, a one-pole follower: y ← y + a·(x − y), with a = 1 − exp(ln(0.1)·Δt/τ), τ the attack
// time when the input is above the state and the release time when it is below, Δt the frame
// interval. After frames totalling T a step has (x − y)/(x − y₀) = exp(ln 0.1 · T/τ) left, exactly
// 10 % at T = τ however T is split, so "reaches 90 % by the attack time" holds at any frame rate.
// τ = 0 is instant. The two coefficients are computed once per update.
//
// The first update, the first after `reset()`, and any update whose band count or capture-session
// generation differs from the previous one take the input directly (no ramp from zero or from an
// old session). A non-finite input band holds its state (0 when snapping). A non-positive or
// non-finite Δt makes no progress for non-zero times.
//
// It sits after band extraction (ANL-002) and normalization, on the display side; onset detection
// (ANL-004) keeps working on raw spectra. Pure Swift (builds on Linux and with
// -DANALYSIS_NO_ACCELERATE). Storage for 128 bands is allocated in `init`; `update` allocates,
// locks and logs nothing. Not Sendable: one owner.
import Foundation

/// Attack and release times in seconds (ANL-003-R7).
public struct SmoothingTimes: Sendable, Equatable {
    public static let range: ClosedRange<Double> = 0...2
    /// Both 0: the output is the input (today's look).
    public static let instant = SmoothingTimes(attackSeconds: 0, releaseSeconds: 0)

    public var attackSeconds: Double
    public var releaseSeconds: Double

    /// Clamps both to `range`; NaN reads 0.
    public init(attackSeconds: Double, releaseSeconds: Double) {
        self.attackSeconds = Self.clamped(attackSeconds)
        self.releaseSeconds = Self.clamped(releaseSeconds)
    }

    public var isInstant: Bool { attackSeconds == 0 && releaseSeconds == 0 }

    private static func clamped(_ value: Double) -> Double {
        if value.isNaN { return 0 }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    /// The fraction of the remaining distance covered in one frame: 1 − exp(ln(0.1)·Δt/τ); 1 when
    /// τ = 0; 0 when Δt is not finite or not positive (for τ > 0).
    public static func coefficient(timeConstant: Double, frameInterval: Double) -> Double {
        if timeConstant <= 0 { return 1 }
        guard frameInterval.isFinite, frameInterval > 0 else { return 0 }
        let exponent: Double = log(0.1) * frameInterval / timeConstant
        let remaining: Double = exp(exponent)
        return 1 - remaining
    }
}

public final class BandSmoother {
    /// Largest band vector (BandCount.b128).
    public static let capacity = BandCount.b128.rawValue

    /// Effective from the next update; never snaps the state.
    public var times: SmoothingTimes

    private let state: UnsafeMutablePointer<Float>
    private var count = 0
    private var generation: UInt64 = 0
    private var primed = false

    public init(times: SmoothingTimes = .instant) {
        self.times = times
        state = .allocate(capacity: Self.capacity)
        state.initialize(repeating: 0, count: Self.capacity)
    }

    deinit {
        state.deinitialize(count: Self.capacity)
        state.deallocate()
    }

    /// The next update takes its input directly.
    public func reset() {
        primed = false
    }

    /// Smooths `count` values of `target` (clamped to 0…capacity) over `frameInterval` seconds and
    /// returns the smoothed vector, valid until the next call. Allocation-free.
    public func update(target: UnsafePointer<Float>, count requested: Int, frameInterval: Double,
                       generation newGeneration: UInt64) -> UnsafeBufferPointer<Float> {
        let n: Int = min(max(requested, 0), Self.capacity)
        if !primed || n != count || newGeneration != generation {
            for i in 0..<n {
                let x: Float = target[i]
                state[i] = x.isFinite ? x : 0
            }
            count = n
            generation = newGeneration
            primed = true
            return UnsafeBufferPointer(start: state, count: n)
        }
        let attack = Float(SmoothingTimes.coefficient(timeConstant: times.attackSeconds, frameInterval: frameInterval))
        let release = Float(SmoothingTimes.coefficient(timeConstant: times.releaseSeconds, frameInterval: frameInterval))
        for i in 0..<n {
            let x: Float = target[i]
            guard x.isFinite else { continue }
            let y: Float = state[i]
            let a: Float = x > y ? attack : release
            if a >= 1 {
                state[i] = x   // instant: exact copy
            } else {
                let step: Float = a * (x - y)
                state[i] = y + step
            }
        }
        return UnsafeBufferPointer(start: state, count: n)
    }
}
