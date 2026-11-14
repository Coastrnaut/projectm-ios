# ADR-0040: Layer Render Caching Is Opt-In, Keyed by Input Generations, Bit-Identical

- **Status**: Accepted 2026-11-14 (decided by Claude under the owner's best-judgement rule, owner
  rule 4)
- **Feature**: CMP-013 (`specs/113-cmp-013-render-caching`)
- **Constitution**: VI (modular boundaries: each layer declares its own inputs), X (evidence-based
  quality; an ADR for a rule every future layer must follow)
- **Builds on**: ADR-0013 (unified layer protocol), CMP-002 (stack), CMP-012 (solo/mute), PERF-004 and
  PERF-006 (texture pool, memory pressure), PERF-014 (render health), FX-019 (composite flash guard),
  REC-001/REC-003 (capture, recording)
- **Amends**: ADR-0013's layer contract gains an optional render-dependency declaration

## Context

Every layer rendered its whole picture every frame and the whole stack was composited every frame. A
photo or a text overlay never changes between frames, yet it was redrawn 60 or 120 times a second.
Skipping that work is only safe if nothing that can change the picture is missed: a stale picture is a
visible bug, extra work is not.

## Decision

1. **Opt-in, unknown means render.** A layer may adopt `LayerRenderCaching` and return, each frame, a
   `LayerRenderDependencies` value: flags for time, audio, modulation (MOD-002 bindings) and external
   input (camera, video frames), plus a content generation and a parameter generation. Only a layer with
   no flag set is cacheable. A layer that does not adopt the protocol renders every frame. In CMP-013
   only the photo (MED-001) and text (MED-009) layers adopt it.
2. **The key is the set of input generations**: content and parameter generations, the picture
   description (size, format, colour space), the frame context's content scale and Reduce flashing, and
   the compositor's cache epoch. Time terms are never in the key (a cacheable layer must not read them).
   Composite placement (opacity, transform, blend, mask, group, solo/mute) is not a layer input; a fit
   applied inside the layer's picture (CMP-006) is a parameter of that layer.
3. **Level 1, layer pictures**: equal key and a last good picture → no render call, that picture is
   shown and the layer is told (`renderReused`); otherwise the entry is dropped, the layer renders, and
   only a successful render stores the key. No extra texture: the reused picture is the layer's own.
4. **Level 2, the composite**: when the composite is valid and every layer's draw input (picture drawn
   from or none, shown opacity, reused) and every group's shown opacity is unchanged, the previous
   composite is kept and only the layer passes are skipped. The flash guard, the output pass, frame
   capture and recording run every frame on it (the envelope must see every frame's duration; the
   caller's drawable is new each frame). Each compositor (the external display has its own) applies
   the rule independently.
5. **One epoch for global invalidation**: a new output size, a pool purge (memory warning), an observed
   GPU error, a visual fault, a render-health reset, caching switched, an explicit
   `invalidateRenderCache()`, and any frame that returns without finishing. Stack applies and solo/mute
   changes invalidate the composite only.
6. **Bit-identical**: output with caching on equals caching off, byte for byte; caching can be switched
   off per compositor (on by default) as a kill switch.

## Rules for a layer that adopts the protocol

- Declare every per-frame input it reads, or do not adopt.
- Bump a generation for every change that alters the picture.
- Never report a generation newer than what `render` draws in the same frame (take asynchronously
  loaded content the same way in the declaration and in `render`).

## Consequences

- A static photo renders once over ten frames; a fit or content change renders exactly once
  (`RenderCacheCompositeTests`, docs/test-reports/render-caching.md).
- A static-heavy stack (6 layers at 1080p) costs about 0.05 ms of Mac GPU time per frame instead of
  about 0.54 ms (not device evidence).
- A GPU error is seen at the next tick that polls it (normally 1-3 frames later); those frames showed
  the failed work without caching too, so the output is unchanged.
- Materials, generator graphs, video, camera, spectra and projectM keep rendering every frame. A
  generator graph without time or music nodes, or a paused video, could opt in later.

## Alternatives rejected

- Opt-out (every layer cached unless it says otherwise): one forgotten flag shows a stale picture.
- A content hash of the picture: needs a GPU read-back or a full render to compute.
- Skipping the flash guard or the output pass on a reused frame: an unfilled drawable, and an envelope
  that would skip time.
- Composite placement in the layer key: every opacity fade would re-render static layers for nothing.

## Amendment 2026-11-14 (FX-009, ADR-0051)

While a compositor's motion feedback ("Trails") is active, the composite is never kept (level 2): the shown frame
depends on the previous frames, so no time-dependent output enters the cache. Layer pictures (level 1) may still be
reused. With Trails off, caching is unchanged.
