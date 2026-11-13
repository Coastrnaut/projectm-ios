// FrameLuminanceTransfer.swift — how stages after a generator change the frame's brightness, so the
// Reduce-flashing limiter can bound the composited picture (FX-001-R10; research FX-001-D4;
// ADR-0010 decision 5).
//
// A generator made of flat-colored regions computes its mean luminance as Σ area · T(color) / A.
// With no downstream stage T is the relative luminance Y; an effect that adds light (bloom) supplies
// a T that bounds what one unit of area of that color contributes to the final frame, wherever the
// effect puts that light. Implementations are values with no per-call allocation.
//
// FX-019 (research FX-019-D6) adds the redness bound (WCAG red flash) and how far the downstream
// stages move light, so the strobe safety envelope can place it in the 4 × 4 areas.

public protocol FrameLuminanceTransfer: Sendable {
    /// Mean relative luminance contributed, per unit of its area, by a flat region of this linear,
    /// premultiplied pixel color after the downstream stages (an upper bound). Must be
    /// nondecreasing when the color is scaled up.
    func outputLuminance(ofFlatColor color: LinearColor) -> Double
    /// Mean redness max(R − G − B, 0) contributed per unit of area of this color after the downstream
    /// stages (an upper bound; nondecreasing when the color is scaled up). Default: the color's own.
    func outputRedness(ofFlatColor color: LinearColor) -> Double
    /// How far, in pixels of a `width × height` output, the downstream stages carry the light they
    /// add (0 when they add none). Must not allocate.
    func spreadRadius(width: Int, height: Int) -> Double
}

extension FrameLuminanceTransfer {
    public func outputRedness(ofFlatColor color: LinearColor) -> Double { Double(color.redness) }
    public func spreadRadius(width: Int, height: Int) -> Double { 0 }
}

/// No downstream stage: Y(color).
public struct IdentityLuminanceTransfer: FrameLuminanceTransfer {
    public init() {}

    @inlinable
    public func outputLuminance(ofFlatColor color: LinearColor) -> Double {
        Double(color.relativeLuminance)
    }
}
