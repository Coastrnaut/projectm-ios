// RadialWaveformFixtures.swift — VIS-005-T03: helpers for the radial waveform tests. Histories come from
// VIS-003's `WaveformSignal` (a pure function of the absolute sample index) or are constant; distance helpers
// measure the closed ring (VIS-005-S1, S2).
@testable import VisualGenerators

enum RadialFixture {
    static func constant(_ value: Float, count: Int = 4_096) -> [Float] { [Float](repeating: value, count: count) }
    static func silence() -> [Float] { constant(0) }
    static func sine(_ frequency: Double, amplitude: Double = 0.8, endingAt end: Int64 = 60_000) -> [Float] {
        WaveformSignal(shape: .sine, frequency: frequency, amplitude: amplitude).history(endingAt: end)
    }
}

extension RadialWaveformLayout {
    func layout(_ history: [Float], frameDuration: Double = 1.0 / 60, width: Int = 256, height: Int = 192) {
        history.withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> Void in
            layout(samples: b, frameDuration: frameDuration, width: width, height: height)
        }
    }

    func vertexCount() -> Int {
        let out = UnsafeMutablePointer<SpectrumVertex>.allocate(capacity: Self.maximumVertexCount)
        defer { out.deallocate() }
        return tessellate(into: out, capacity: Self.maximumVertexCount, gain: 1)
    }

    /// Distances between neighbouring points, the closing segment (last → first) last.
    func neighbourDistances() -> [Double] {
        (0..<pointCount).map { (j: Int) -> Double in
            let a = point(j), b = point((j + 1) % pointCount)
            return ((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y)).squareRoot()
        }
    }

    /// Largest neighbour distance (closing segment included) over the median.
    func seamRatio() -> Double {
        let d = neighbourDistances()
        let sorted = d.sorted()
        let median: Double = (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
        return (d.max() ?? 0) / median
    }

    var radii: [Double] { (0..<Self.windowSamples).map { (j: Int) -> Double in radius(j) } }
}
