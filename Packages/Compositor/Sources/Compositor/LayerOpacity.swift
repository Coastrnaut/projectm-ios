// LayerOpacity.swift — per-layer opacity fades (CMP-003-R5 to R7, R10; research CMP-003-D3 to D6;
// specs/043-cmp-003-opacity-per-layer/contracts/layer-opacity.md).
//
// CPU only (builds on Linux). A stack entry's opacity is the target a layer settles at; the
// compositor keeps one `LayerOpacityAnimator` per layer and advances it by the frame clock's clamped
// frame durations (CMP-001-R3), so a fade is deterministic from the frame times, never reads a wall
// clock and never jumps after a stall. Interpolation is a local pure helper (exact ends, never
// outside them, monotonic), not ParameterGraph's `LinearMapping`, to keep the core target's
// dependencies as they are.

/// How a fade moves between its ends.
public enum LayerOpacityCurve: Sendable, Equatable {
    /// Constant speed.
    case linear
    /// Smoothstep, t²(3 − 2t): slow at both ends, exact at 0 and 1, monotonic.
    case easeInOut

    /// Maps a position in 0…1 to 0…1 (exact at both ends).
    func shape(_ t: Double) -> Double {
        switch self {
        case .linear: return t
        case .easeInOut: return t * t * (3 - 2 * t)
        }
    }
}

/// Why a fade request was refused (nothing changed).
public enum LayerOpacityError: Error, Equatable, Sendable {
    case nonFiniteTarget
    case nonFiniteDuration
    case negativeDuration
}

/// How opacity changes in one `Compositor.apply` reach the screen.
public struct LayerOpacityTransition: Sendable, Equatable {
    /// Seconds of summed frame time; finite and ≥ 0 (0: at the next frame).
    public let duration: Double
    public let curve: LayerOpacityCurve

    public init(duration: Double, curve: LayerOpacityCurve = .linear) throws(LayerOpacityError) {
        guard duration.isFinite else { throw .nonFiniteDuration }
        guard duration >= 0 else { throw .negativeDuration }
        self.duration = duration
        self.curve = curve
    }

    private init(validDuration: Double, curve: LayerOpacityCurve) {
        duration = validDuration
        self.curve = curve
    }

    /// The new opacity is shown from the next frame.
    public static let immediate = LayerOpacityTransition(validDuration: 0, curve: .linear)
}

/// One layer's shown opacity and the fade towards its target.
public struct LayerOpacityAnimator: Sendable, Equatable {
    /// The opacity shown at the last `advance` (or set at once).
    public private(set) var value: Double
    /// Where the current fade ends.
    public private(set) var target: Double
    private var start: Double
    private var duration: Double = 0
    private var elapsed: Double = 0
    private var curve: LayerOpacityCurve = .linear

    /// Starts settled at `opacity` (clamped to 0…1; non-finite reads 1, as `LayerCompositeSettings`).
    public init(opacity: Double) {
        let v = Self.clamped(opacity.isFinite ? opacity : 1)
        value = v
        target = v
        start = v
    }

    /// True while a fade has time left.
    public var isAnimating: Bool { elapsed < duration }

    /// Fades from the shown value to `target` (clamped to 0…1) over `duration` seconds of frame time.
    /// A duration of 0 changes at once. Refused (nothing changes) for a non-finite target or a
    /// negative or non-finite duration.
    public mutating func setOpacity(_ target: Double, duration: Double, curve: LayerOpacityCurve = .linear) throws(LayerOpacityError) {
        guard target.isFinite else { throw .nonFiniteTarget }
        setOpacity(target, transition: try LayerOpacityTransition(duration: duration, curve: curve))
    }

    /// Fades from the shown value to `target` (finite; clamped to 0…1; a non-finite target is ignored).
    public mutating func setOpacity(_ target: Double, transition: LayerOpacityTransition) {
        guard target.isFinite else { return }
        start = value
        self.target = Self.clamped(target)
        duration = transition.duration
        curve = transition.curve
        elapsed = 0
        if duration == 0 { value = self.target }
    }

    /// Adds one frame's duration (negative or non-finite counts as 0) and returns the shown value.
    @discardableResult
    public mutating func advance(by frameDuration: Double) -> Double {
        guard isAnimating else { return value }
        if frameDuration.isFinite && frameDuration > 0 { elapsed += frameDuration }
        if elapsed >= duration {
            value = target
        } else {
            let s = curve.shape(elapsed / duration)
            let v = start + s * (target - start)
            value = min(max(v, min(start, target)), max(start, target))
        }
        return value
    }

    private static func clamped(_ v: Double) -> Double { min(max(v, 0), 1) }
}
