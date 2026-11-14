// ExpressionMapping.swift — a compiled formula used where a binding's linear position is used
// (SHD-009-R10; contract E8; Clarifications: adapter only).
//
// The formula's value is limited to the 0…1 position exactly as MOD-003 limits a linear position
// (non-finite → 0, then clamped), and MOD-003's interpolation maps it into the output range, so a
// formula reaches a parameter only through the existing range clamping. MOD-004: the position is shaped
// by `curve` (linear by default, bit-identical) before the interpolation. Wiring mappings into
// `AudioFeatureModulator` bindings, with the target checks of MOD-002 contract C2, is a later row.
import ParameterGraph

public struct ExpressionMapping: Sendable, Hashable {
    public var expression: CompiledExpression
    /// The values at position 0 and 1 (valid when finite); an end below the start inverts.
    public var outputStart: Double
    public var outputEnd: Double
    /// Shapes the 0…1 position before the interpolation (MOD-004-R8).
    public var curve: MappingCurve

    public init(expression: CompiledExpression, outputStart: Double = 0, outputEnd: Double = 1, curve: MappingCurve = .linear) {
        self.expression = expression
        self.outputStart = outputStart
        self.outputEnd = outputEnd
        self.curve = curve
    }

    /// Both output ends are finite.
    public var isValid: Bool { outputStart.isFinite && outputEnd.isFinite }

    /// The formula's value limited to 0…1 (MOD-003 `clampedPosition`).
    public func position(_ inputs: ExpressionInputs) -> Double {
        LinearMapping.clampedPosition(expression.evaluate(inputs))
    }

    /// The position shaped by the curve, then mapped into the output range (MOD-003 `interpolate`):
    /// exact ends, bounded.
    public func map(_ inputs: ExpressionInputs) -> Double {
        let shaped: Double = curve.apply(position(inputs))
        return LinearMapping.interpolate(from: outputStart, to: outputEnd, at: shaped)
    }
}
