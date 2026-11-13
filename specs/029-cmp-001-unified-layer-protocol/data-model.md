# Data Model: CMP-001 Unified Layer Protocol

All entities are in-memory values or objects; nothing is persisted (no storage, no migration).
Full signatures: [contracts/layer-source.md](contracts/layer-source.md).

| Entity | Fields | Rules |
|---|---|---|
| LayerPictureDescriptor | width, height (pixels ≥ 1), format (`rgba16Float`), colorSpace (`linearSRGB`), alpha (`premultiplied`), origin (`topLeft`) | Equal descriptors never cause a reallocation; a different width or height reallocates every picture once (CMP-001-R6). |
| LayerFrameContext | presentationTimeNanoseconds, frameIndex, frameDuration, outputWidth, outputHeight, contentScale, reduceFlashing | Produced by LayerFrameClock: frameIndex +1 per rendered frame from 0; time never decreases (an earlier time is replaced by the previous one); duration = Δt clamped 0…0.1 s, 0 on frame 0; non-finite or ≤ 0 scale reads 1 (CMP-001-R3). |
| LayerAudioContext | frame (AnalysisFrame?), bands (≤ 128 values), events (≤ 64, oldest first), droppedEvents | Views into LayerAudioBuffer storage, valid during one `composite` call; `.empty` has no frame, no bands, no events (CMP-001-R4). |
| LayerAudioBuffer | band storage 128, event ring 64, frame, counts | `update(from:)`/`set(…)` never allocate; more than 64 new events keep the newest 64 and add the rest to droppedEvents; bands beyond 128 are ignored. |
| LayerFallback | `.transparent`, `.lastGoodFrame` | Declared by the layer; read once at compositor init. |
| LayerSourceError | notReady, frameSkipped, unsupportedPicture, resourceUnavailable(String), engineFailure(String) | Typed throws; no allocation for payload-free cases. |
| LayerOutcome | rendered, fallbackTransparent(error), fallbackLastGood(error), unavailable(error), notRendered | One per layer per frame, kept in preallocated storage (CMP-001-R7, R8). |
| LayerCompositeSettings | opacity (0…1), blendMode (`.normal`), transform (2D affine a, b, c, d, tx, ty) | CMP-001 accepts only opacity 1, normal, identity; anything else is rejected at init (CMP-001-R11). |
| LayerSlots | per layer: picture count (1 or 2), index to render into, index of the last good picture (or none), available flag | Transitions below. |

## LayerSlots transitions (per layer)

- **prepare(ok)** → available; last good = none; render index = 0.
- **prepare(failed)** → unavailable (outcome `.unavailable`), skipped until the next size change or
  `retryUnavailableLayers()`.
- **frame succeeded** → shown picture = render index; last good = render index; with two pictures
  render index flips to the other one.
- **frame failed, `.transparent`** → nothing shown; render index unchanged.
- **frame failed, `.lastGoodFrame`** → shown = last good (none → nothing shown, outcome still
  `.fallbackLastGood`); render index unchanged (the good picture is never the render target).
- **resize** → like prepare; last good = none (old pictures are released).
