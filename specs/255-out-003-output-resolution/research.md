# Research: OUT-003 Independent Output Resolution

## OUT-003-D1: Where the pixel count is set

- **Decision**: Override the display scale trait of the visual view held by an external slot (`visual.traitOverrides.displayScale`), then lay the visual out again.
- **Rationale**: Every visual (ANGLE renderer, GLES renderer, native spectrum, Camera, Photo, Video, Text hosts) computes `drawable = bounds × traitCollection.displayScale × QualityGovernor.renderScale` in its layout pass. Overriding the trait changes only that product; bounds, centre and transform stay in points, so the scene's normalised coordinates, OUT-004's placement and the compositor's layer stack are untouched. One change covers all visual kinds and needs no renderer edit. The DEBUG fake display already uses the same trait override on its slot (display scale 1).
- **Alternatives considered**: (a) setting `contentScaleFactor` directly — each visual overwrites it on layout; (b) a per-renderer API — seven call sites, two packages; (c) scaling the view's bounds down and transforming up — changes scene coordinates (violates the acceptance).

## OUT-003-D2: Which view carries the override

- **Decision**: The held visual view, not the slot. The slot keeps its own (native or test) display scale, so `slot.geometry` still reports the screen's real scale to the routing (OUT-001-R7) and no feedback loop arises. The device slot and `removeVisuals()` remove the override, so a visual moving back renders at the device scale.
- **Alternatives considered**: overriding the slot itself — changes the geometry the slot reports and the routing's notion of the screen.

## OUT-003-D3: The arithmetic

- **Decision**: native pixels `(W·s, H·s)` for slot points `(W, H)` and native scale `s`. Factor `f = min(1, choice, budget)`: Native 1; 1080p `min(1920/long, 1080/short)`; 720p `min(1280/long, 720/short)`; Custom `p/100` with `p` clamped to 50…100. Budget `min(maxSide/long, sqrt(maxPixels/(long·short)))`. Output scale `s·f`, pixel size `round(W·s·f) × round(H·s·f)`; one more floor step guards rounding above the budget. Clamped = the budget factor is the smallest and below the other limits.
- **Rationale**: a uniform scale keeps the shape; never upscales; matches REC-014's budget semantics.

## OUT-003-D4: The budget

- **Decision**: `RecordingOutputCap.device(physicalMemory:maxTextureSide: 16_384)` — the same function REC-014 uses for exports (compact under 6 GB: 2560 / 2560 × 1440; regular 4096 / 3840 × 2160), passed to the pure type as `ExternalPixelBudget(maxSide:maxPixels:)`.
- **Rationale**: one memory policy per device class across the app; no new package dependency for `PresentationLifecycle`.

## OUT-003-D5: Live change and recording hold

- **Decision**: The coordinator stores `resolution` and pushes it with OUT-004's correction in `pushCorrection()` (skipped while a recording holds the placement, applied when it ends). The slot applies it in `applyPlacement()` inside the call; the visual's next layout pass changes its drawable. Nothing restarts.
- **Rationale**: REC-003-R11 stops a recording whose picture size changes; deferring keeps it running.

## OUT-003-D6: Settings UI

- **Decision**: In Settings › External Display, a "Resolution" picker (Native, 1080p, 720p, Custom) and, only for Custom, a "Scale" slider 50…100 % in 5 % steps using ACC-005's `.accessibleParameter`. The footer gains one sentence.
