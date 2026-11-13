# Feature Specification: CMP-001 Unified Layer Protocol

**Feature Branch**: `feature/cmp-001` (spec directory `029-cmp-001-unified-layer-protocol`)

**Created**: 2026-11-13

**Status**: Draft

**Input**: User description: "Implement CMP-001 (Unified layer protocol) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Expose render-to-texture sources
with explicit time and audio context." Acceptance, verbatim: "Two dummy sources composite without
direct engine coupling." Dependencies: FX-001 (integrated); builds on VIS-001/VIS-002, FX-019 and the
ANL-016 bus. Honor the repository constitution (VI) and owner rule 7."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `CMP-001-R1…`, success criteria `CMP-001-S1…`, tasks `CMP-001-T01…`. Requirements
of other features are cited by their own IDs: FR-072 (Reduce flashing); VIS-001-R1, R10, R16, R19
(the native visual contract, its Reduce-flashing slew, fallback, determinism); VIS-002-R1, R9;
FX-001-R10, R13 (glow light bound and failure); FX-019-R4, R9, R11 (the strobe safety envelope:
17 areas, every frame, history kept across pauses); ANL-016-R2, R3 (the analysis bus's frames and
events).

## Baseline: what exists today (audit of 2026-11-13, commit `733c5d6`)

This is a gap row ("Gap candidate; re-audit at implementation"). The audit confirms the gap.

| Area | Today | Gap for this row |
|---|---|---|
| Native visuals | VIS-001 and VIS-002 draw into a caller's texture (`TextureGenerator`, ADR-0009); one app host draws one of them straight into the screen. | Nothing combines several visuals; a generator is driven only by the app host. |
| Post-processing | FX-001's effect chain runs effects between one source and the output (ADR-0010). | Works for one source only. |
| Flash safety | FX-019's envelope bounds each native spectrum's own frame (in the generator) and projectM's frame (in the GL post-pass), ADR-0011. | No bound exists for a picture made of several layers: two safe layers could add up to an unsafe one. |
| projectM | Draws through ANGLE into a window surface on a Metal layer (ADR-0003); nothing else can read its frame. | Whether projectM can draw into a texture the rest of the app can sample is unproven (audit "Architecture finding"). |
| Analysis | ANL-016's bus delivers timestamped feature frames and events to subscribers. | No visual receives them together with a frame clock. |

## Clarifications

### Session 2026-11-13

Answered by Claude under the owner's standing approval (owner rule 4: routine decisions delegated,
no human interaction); each answer is the conservative, local-first option, recommended option
first.

- Q: Where is flashing bounded when several layers are stacked: in each layer, on the final composite, or both? → A: Both, with the final composite as the guarantee. The compositor runs FX-019's envelope (17 areas, luminance and redness, Reduce-flashing or always-on configuration) on the finished stack every frame, on the GPU with no read-back, before anything reaches the output; a stack therefore cannot add up to a strobe. Layers that already limit themselves (the spectra's Reduce-flashing slew and envelope) keep doing so; projectM's GL post-pass stays in the full-screen renderer and the projectM layer relies on the composite bound (research CMP-001-D8): two gains of at most 1 can only dim, never brighten. Rejected: per-layer only (out-of-step layers sum to a strobe); composite only for the spectra (would drop VIS-001's bar slew, a different, gentler softening) (CMP-001-R10, S5).
- Q: What color format, color space and orientation do layer pictures use? → A: 16-bit float RGBA, linear light with sRGB (Rec. 709) primaries and D65 white, premultiplied alpha, row 0 at the top (Metal's convention), one picture per layer at the full output size. The output may be an 8-bit sRGB screen picture or a 16-bit float picture; encoding happens only when the output is written. Rejected: 8-bit sRGB layers (banding and wrong blending in gamma space); extended-range or wide-gamut spaces (nothing produces them yet; a later MED/CAM row can add a declared space) (CMP-001-R2).
- Q: What does a failing layer show, and how is "last good frame" kept? → A: Each layer declares its fallback. *Transparent*: nothing of that layer is shown for the failed frame. *Last good frame*: the compositor keeps a second picture for that layer and renders into the one not holding the last success, so a failed or half-drawn frame never overwrites the good one; before any success the layer is transparent. The spectra and projectM declare last good frame (a skipped frame must not flicker); dummy and test layers choose either. Failures are reported per frame in a preallocated report (layer index, outcome, typed reason) (CMP-001-R7, R8, S3).
- Q: How do frames, bands and events reach a layer, and what bounds them? → A: The caller of the compositor passes a frame time (monotonic nanoseconds, e.g. the display link's target time) and an audio context each frame; the compositor derives the frame number and duration (clamped to 0…0.1 s, the FX-019 clamp; a backwards time reads as the previous time) and hands both to every layer as plain values. A reusable, preallocated audio buffer fills the context from an ANL-016 subscription without allocating: up to 128 bands of the latest frame and up to 64 events since the previous frame (oldest first; when more arrived, the newest 64 are kept and the rest counted as dropped). Layers must not keep the band or event storage after the frame (CMP-001-R3, R4).
- Q: The spike shows the pinned ANGLE build can draw into a Metal-readable texture on the simulator; does projectM become a layer now, and does the app use it? → A: Yes to the layer, no to the app. A projectM layer source is added next to the ANGLE code: its own EGL context and engine draw into a Metal texture wrapped as an EGL image (`EGL_ANGLE_metal_texture_client_buffer`), ANGLE signals a Metal shared event after the frame (`EGL_ANGLE_metal_shared_event_sync`) and the compositor's GPU work waits for it (no CPU wait), and a Metal pass flips the picture upright and converts it to linear premultiplied. It knows nothing of the other layers or the analysis bus; it takes PCM the way the visible engine does. The app is not changed in this row (no debug flag either): wiring the compositor into the screen is a later row, after device checks of cost and correctness ({device}) (CMP-001-R13, R14, S7).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Two independent layers combine into one picture (Priority: P1)

Whoever builds a later visual feature (layer stacks, photos, video, camera, text, recording) takes
two layer sources that know nothing about each other or about projectM, hands them to the
compositor, and gets one picture in which the upper layer covers the lower one according to its
transparency.

**Why this priority**: It is the roadmap acceptance ("Two dummy sources composite without direct
engine coupling") and the foundation of every CMP, MED, CAM, OUT, REC and SCN row.

**Independent Test**: Composite a half-transparent red layer over an opaque blue layer at a small
size, read the picture back and compare every pixel with the "over" result.

**Acceptance Scenarios**:

1. **Given** an opaque blue layer below a 50 %-transparent red layer, **When** they are composited, **Then** every pixel equals red over blue (half red, half blue, fully opaque) within 1/255.
2. **Given** the two layers in the opposite order, **When** composited, **Then** the opaque blue covers the red completely.
3. **Given** either layer, **When** its definition is inspected, **Then** it refers to neither the other layer, the compositor's other layers, the engine (projectM), the renderer nor any capture technology.

---

### User Story 2 - Every layer sees an explicit clock and the music (Priority: P1)

A layer author receives, with every frame, when the frame will be shown (a monotonic time), which
frame it is, how long since the previous one, the output size, and the latest music analysis (band
levels, onset strength, tempo) together with the discrete events (onsets, beats) that arrived since
the previous frame, as plain values. The layer never asks the engine, the audio source or the clock
itself.

**Why this priority**: The row's observable behavior ("explicit time and audio context").

**Independent Test**: Give the compositor a sequence of frame times and analysis values (including a
time that goes backwards) and record what a probe layer receives.

**Acceptance Scenarios**:

1. **Given** frame times t₀ < t₁ and analysis values, **When** two frames are composited, **Then** the probe layer receives exactly those times, frame numbers 0 and 1, the difference t₁ − t₀, the output size, and exactly the given band values and events.
2. **Given** a frame time earlier than the previous one, **When** composited, **Then** the layer sees the previous time again and a zero frame duration (time never runs backwards).
3. **Given** no analysis is available (no audio, analysis stopped), **When** composited, **Then** the layer receives an empty audio context and still renders.

---

### User Story 3 - A failing layer never takes the picture down (Priority: P1)

When one layer cannot produce a frame (its resources failed, its content is not ready, it reports
an error), the other layers still appear, the failing layer shows its declared fallback (nothing, or
its last good frame), and the failure is reported with a typed reason. The app never crashes and
never shows a black screen because of one layer.

**Why this priority**: Roadmap failure boundary ("degrade to safe fallback, not crash") and the
render boundary's "safe fallback".

**Independent Test**: Composite a layer that fails on chosen frames together with a working layer.

**Acceptance Scenarios**:

1. **Given** a layer that fails and declares "transparent" fallback, **When** composited over a working layer, **Then** the picture is the working layer alone and the failure is reported for that layer with its reason.
2. **Given** a layer that rendered once and then fails, declaring "last good frame", **When** composited, **Then** its last good picture is shown and the failure is reported.
3. **Given** a layer whose preparation for a new size fails, **When** composited, **Then** the other layers still render and that layer is reported as unavailable until a later preparation succeeds.

---

### User Story 4 - Layers can be any size the screen needs (Priority: P2)

When the output size changes (rotation, iPad window size, render scale), every layer's working
picture is reallocated exactly once and the layers are told the new size; at a steady size nothing
is created per frame.

**Why this priority**: Resource ownership is part of the contract later rows build on (PERF-004
texture pool, CMP-013 caching).

**Independent Test**: Composite at one size for several frames, change the size, composite again,
and count allocations.

**Acceptance Scenarios**:

1. **Given** a steady output size, **When** several frames are composited, **Then** no layer picture is created after the first frame.
2. **Given** a new output size, **When** the next frame is composited, **Then** each layer's picture is created exactly once at the new size and each layer is told the new size exactly once.

---

### User Story 5 - Flashing stays bounded however many layers are stacked (Priority: P1)

A user who relies on Reduce flashing (or anyone, with the always-on cap) sees a composited picture
that obeys FX-019's limits as a whole, even if several layers each flash within their own limits but
out of step with one another.

**Why this priority**: Constitution safety and FX-019; a stack must not add up to a strobe.

**Independent Test**: Composite a layer that alternates full white and black every frame at 60 Hz
and count the transitions of the final picture's areas.

**Acceptance Scenarios**:

1. **Given** a layer strobing white/black every frame at 60 Hz, **When** composited with Reduce flashing on (off), **Then** no area of the final picture has more than 4 (6) transitions per 1 s window, and with it on no area rises faster than 0.25 per second.
2. **Given** a steady picture, **When** composited, **Then** the final picture is unchanged by the bound (gain 1).

---

### User Story 6 - Existing visuals and projectM as layers (Priority: P2)

The circular and linear spectra (with the glow) are available as layers that take their bands from
the audio context. projectM is offered as a layer only if the pinned ANGLE build can draw it into a
texture the compositor can sample; otherwise the gap is documented with its exact cause and next
step, and projectM keeps drawing as today. What the app shows does not change in this feature.

**Why this priority**: Proves the protocol fits the visuals that exist; the projectM question decides
how the later CMP rows get projectM into a stack.

**Independent Test**: Composite a spectrum layer from a reference band vector and check lit pixels;
query the ANGLE extensions at run time on the simulator and record the outcome.

**Acceptance Scenarios**:

1. **Given** a reference band vector in the audio context, **When** a spectrum layer is composited, **Then** its bars appear where the spectrum's own layout predicts.
2. **Given** the iOS simulator, **When** the projectM spike runs, **Then** it records which client-buffer extensions the display reports and whether a frame drawn by ANGLE can be read through Metal, and the result decides whether a projectM layer exists.
3. **Given** the app built from this feature, **When** it runs, **Then** what it shows and how it behaves is unchanged.

### Edge Cases

- No layers: the output is the background (transparent black, or opaque black when the output has no alpha).
- A layer returns colors outside 0…1 or not-a-number: the compositor's arithmetic stays finite and the final picture is clamped by the output's format (no crash, no poisoning of other layers).
- Output size 0 in either dimension: nothing is rendered and nothing is allocated.
- A layer's preparation succeeds after an earlier failure: it reappears from the next frame.
- An analysis frame with fewer bands than a layer wants: missing bands read 0 (VIS-001-R8).
- More events since the previous frame than the context holds: the newest are kept and the count of dropped events is reported (bounded, no allocation).
- The same layer object given twice in one stack: rejected when the stack is built (one owner per layer).

## Requirements *(mandatory)*

### Functional Requirements

- **CMP-001-R1**: A *layer source* MUST render one frame into a picture that the compositor owns and provides, of a declared size and color format, covering the whole picture; it MUST NOT keep a reference to that picture after the frame.
- **CMP-001-R2**: Pictures exchanged between layers and the compositor MUST be 16-bit float RGBA in linear light with sRGB (Rec. 709) primaries, premultiplied alpha, row 0 at the top; the compositor converts to the output's encoding (8-bit sRGB or 16-bit float) only when writing the output.
- **CMP-001-R3**: Each frame a layer MUST receive a frame context: a monotonic presentation time (nanoseconds, never decreasing; a time earlier than the previous frame's is replaced by the previous time), a frame number starting at 0 and increasing by 1 per composited frame, the duration since the previous frame (0 for the first frame and when time did not advance, clamped to at most 0.1 s), the output size in pixels and its scale, and the Reduce flashing setting (FR-072).
- **CMP-001-R4**: Each frame a layer MUST receive an audio context as plain values: the latest analysis frame's metadata (ANL-016-R2), its band levels (0…1), and the discrete events (ANL-016-R3) delivered since the previous frame, oldest first, in bounded storage (up to 128 bands and 64 events per frame; when more events arrived, the newest 64 are kept) with a dropped-event count. It MUST NOT receive the engine, the capture system or any audio source object.
- **CMP-001-R5**: Layer sources MUST NOT depend on projectM, the renderer, ANGLE, capture or the app; the compositor MUST NOT depend on them either. A projectM layer, if one exists, lives with the ANGLE code and depends only on the layer contract (Constitution VI).
- **CMP-001-R6**: The compositor MUST own every layer picture and the composite: it creates them when the output size or format changes (exactly once per change) and before the first frame, tells each layer its size through a preparation step called exactly once per change, and creates nothing per frame at a steady size.
- **CMP-001-R7**: A layer MUST declare its fallback, *transparent* or *last good frame* (kept in a second picture, so a failed frame never overwrites the good one). When it fails a frame it reports a typed reason; the compositor then shows its fallback for that frame (a last-good layer with no good frame yet is transparent), records the failure per layer, and composites every other layer normally. A failure never crashes and never blanks the other layers.
- **CMP-001-R8**: A layer whose preparation fails MUST be reported unavailable with its reason and skipped until a later preparation (the next size change or an explicit retry) succeeds.
- **CMP-001-R9**: The compositor MUST composite a fixed, ordered list of layers bottom to top with normal premultiplied "over" blending onto a transparent background, and write the result to a caller-provided output picture.
- **CMP-001-R10**: The final composite MUST pass through FX-019's strobe safety envelope (17 areas, luminance and redness, Reduce-flashing or always-on configuration, FX-019-R4, R9) before it reaches the output, so the stack as a whole is bounded; the envelope's history is kept across pauses (FX-019-R11) and can be reset for a new scene. Layers that already limit their own flashing keep doing so.
- **CMP-001-R11**: The contract MUST leave room for CMP-002…005 without breaking changes: per-layer opacity, blend mode and transform are described in the layer's composite settings with only "opacity 1, normal blend, identity transform" supported now; anything else is rejected, not silently ignored.
- **CMP-001-R12**: The circular and linear spectra (VIS-001, VIS-002) with the FX-001 glow MUST be available as layer sources fed from the audio context's band levels, keeping their own Reduce-flashing behavior (VIS-001-R10, VIS-002-R9, FX-001-R10).
- **CMP-001-R13**: A spike on the iOS simulator MUST query, at run time, the pinned ANGLE build's client-buffer extensions (IOSurface and Metal texture) and try to draw an ANGLE frame into a picture Metal can read. If it works (it does on the simulator; see Clarifications), a projectM layer source MUST be provided behind the contract (it knows nothing of the other layers or the analysis), synchronized with the compositor on the GPU; if not, the exact failure and a concrete next step MUST be recorded in the architecture decision and projectM keeps drawing as today.
- **CMP-001-R14**: The app's visible behavior MUST NOT change in this feature.
- **CMP-001-R15**: Per frame, the compositor and the adapters MUST NOT allocate, lock with unbounded wait, log or do I/O; the CPU-side contract (frame and audio context rules, ordering, fallback bookkeeping, picture descriptions) MUST build and be tested on every CI host, including Linux.

### Key Entities

- **Layer source**: identity, declared fallback, preparation for a size, one frame rendered into a provided picture.
- **Layer picture description**: size in pixels, color format, color space, alpha convention, usage.
- **Frame context**: presentation time, frame number, frame duration, output size and scale, Reduce flashing.
- **Audio context**: analysis frame metadata, band levels, events since the previous frame, dropped-event count.
- **Layer composite settings**: opacity, blend mode, transform (fixed values in this row).
- **Composite report**: per layer, rendered, fallback shown (which) or unavailable, with the typed reason.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **CMP-001-S1**: Half-transparent red over opaque blue at 64 × 64 reads back as the "over" result within 1/255 on every pixel, and the reversed order reads back as opaque blue; where no GPU exists the check is reported as skipped.
- **CMP-001-S2**: A probe layer receives exactly the given times, frame numbers, durations, sizes, band values and events over a scripted sequence (including a backwards time and an empty audio context), on every CI host.
- **CMP-001-S3**: With one layer failing (each fallback kind) and one working, 100 % of pixels show the working layer plus the declared fallback, and the failure is reported with its reason.
- **CMP-001-S4**: Over 5 frames at one size and 5 at another, each layer's picture is created exactly twice (once per size) and each layer is prepared exactly twice.
- **CMP-001-S5**: A 60 Hz full/empty strobe composited for 2 s yields at most 4 transitions per 1 s window in every area of the final picture with Reduce flashing on and at most 6 with it off; a steady picture keeps gain 1.
- **CMP-001-S6**: A spectrum layer fed a reference band vector lights pixels only inside its own predicted bars (within one pixel).
- **CMP-001-S7**: The projectM spike's outcome (extension strings and result) is recorded in the architecture decision; if a projectM layer exists, a frame it draws reads back non-empty through the compositor on the simulator.
- **CMP-001-S8**: Each new test takes at most 10 s (typically 1-2 s) and the new package's suite under 1 minute on the host (owner rule 7); every existing test of the touched packages passes unchanged; the app's UI tests for native visuals pass unchanged.

## Assumptions

- Later rows (CMP-002 onward) add stack editing, opacity, blend modes, transforms, caching and transitions; this row only composites a fixed list with normal blending.
- The app does not use the compositor yet; wiring it into the visualizer screen is a later row.
- The simulator renders with the host GPU; CI simulators may lack a usable GPU, so GPU checks may skip there. Real-device GPU checks (including a projectM layer's speed) are `{device}` tasks for the roadmap's final phase.
- No new stored data, no network, no new dependency; the privacy manifest does not change.
