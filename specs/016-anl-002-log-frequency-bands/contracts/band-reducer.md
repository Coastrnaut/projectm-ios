# Contract: band reducer (ANL-002)

Package `AnalysisFeatures` (extends ANL-001's `contracts/spectrum-analyzer.md`; that contract is
unchanged). Swift 6, strict concurrency. Not linked by the app in this row.

## Public API

```swift
public enum BandCount: Int, CaseIterable, Sendable, Hashable { case b16 = 16, b32 = 32, b64 = 64, b128 = 128 }

public enum BandLayoutError: Error, Equatable, Sendable { case invalidSampleRate(Double) }

public struct BandLayout: Sendable, Equatable {
    public static let lowerEdgeHz: Double = 20
    public static let upperEdgeLimitHz: Double = 20_000
    public static let minimumSampleRate: Double = 8_000
    /// Equivalent noise bandwidth of the periodic Hann window, in bins.
    public static let hannEquivalentNoiseBandwidth: Double = 1.5

    public init(bandCount: BandCount, size: FFTSize, sampleRate: Double) throws(BandLayoutError)
    public let bandCount: BandCount; public let size: FFTSize; public let sampleRate: Double
    public var lowerEdge: Double { get }; public let upperEdge: Double
    public let edges: [Double]                                  // bandCount + 1
    public func lowerEdge(ofBand: Int) -> Double; public func upperEdge(ofBand: Int) -> Double
    public func centerFrequency(ofBand: Int) -> Double          // geometric
    public func widthInBins(ofBand: Int) -> Double
    public func binRange(ofBand: Int) -> Range<Int>
    public func weights(ofBand: Int) -> [Float]                 // allocates; inspection only
    public func band(containingFrequency: Double) -> Int?
    public func ownerBand(ofBin: Int) -> Int?
}

public final class BandReducer {                                // not Sendable: one worker
    public init(sampleRate: Double = 44_100, backend: SpectrumBackend = .automatic) throws(BandLayoutError)
    public let sampleRate: Double
    public let resolvedBackend: SpectrumBackend
    public func layout(bandCount: BandCount, size: FFTSize) -> BandLayout
    /// `magnitudes[0..<size.binCount]` (ANL-001 linear) → `output[0..<bandCount.rawValue]`. No allocation.
    public func reduce(magnitudes: UnsafePointer<Float>, size: FFTSize, bandCount: BandCount,
                       into output: UnsafeMutablePointer<Float>)
    /// Convenience (allocates); `magnitudes.count` must equal `size.binCount`.
    public func reduce(_ magnitudes: [Float], size: FFTSize, bandCount: BandCount) -> [Float]
}

public enum BandScale: Sendable, Hashable { case linear(reference: Float), decibels(floorDecibels: Float) }

public enum BandMath {
    public static let defaultFloorDecibels: Float = -80
    public static func normalizedLinear(_ value: Float, reference: Float = 1) -> Float
    public static func normalizedDecibels(_ value: Float, floorDecibels: Float = defaultFloorDecibels) -> Float
    public static func normalize(_ values: UnsafeMutablePointer<Float>, count: Int, scale: BandScale)
}
```

## Guarantees

1. Edges: `edges[i] = 20 · (upper/20)^(i/B)`, upper = min(20,000, R/2); band b = [edges[b], edges[b+1]).
2. Weights: bin k ≥ 1 covers one bin width centred on it (bin 1 from 0 Hz, Nyquist bin up to R/2);
   DC contributes nothing; weight = fraction of the bin's interval inside the band. Every band of
   every layout has at least one bin with weight > 0.
3. Value: `sqrt(Σ w·m² / (1.5 · min(1, W_b)))`; a sine of amplitude A wholly inside a band at least
   one bin wide reads A (±2 % where its main lobe ±2.5 bins lies inside the band).
4. Zero in → +0.0 out in every band; non-finite or negative magnitudes count as 0; magnitudes are
   clamped to 1e15; output finite and ≥ 0 for any input.
5. Determinism: same input, layout and backend → bit-identical output.
6. Backends agree within `1e-5·max(output) + 1e-7` per band.
7. `reduce(magnitudes:size:bandCount:into:)` and `BandMath.normalize` do not allocate, lock, log or do
   I/O; all 20 layouts exist after `init`.
8. Sub-bin bands do not conserve energy (research ANL-002-D4); consumers needing exact energy sums use
   bands at least one bin wide (`widthInBins ≥ 1`).
9. Nothing from this package is passed to projectM (ANL-002-R13).

## Errors

- `BandLayoutError.invalidSampleRate` from `BandLayout.init` and `BandReducer.init` (rate < 8,000 or
  not finite).
- Band and bin indices out of range in the inspection queries are programming errors (precondition).
