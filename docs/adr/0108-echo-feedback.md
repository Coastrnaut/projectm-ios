# ADR-0108: Echo Feedback Keeps a Ring of Exactly Four Half-Size History Pictures, Stored Once per Delay

- **Status**: Accepted 2026-11-15 (decided by Claude under the owner's best-judgement rule, owner rule 4)
- **Feature**: FX-010 (`specs/297-fx-010-echo-feedback`)
- **Constitution**: I (public APIs; shader policy of ADR-0024), VI (modular boundaries), VIII (default output
  bit-identical), X (evidence-based quality)
- **Builds on and amends**: ADR-0106 and ADR-0104 (the effect-chain walk gains the kind `fx.echo`, appended last),
  ADR-0051 (FX-009 Trails: the same frame clock, reset triggers, brighter-of blend and ACC-012 limiting), ADR-0054
  (FX-020 chain), ADR-0024 (no new compile site), ADR-0009 (run-time compiled module constants)

## Context

The roadmap row FX-010 asks to "render multiple delayed echoes using bounded history buffers", with the acceptance
"echo count is capped and memory use remains bounded". A frame-exact delay line needs count × delay frames of
history; at 4 echoes 500 ms apart and 60 fps that is 120 full-size pictures (gigabytes on an iPad).

## Decision

1. **Own pass**: `EchoPass` has two functions, `cmp_echo_capture` (stores a picture) and `cmp_echo` (draws the
   echoes), both module constants spliced into the existing compile site and listed in
   `CompositorShaderSources.archived`. Inactive (off, count 0, or a weight cap of 0): no pass, no picture,
   bit-identical output.
2. **Cap**: at most 4 echoes (`EchoFeedback.cap`, shader constant `cmp_echo_cap`); any larger request gives 4, and
   the shader's loop bound is `min(count, cmp_echo_cap)`.
3. **Bounded history**: a ring of exactly 4 `rgba16Float` pictures (the cap, whatever the count) at the history size:
   half the output per axis, rounded to a multiple of 16 (≥ 16), scaled so the longer side is ≤ 960. Worst case
   4 × 960 × 960 × 8 = 29,491,200 bytes at any output size (D1 13.3 MB, D2 22.1 MB, D3 20.2 MB, 4K 16.7 MB). Taken
   from the texture pool once when Echo turns on, kept through count, delay and fade changes, replaced only when the
   history size changes, returned when Echo turns off. Nothing is allocated per frame.
4. **Sample and hold**: one picture is stored each time the delay (10…500 ms) has passed on the frame clock, at most
   once per frame, after the frame's echoes are drawn; echo k is the k-th most recent store, between (k − 1) × delay
   and k × delay old plus one frame. Stores are copies of the picture entering Echo (no echo of an echo).
5. **Blend and safety**: out = max(current, Σ w_k × stored_k) per channel, w_k = decay^k scaled together so
   Σ w_k ≤ the weight cap (1). The output is never brighter than the brightest frame it is made of. ACC-012: an
   intensity-capping profile scales the weight cap by its limit, Reduce flashing caps it at 0.5, 0 turns Echo off.
   The FX-019 flash guard measures the shown frame, after Echo.
6. **Resets**: the history empties (no echo of earlier content) on turning on, a history-size change, a scene change
   (`resetFeedback`, `resetFlashHistory`), a render-health reset, an output-format change, a transition start and an
   unfinished frame, as for Trails. CMP-013 composite reuse stays allowed: the echo pass runs every frame.
7. **Chain and storage**: `OutputEffectKind.echo` (`fx.echo`) appended after the existing kinds (FX-008 appends its
   own in parallel; neither reorders). Global setting `settings.echo.*`; scenes and presets carry an `fx.echo` entry
   (`count`, `delay`, `decay`); a disabled echo counts as default.

## Consequences

- Echoes are half-resolution (or smaller) copies and move in steps of the delay (a stroboscopic look at long delays),
  the price of a fixed memory bound independent of the delay.
- Per active frame: one full-screen pass of ≤ 4 bilinear history samples, and on storing frames one history-size pass
  of 4 samples per pixel; plus one output picture at composite size.
- The device frame-rate check is FX-010-T17 `{device}`.
