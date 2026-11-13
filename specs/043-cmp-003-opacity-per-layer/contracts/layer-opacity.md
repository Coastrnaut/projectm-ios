# Contract: Layer opacity (CMP-003)

Extends `specs/040-cmp-002-ordered-layer-stack/contracts/layer-stack.md`. Target `Compositor`.

## Values (CPU, every host)

```swift
public enum LayerOpacityCurve: Sendable, Equatable { case linear, easeInOut }

public enum LayerOpacityError: Error, Equatable, Sendable {
    case nonFiniteTarget, nonFiniteDuration, negativeDuration
}

public struct LayerOpacityTransition: Sendable, Equatable {
    public let duration: Double          // seconds, finite, >= 0
    public let curve: LayerOpacityCurve
    public init(duration: Double, curve: LayerOpacityCurve = .linear) throws(LayerOpacityError)
    public static let immediate: LayerOpacityTransition
}

public struct LayerOpacityAnimator: Sendable, Equatable {
    public init(opacity: Double)                       // clamped; non-finite → 1
    public private(set) var value: Double              // shown opacity
    public private(set) var target: Double
    public var isAnimating: Bool
    public mutating func setOpacity(_ target: Double, duration: Double,
                                    curve: LayerOpacityCurve = .linear) throws(LayerOpacityError)
    public mutating func setOpacity(_ target: Double, transition: LayerOpacityTransition)
    @discardableResult public mutating func advance(by frameDuration: Double) -> Double
}

extension LayerCompositeSettings {
    public var isSupportedByCompositor: Bool   // normal blend and identity transform; any opacity
}
```

Rules:

1. A finite target is clamped to 0…1; a non-finite target, a non-finite or negative duration is
   refused with the error and nothing changes.
2. A new segment starts at the current `value` (continuity); `duration` 0 sets `value = target` at
   once.
3. `advance(by:)` adds `max(dt, 0)` (non-finite → 0). While `elapsed < duration`, `value` is
   `start + curve(elapsed / duration) · (target − start)` clamped to the segment's ends; from
   `elapsed ≥ duration` on, `value == target` exactly.
4. For a fixed segment, `value` is monotonic in the summed time for both curves.

## Compositor (Metal)

```swift
public func apply(_ stack: LayerStack, opacityTransition: LayerOpacityTransition = .immediate,
                  makeLayer: LayerFactory) throws(CompositorError)
```

1. Entries with a non-normal blend or a non-identity transform are refused
   (`unsupportedCompositeSettings(index:)`); any opacity is accepted.
2. A kept layer whose entry opacity differs from the applied one is retargeted with
   `opacityTransition`; nothing is created, prepared or released for it. A stack equal to the
   applied one is still a no-op (an unchanged opacity does not restart a fade).
3. A new layer starts at its entry's opacity (no fade). `init(device:layers:)` layers start at their
   `compositeSettings.opacity`.
4. Per frame every layer's animator advances by the frame's `frameDuration`, then each shown
   picture is drawn with its premultiplied channels × the animator's value; a value of exactly 0
   skips the draw (the layer still rendered).
5. Opacity 1 output is bit-identical to CMP-002's; opacity changes never reset the flash guard.
