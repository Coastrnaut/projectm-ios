# Contract: spectrum analyzer (ANL-001)

Package `AnalysisFeatures` (depends on AudioCore). Swift 6, strict concurrency. Not linked by the app
in this row.

## Public API

```swift
public enum FFTSize: Int, CaseIterable, Sendable { case n512 = 512, n1024 = 1024, n2048 = 2048, n4096 = 4096, n8192 = 8192
    public init?(samples: Int); public static let maximum: FFTSize
    public var log2: Int; public var binCount: Int
    public func binWidth(sampleRate: Double) -> Double
    public func frequency(ofBin: Int, sampleRate: Double) -> Double
    public func nearestBin(toFrequency: Double, sampleRate: Double) -> Int }

public enum ChannelMode: Sendable { case mid, left, right }
public struct SpectrumConfiguration: Sendable, Hashable { size, hop, sampleRate, channelMode; throwing init }
public enum SpectrumConfigurationError: Error, Equatable { case hopOutOfRange(hop: Int, size: Int), invalidSampleRate(Double) }

public enum SpectrumBackend: Sendable { case automatic, accelerated, portable
    public static var isAcceleratedAvailable: Bool }

public final class SpectrumAnalyzer {          // not Sendable: confined to one worker
    public init(backend: SpectrumBackend = .automatic)   // preallocates every size
    public var resolvedBackend: SpectrumBackend { get }   // .accelerated or .portable
    /// Windowed magnitudes of `samples[0..<size]` into `output[0..<size.binCount]`. No allocation.
    public func magnitudes(of samples: UnsafePointer<Float>, size: FFTSize, into output: UnsafeMutablePointer<Float>)
    /// Convenience for tests and off-real-time callers (allocates the result).
    public func magnitudes(of samples: [Float], size: FFTSize) -> [Float]
}

public final class SpectrumStream {            // not Sendable: confined to one worker
    public static let fifoCapacity = 16_384
    public init(configuration: SpectrumConfiguration, backend: SpectrumBackend = .automatic,
                clock: @escaping @Sendable () -> UInt64 = { MonotonicClock.nowNanoseconds() })
    public private(set) var configuration: SpectrumConfiguration
    public var resolvedBackend: SpectrumBackend { get }
    public var bufferedSamples: Int { get }
    public func setConfiguration(_: SpectrumConfiguration)      // no allocation, keeps FIFO
    public func reset()
    @discardableResult public func append(interleaved: UnsafePointer<Float>, frames: Int, channels: Int) -> Int
    @discardableResult public func append(mono: UnsafePointer<Float>, count: Int) -> Int
    public func nextFrame() -> SpectrumFrame?                     // computes into `magnitudes`
    public var magnitudes: UnsafeBufferPointer<Float> { get }    // last frame, valid until next call
    public func copyMagnitudes(into: UnsafeMutablePointer<Float>)
    /// Reads stereo frames from `reader` until it is empty, calling `body` for each frame.
    @discardableResult public func pull(from reader: some NormalizedPCMReader,
                                        _ body: (SpectrumFrame, UnsafeBufferPointer<Float>) -> Void) -> Int
}

public struct SpectrumFrame: Sendable, Equatable { index: Int64; size: FFTSize; sampleRate: Double; timestampNanoseconds: UInt64 }

public enum SpectrumMath { public static let floorDecibels: Float = -120
    public static func decibels(_ magnitude: Float) -> Float }
```

AudioCore additions (`NormalizedPCMRing`):

```swift
public static let analysisTapDefaultCapacityFrames = 22_050
public init(analysisTapCapacityFrames: Int = 0)
public var analysisTap: (any NormalizedPCMReader)? { get }
public var analysisTapAvailableFrames: Int { get }
public var analysisTapDroppedFrames: Int { get }
```

## Guarantees

1. Output length `size.binCount`; values finite and ≥ 0 for any input (sanitized, research ANL-001-D5).
2. Normalization: bin-centred sine amplitude A reads A (±1e-4 relative); constant A reads A at bin 0.
3. Determinism: same input, size and backend → bit-identical output, on fresh or reused instances.
4. Backends agree within `1e-5·peak + 1e-6` per bin and have the same peak bin for tonal input.
5. The per-frame paths (`magnitudes(of:size:into:)`, `nextFrame`, `append`, `pull`, `setConfiguration`)
   do not allocate, lock, log or do I/O. Allocation happens only in the initializers and the array
   convenience.
6. Frames are produced only for whole windows; frame `i+1` starts `hop` samples after frame `i`
   (with the hop configured when frame `i` was produced).
7. Nothing from this package is passed to projectM (ANL-001-R12).
8. With `analysisTapCapacityFrames == 0` the normalized ring behaves exactly as before; with a tap,
   `read` on the main ring returns the same frames whether or not the tap is read.

## Errors

- `SpectrumConfigurationError` from the configuration initializer only.
- An unsupported size cannot be expressed (`FFTSize(samples:)` returns nil).
- `append` accepting fewer frames than offered is not an error: the caller calls `nextFrame()`
  (or uses `pull`) to make room.

## Amended by ANL-004 (2026-11-13)

Two additive changes; defaults keep the behavior above (`specs/018-anl-004-spectral-flux-onset-detector/contracts/onset-detector.md`):

- `SpectrumFrame` carries `hop: Int`, the samples from its first sample to the next frame's (the
  hop configured when it was produced). The public initializer gains `hop: Int? = nil` (nil =
  size/2), so existing call sites compile unchanged.
- `SpectrumStream.init(…, leadIn: SpectrumLeadIn = .none)` and `leadIn`: with `.silence` the FIFO
  starts (at init and after `reset()`) with `size − hop` zeros of the configuration current then,
  and the first frame index is `−(size − hop)`. Guarantee 6 holds; indices may be negative only
  during the lead-in.
