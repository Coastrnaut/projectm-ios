# Contract: LinearMapping (Packages/ParameterGraph)

```swift
public struct LinearMapping: Sendable, Hashable {
    public var inputMinimum: Double
    public var inputMaximum: Double
    public var outputStart: Double
    public var outputEnd: Double
    public init(inputMinimum: Double = 0, inputMaximum: Double = 1, outputStart: Double, outputEnd: Double)
    public static let identity: LinearMapping            // 0…1 → 0…1
    public var isValid: Bool
    public var isInverted: Bool
    public var isConstant: Bool
    public func position(of input: Double) -> Double     // L1
    public func interpolate(_ position: Double) -> Double // L2, L3
    public func map(_ input: Double) -> Double            // L4
    public static func clampedPosition(_ position: Double) -> Double
    public static func interpolate(from start: Double, to end: Double, at position: Double) -> Double
}
extension AudioFeatureBinding { public var mapping: LinearMapping { get set } }
```

- **L1 position**: `(input − inputMinimum) / (inputMaximum − inputMinimum)`, then
  `clampedPosition`: NaN → 0, below 0 → 0, above 1 → 1. Never traps (MOD-003-R2, R8).
- **L2 exact ends**: `interpolate(0) == outputStart` and `interpolate(1) == outputEnd` for every
  finite pair of ends (MOD-003-R3).
- **L3 bounded and monotonic**: for p in 0…1 the result lies in `min(start, end)…max(start, end)`
  and is non-decreasing in p when `end ≥ start`, non-increasing otherwise; positions are clamped
  first (MOD-003-R4). Formula: research MOD-003-D1.
- **L4 map**: `map(x) == interpolate(position(of: x))` (MOD-003-R5).
- **L5 MOD-002 equality**: for ends of opposite sign or including zero, `interpolate(p)` equals
  `(1 − p)·start + p·end` bit for bit; otherwise within 2 units in the last place; at p = 0 and 1
  always equal (MOD-003-R7). The modulator's results for MOD-002's fixtures are unchanged.
