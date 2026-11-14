# Contract: ANL-010 Spectral Centroid

## C1 — SpectralBinRange (AnalysisFeatures)

```swift
public struct SpectralBinRange: Sendable, Hashable {
    public let first: Int
    public let last: Int
    public init?(lowerFrequency: Double, upperFrequency: Double, size: FFTSize, sampleRate: Double)
    public var count: Int { get }
}
```

- `first ≥ 1` always; `last ≤ size.rawValue / 2`; nil when no whole bin lies in the range.
- Pure and allocation-free; reused by ANL-011 and ANL-012.

## C2 — SpectralCentroidEstimator (AnalysisFeatures)

```swift
public struct SpectralCentroidConfiguration: Sendable, Hashable {
    public static let standard: SpectralCentroidConfiguration
    public init(sampleRate: Double = 44_100, lowerFrequency: Double = 20, upperFrequency: Double? = nil,
                floorDecibels: Float = -70, normalizationLower: Double = 50,
                normalizationUpper: Double = 10_000) throws(SpectralCentroidConfigurationError)
    public func normalized(hz: Double) -> Double        // clamp(log2(hz/lo)/log2(hi/lo), 0, 1); 0 for non-finite or ≤ 0
    public var floorPower: Double { get }
}
public struct SpectralCentroidReading: Sendable, Hashable { hz, normalized: Float; hasSignal: Bool; static let none }
public struct SpectralCentroidEstimator: Sendable {
    public init(configuration: SpectralCentroidConfiguration = .standard)
    public private(set) var reading: SpectralCentroidReading
    @discardableResult
    public mutating func process(_ frame: SpectrumFrame, magnitudes: UnsafeBufferPointer<Float>) -> SpectralCentroidReading
    public mutating func reset()
    /// Σ f·m² / Σ m² and Σ m² over `range`; (0, 0) when the power is 0.
    public static func measure(magnitudes: UnsafeBufferPointer<Float>, size: FFTSize, sampleRate: Double,
                               range: SpectralBinRange) -> (hz: Double, power: Double)
}
```

- Every value returned is finite; `normalized` is in 0…1.
- No allocation, lock, log, clock or I/O.

## C3 — Analysis bus (AnalysisFeatures)

- `AnalysisPipelineConfiguration.centroid` (default `.standard`); a sample rate differing from the
  spectrum's throws `.sampleRateMismatch`.
- Every `AnalysisFrame` carries `centroidHz` and `centroid` from the estimator for that spectrum.
- Every session start resets the estimator (the first frames of a session read 0 until signal).

## C4 — MOD-002 / SHD-009 (ParameterGraph)

- `AudioFeatureSource.centroid.id == "audio.centroid"`; `AudioFeatureSource(id: "audio.centroid") == .centroid`.
- `value(in:)` = `frame.centroid` as Double; nil or non-finite reads 0.
- `ExpressionOpcode.centroid.rawValue == 15`, stack effect +1; `audio.centroid` in a formula
  compiles to it and reads the frame's centroid.

## C5 — App

- `NativeSpectrumHost.applyModulation(bands:kick:centroid:timeNanoseconds:)`; the frame loop passes
  the newest bus frame's normalized centroid (0 after a pause restart).
