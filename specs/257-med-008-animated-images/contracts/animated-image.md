# Contract: Animated images (MED-008)

## A1 Import (`ImageSanitizer.sanitize`, format `.automatic`)

- Input passes `ImageIODecoder`'s checks for frame 0 first (size, structure, type, status, pixel count).
- Animated (D1) → `SanitizedImage` with `fileExtension == "png"`, `data` an APNG whose frame count is
  `min(frames, 600)`, every frame the same upright size ≤ 2048 px with frames × w × h ≤ 32 M, per-frame delay = the
  source's unclamped delay, loop count 0, no other properties. Over `maxFileBytes` after two halvings → `.tooLarge`.
- `.png` format (logos) and non-animated input → unchanged MED-001 behaviour.

## A2 Playback (`ImageLayerSource`)

- `content = .file(url)` of an APNG/GIF/HEICS/WebP animation → `state == .ready(width:height:)` (decoded size) once
  frame 0 is decoded; `animationFrameCount` = frame count (0 for a still).
- Frame for a render = `timeline.frameIndex(playhead.elapsed)`; Reduce Motion → 0. Missing texture → the last drawn
  frame; frames i and i + 1 are requested.
- The frame context's `reduceFlashing` selects the Reduce flashing timeline for that render, keeping the elapsed time.
- `renderDependencies`: time while animating (frames > 1, not Reduce Motion) or Ken Burns moving; else still.
- `animationCacheStatistics` → (budget, resident, peak, decodes, decoded size) and `shownFrameIndex` for tests and
  diagnostics; `isAnimating`.
- `waitUntilLoaded()` also drains the animation's decode queue.

## A3 Budget

- `ImageLayerSource(..., animationBudgetBytes:)` defaults to `AnimatedFrameBudget.current`. Peak accounted bytes ≤
  budget for every animation.
