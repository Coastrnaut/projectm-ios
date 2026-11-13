# Contract: Layer stack and stack apply (CMP-002)

Module `Compositor`. The stack is CPU (every host); `apply` is part of the Metal compositor.

## Order

Index 0 is the **bottom** layer; the last index is drawn **on top**. The compositor draws entries in
index order with premultiplied "over" (CMP-001). `add` without an index puts the layer on top.

## LayerStack

```swift
public struct LayerStack: Equatable, Sendable {
    public static let maximumLayerCount: Int            // 8
    public private(set) var entries: [LayerStackEntry]
    public init()
    public var count: Int { get }
    public func index(of id: LayerInstanceID) -> Int?
    public func entry(_ id: LayerInstanceID) -> LayerStackEntry?
    @discardableResult
    public mutating func add(_ descriptor: LayerDescriptor, settings: LayerCompositeSettings = .init(),
                             at index: Int? = nil) throws(LayerStackError) -> LayerInstanceID
    @discardableResult
    public mutating func remove(_ id: LayerInstanceID) throws(LayerStackError) -> LayerStackEntry
    @discardableResult
    public mutating func duplicate(_ id: LayerInstanceID) throws(LayerStackError) -> LayerInstanceID
    public mutating func move(_ id: LayerInstanceID, to index: Int) throws(LayerStackError)
}
```

- Every operation either succeeds or throws and leaves the stack unchanged.
- `duplicate` inserts the copy at the original's index + 1 with a new ID and equal descriptor and
  settings.
- `move(id, to: i)` removes the entry and inserts it so that it ends at index `i`.
- IDs come from a per-stack counter starting at 1 and are never reused. Equality compares entries.
- Kind limits: a kind with `maximumInstances = n` may appear at most n times (`.camera`: 1).

## Compositor

```swift
public typealias LayerFactory = (LayerStackEntry) throws(LayerSourceError) -> any LayerSource
public convenience init(device: MTLDevice) throws(CompositorError)       // empty stack
public func apply(_ stack: LayerStack, makeLayer: LayerFactory) throws(CompositorError)
public private(set) var appliedStack: LayerStack?
public func layerID(at index: Int) -> LayerInstanceID?
public private(set) var layerPreparations: Int                            // diagnostics, tests
// New CompositorError case:
case layerCreationFailed(index: Int, LayerSourceError)
```

Call `apply` on the compositor's thread, between frames (never while encoding one).

1. An equal stack (`appliedStack == stack`) changes nothing: no factory call, no prepare, no
   release.
2. An entry whose settings are not the identity values → `unsupportedCompositeSettings(index:)`.
3. IDs already applied keep their layer object, pictures, slots (last good frame) and prepared
   state, at their new index. The factory is called once per new ID, in index order; a throw →
   `layerCreationFailed(index:, error)`.
4. A factory result identical (`===`) to another entry's layer → `duplicateLayer(index:)`.
5. On any error nothing changes (the previous stack stays applied).
6. New layers are prepared now when the compositor has an output size (their pictures are created
   now), otherwise with the first frame. A failed prepare makes that layer `unavailable` (CMP-001).
7. Layers whose IDs are gone are released (the compositor holds no reference afterwards). The
   compositor calls nothing on a released layer: whoever owns a layer with outside resources (the
   camera's capture session) stops it before or after the apply.
8. The flash guard's history is kept.
9. `composite` at a steady size creates no pictures (unchanged CMP-001-R9).

`init(device:layers:)` remains: such layers have no ID and are released by the first `apply`.

## Kinds declared by layer targets

| Kind | Identifier | Max instances | Module |
|---|---|---|---|
| `.camera` | `camera` | 1 | CameraLayer |
| `.circularSpectrum` | `spectrum.circular` | — | SpectrumLayers |
| `.linearSpectrum` | `spectrum.linear` | — | SpectrumLayers |
