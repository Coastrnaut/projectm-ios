# Contract: Tempo Source (SHOW-011)

Module `PerformanceControl` (no dependencies) and `PerformanceControlAnalysis` (AnalysisFeatures).
Every time is monotonic nanoseconds on the analysis bus's clock. Nothing here reaches projectM
(ADR-0008 decision 5).

## PerformanceControl

```swift
public struct TapTempoRules: Sendable, Hashable, Codable {
    public static let standard: TapTempoRules           // 4 taps, 60-200 BPM, 2 s pause, 8 taps, 0.5
    public var tapsToEstablish: Int
    public var minimumBPM: Double
    public var maximumBPM: Double
    public var pauseNanoseconds: UInt64
    public var maximumTaps: Int
    public var minimumEstimateConfidence: Double
}

public enum TapOutcome: Sendable, Hashable {
    case counting(taps: Int, of: Int)
    case established(bpm: Double)
    case refined(bpm: Double)
    case tooFast
    case tooSlow
}

public enum TempoOrigin: String, Sendable, Hashable, Codable { case manual, estimated, none }

public struct TempoEstimate: Sendable, Hashable, Codable {
    public init(bpm: Double, confidence: Double, beatNanoseconds: UInt64?)
}

public struct TempoSnapshot: Sendable, Hashable, Codable {
    public static let none: TempoSnapshot
    public let origin: TempoOrigin
    public let bpm: Double?
    public let confidence: Double
    public let periodNanoseconds: UInt64?
    public let anchorNanoseconds: UInt64?
    public func nextBeat(atOrAfter time: UInt64) -> UInt64?
    public func beatPhase(at time: UInt64) -> Double?
}

public struct TempoSource: Sendable {
    public init(rules: TapTempoRules = .standard)
    public var rules: TapTempoRules { get }
    public var snapshot: TempoSnapshot { get }      // the one read API (SHOW-011-R10)
    public var tapsInSequence: Int { get }          // 0 after reset
    public var hasManualTempo: Bool { get }
    @discardableResult public mutating func tap(at time: UInt64) -> TapOutcome
    public mutating func resetManual()              // clears override and sequence (SHOW-011-R8)
    public mutating func updateEstimate(_ estimate: TempoEstimate?)
}
```

Guarantees: deterministic (same calls, same results); `snapshot.origin == .manual` exactly from
the `tapsToEstablish`-th accepted tap of a sequence until `resetManual()`; a manual BPM is always
within the rules' range; after `resetManual()` the snapshot equals the one the estimate alone gives.

## PerformanceControlAnalysis

```swift
public struct TempoEstimateTracker: Sendable {
    public init(sampleRate: Double)
    public mutating func observe(_ frame: AnalysisFrame)
    public mutating func observe(_ event: AnalysisEvent)
    public var estimate: TempoEstimate? { get }      // nil without a tempo
    public mutating func clear()
}

/// Reads one bus subscription; not thread-safe (one owner, the main actor in the app).
public final class TempoSubscriptionReader {
    public init(subscription: AnalysisSubscription, sampleRate: Double)
    public func poll() -> TempoEstimate?             // drains events, reads the latest frame
}

/// Its own ANL-016 pipeline for when no other pipeline reads the analysis tap.
public final class TempoAnalyzer: @unchecked Sendable {
    public init() throws
    public let reader: TempoSubscriptionReader
    public func start(reader: any NormalizedPCMReader)   // idempotent
    public func stop()                                  // idempotent; synchronous
    public var isRunning: Bool { get }
}
```

## VisualBandFeed hook (additive)

```swift
extension LiveBandAnalyzer {
    public func subscribe(eventCapacity: Int = AnalysisSubscription.defaultEventCapacity) throws(AnalysisBusError) -> AnalysisSubscription
    public func unsubscribe(_ subscription: AnalysisSubscription)
    public var sampleRate: Double { get }
}
```

## App

- Controls overlay, both layouts: `tempoReadout` (label "Tempo", value "120 BPM, manual" /
  "126 BPM, detected" / "No tempo"), `tapTempo` (label "Tap tempo", value "Tap 2 of 4" or the
  tempo; hint "Tap in time with the music, four times, to set the tempo"), `resetTempo` (label
  "Reset tempo"; only while manual).
- Announcements: "Tempo set to 120 BPM", "Manual tempo cleared. Detected tempo 126 BPM",
  "Manual tempo cleared. No tempo", "Tap slower", "Tap faster".
- DEBUG launch argument `-uitestTapInterval <ms>`: every tap advances a synthetic clock by that
  many milliseconds.
