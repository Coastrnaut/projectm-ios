# Contract: Layer render caching (CMP-013)

## Layer side (`LayerRenderCaching`, plain Swift protocol in `Compositor`)

```swift
public protocol LayerRenderCaching: AnyObject {
    /// Read once per frame, before `render`, on the compositor's thread. Must not allocate, lock with
    /// unbounded wait, log or do I/O (the same rules as `render`).
    var renderDependencies: LayerRenderDependencies { get }
    /// Called instead of `render` when the compositor reused the layer's last good picture.
    func renderReused(frame: LayerFrameContext)   // default: nothing
}
```

Rules for an adopter:
1. Declare `time`, `audio`, `modulation` or `externalInput` whenever `render` reads that input, or do
   not adopt. Unknown means render.
2. Bump `contentGeneration` or `parameterGeneration` for every change that alters the picture.
3. The generation reported must never be newer than what `render` would draw in the same frame.
4. Composite settings (opacity, transform, blend, mask, group, solo/mute) are not the layer's inputs.

## Compositor side

- Level 1: per layer and frame, `key = LayerRenderCacheKey(...)`; reuse iff the entry matches and the
  slots hold a last good picture (and DEBUG fault injection does not target the layer); else drop the
  entry, render, and store the key only on success. A reused layer's outcome is `.rendered`.
- Level 2: reuse the composite iff caching is on, the composite is valid, every `LayerDrawInput` and
  every group's shown opacity is unchanged. The flash guard, output pass, capture and recording always
  run.
- Epoch bump (all pictures invalid, composite invalid): `invalidateRenderCache()`, caching switched,
  a new output size, a pool purge seen at `tick`, an observed GPU error, a visual fault,
  `resetRenderHealth()`, a frame that returns false after the frame tick.
- Composite invalid only: `apply` of a changed stack, `setSoloMute`.
- Entry dropped: new pictures or `prepare` for that layer, any frame where the layer is not reused.

## Diagnostics

`renderCacheEpoch`, `renderCacheHits`, `compositeReused`, `compositeReuses`, `wasReused(layer:)`;
`ImageLayerSource.renderCount`, `TextLayerSource.renderCount` (actual renders; `framesShown` counts
reused frames too).
