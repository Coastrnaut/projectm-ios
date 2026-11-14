# Contract: Scene Transition Bus (CMP-014)

## Compositor.encodeScene

```swift
public func encodeScene(width: Int, height: Int, commandBuffer: MTLCommandBuffer,
                        presentationTimeNanoseconds: UInt64, contentScale: Double,
                        reduceFlashing: Bool, audio: LayerAudioContext) -> MTLTexture?
```

Runs the stack phase of one frame exactly as `composite(into:)` (frame tick, render health, layer
renders, CMP-013 reuse, pool tick, command-buffer watch) and returns the finished composite
(`rgba16Float`, linear premultiplied, owned by the compositor, valid in this command buffer until the
compositor's next frame). No flash guard and no output pass run. nil when nothing could be encoded.
`composite(into:)` is unchanged.

## SceneTransitionBus

| Call | Effect |
|---|---|
| `show(_ scene)` | Cut: `scene` is live; any outgoing scene and the blend target are released. |
| `transition(to:spec:reduceMotion:)` | Resolves the spec (Reduce Motion → cut). Instant → `show`. A running transition is finished first (snap). Else the live scene becomes outgoing, `scene` is live, the clock starts at the next frame. |
| `cancel()` | Outgoing scene live again; incoming scene and blend target released. |
| `finishNow()` | Incoming scene stays live; outgoing scene and blend target released. |
| `pause()` / `resume()` | The next frame after resume adds no time. |
| `encodeFrame(into:…)` | One shown frame: scene composite(s) → (mix) → the bus's flash guard → output pass. False, encoding nothing visible, for no live scene, an empty output or an unsupported format. |
| `encodeOutput(into:commandBuffer:)` | The last frame's output pass again into another target (recording, second display), cropped from the top left. |

Guarantees: frames at progress 0 and ≥ 1 are byte-identical to the scene rendered alone through
`composite(into:)` with the same guard history; the blend target is the only texture the bus checks out
and it is returned at the end, on cancel, interruption, size change and deinit; every shown frame goes
through the guard; at most two scenes are held.
