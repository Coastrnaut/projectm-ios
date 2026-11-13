// ExpressionTestSupport.swift — SHD-009-T11: shared inputs and fixtures for the expression tests.
import ParameterExpression
import ParameterGraph

/// Fixed inputs: four bands, onset, beat confidence and time (exactly representable values).
struct ExpressionTestInputs {
    var bands: [Float] = [0.5, 0.25, 1, 0.125]
    var onset: Float? = 0.75
    var beatConfidence: Double? = 0.5
    var time: Double = 2

    func evaluate(_ expression: CompiledExpression) -> Double {
        bands.withUnsafeBufferPointer { (buffer: UnsafeBufferPointer<Float>) -> Double in
            let frame = AudioFeatureFrame(bands: buffer, onset: onset, beatConfidence: beatConfidence)
            return expression.evaluate(ExpressionInputs(frame: frame, timeSeconds: time))
        }
    }

    func map(_ mapping: ExpressionMapping) -> Double {
        bands.withUnsafeBufferPointer { (buffer: UnsafeBufferPointer<Float>) -> Double in
            let frame = AudioFeatureFrame(bands: buffer, onset: onset, beatConfidence: beatConfidence)
            return mapping.map(ExpressionInputs(frame: frame, timeSeconds: time))
        }
    }
}

enum ExpressionFixtures {
    /// Valid formulas (the evaluation table's sources), reused by the determinism and fuzz tests.
    static let valid: [String] = [
        "1 + 2 * 3", "(1 + 2) * 3", "10 - 4 - 3", "16 / 4 / 2", "-2 * 3", "--2", "+3", "2 - -1",
        "1.5e2", "2.5E-1", "audio.band.0", "audio.band.3", "audio.band.10", "audio.bandMean",
        "audio.onset", "audio.beatConfidence", "time", "pi", "tau", "e",
        "min(3, 4)", "max(3, 4)", "clamp(5, 0, 1)", "clamp(-1, 0, 1)", "abs(-2.5)", "sin(0)", "cos(0)",
        "floor(-1.5)", "fract(2.75)", "fract(-0.25)", "mix(2, 4, 0.25)", "smoothstep(0, 1, 0.5)",
        "smoothstep(0, 2, 4)", "step(0.5, 0.75)", "step(0.5, 0.25)", "sqrt(16)", "pow(2, 10)",
        "clamp(audio.onset * 2 - 0.5, 0, 1)",
        "mix(audio.band.0, audio.band.2, 0.5 + 0.5 * sin(time))",
        "let a = 2; let b = a * 3; b + a", "let b = a * 3; let a = 2; b + a", "let unused = 5; 1",
        "1 +\n\t2",
        "let k = audio.onset * 2;\nlet s = smoothstep(0.2, 0.8, k);\nmix(0.1, 0.9, s) * (1 + 0.25 * cos(time * tau))",
    ]
}
