# Contract: AUD-008 Input Trim

## C1: `InputTrim` (AudioCore, public enum)

```swift
public enum InputTrim {
    public static let minimumDecibels: Float      // -12
    public static let maximumDecibels: Float      // 24
    public static let defaultDecibels: Float      // 0
    public static let rampFrames: Int             // 2_048
    public static let kneeLevel: Float            // 0.5
    public static let clipStart: Float            // 1.25
    public static func clamped(_ decibels: Float) -> Float
    public static func linearGain(decibels: Float) -> Float
    public static func softClip(_ value: Float) -> Float
    public static var maximumRampStep: Float { get }
}
```

`softClip(v)`: NaN → 0; |v| ≤ 0.5 → v; |v| ≥ 1.25 (including ±∞) → ±1; otherwise
sign(v)·(0.5 + 0.5·(u − 4u³/27)), u = (|v| − 0.5)/0.5. Monotonic, odd, continuous with continuous
slope, output in [−1, 1].

## C2: `InputTrimControl` (AudioCore, public final class, Sendable)

```swift
public init(decibels: Float = InputTrim.defaultDecibels)
public var decibels: Float { get set }   // stores clamped; lock-free; any thread
```

## C3: `InputTrimProcessor` (AudioCore, public struct)

```swift
public init(decibels: Float)                         // settled at the target
public var gain: Float { get }                       // current linear gain
public var isUnity: Bool { get }                     // gain == 1 and no ramp
public mutating func setTarget(decibels: Float)      // no-op if equal to the current target; else a new ramp
public mutating func snap(decibels: Float)           // settle at the target now
public mutating func process(_ samples: UnsafeMutablePointer<Float>, frames: Int, channels: Int)
```

`process` returns at once when `isUnity` (bit-exact). Otherwise per frame: advance the ramp (the
last ramp frame sets gain = target exactly), then y = softClip(x·gain) for each channel sample.

## C4: `InputTrimReader` (AudioCore, public final class: NormalizedPCMReader, AnalysisSessionReporting)

```swift
public init(_ reader: any NormalizedPCMReader, control: InputTrimControl)
public func read(into dst: UnsafeMutablePointer<Float>, maxFrames: Int) -> Int
public var analysisSessionGeneration: UInt64 { get }   // forwarded; 0 when the wrapped reader reports none
```

Per read: n = wrapped.read(...); if n == 0 return 0. If the wrapped generation differs from the last
one seen → snap to the control's target; else setTarget(control's target). Then
`process(dst, frames: n, channels: 2)`; return n. One consumer thread only (like the tap).

## C5: App

- `InputTrimSetting.key = "settings.inputTrim.decibels"`; `decibels` (Double) clamps to −12…24,
  rounds to whole dB, NaN → 0, stores and sets `control.decibels`; `reset()` sets 0.
- `InputTrimSetting.text(for:)`: "+6 dB", "0 dB", "−12 dB" (U+2212 minus sign).
- `AppCoordinator.trimmedAnalysisTap`: `manager.analysisTap` wrapped in a new `InputTrimReader`
  sharing `inputTrim.control`; every former `manager.analysisTap` consumer uses it.
- Settings "Audio Analysis" section: Slider (`inputTrimSlider`, label "Input trim", value the
  text), readout (`inputTrimValue`), Button "Reset to 0 dB" (`inputTrimReset`).
