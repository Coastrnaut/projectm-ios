// FrameLuminanceTransfer.swift — how stages after a generator change the frame's brightness, so the
// Reduce-flashing limiter can bound the composited picture (FX-001-R10; research FX-001-D4;
// ADR-0010 decision 5).
//
// A generator made of flat-colored regions computes its mean luminance as Σ area · T(color) / A.
// With no downstream stage T is the relative luminance Y; an effect that adds light (bloom) supplies
// a T that bounds what one unit of area of that color contributes to the final frame, wherever the
// effect puts that light. Implementations are values with no per-call allocation.

public protocol FrameLuminanceTransfer: Sendable {
    /// Mean relative luminance contributed, per unit of its area, by a flat region of this linear,
    /// premultiplied pixel color after the downstream stages (an upper bound). Must be
    /// nondecreasing when the color is scaled up.
    func outputLuminance(ofFlatColor color: LinearColor) -> Double
}

/// No downstream stage: Y(color).
public struct IdentityLuminanceTransfer: FrameLuminanceTransfer {
    public init() {}

    @inlinable
    public func outputLuminance(ofFlatColor color: LinearColor) -> Double {
        Double(color.relativeLuminance)
    }
}
