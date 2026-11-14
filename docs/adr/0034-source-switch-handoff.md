# ADR-0034: Source Switch With a Ducked, Bounded Handoff at the Renderer Boundary

- **Status**: Accepted 2026-11-13 (decided by Claude under the owner's best-judgement rule, owner
  rule 4)
- **Feature**: AUD-012 (`specs/092-aud-012-source-crossfade`)
- **Constitution**: I (public APIs only), IV (truthful source labeling), VI (modular boundaries),
  VII (real-time audio safety); Privacy (no new capture or permission)
- **Builds on**: ADR-0001 (capture architecture, serialized source commands), the Phase B normalized
  ring (research R-05, R-06), ANL-016's capture-session generation
- **Amends**: R-06's underrun policy ("no silence is injected") by one exception: the 1,024-frame
  silence of a source switch

## Context

Until now a source could only be changed by going back to the chooser. At the manager level a
switch was a hard cut: the measured step was full scale (+0.5 to −0.5), projectM froze on the old
PCM until the new source's first buffer, the label named the new source before any of its audio
existed, and NaN/±Inf from a source reached projectM and the analysis tap unchanged (one NaN at
48 kHz became 29 after the resampler and made the level meter read −120 dBFS). The roadmap row
AUD-012 asks for a mid-session switch with "a bounded audio-analysis handoff" and "no discontinuous
NaN or stale source labels".

## Decision

1. **Duck, never crossfade.** The old source fades to exact silence over 100 ms while it keeps
   delivering (the wait is capped at 150 ms; a source that cannot deliver is completed from its last
   sample over at most 1,024 frames), stops (FR-016), 1,024 frames of silence follow, and the new
   source fades in over 100 ms. Two sources never run at once (FR-001), no mix is ever labeled as one
   source (IV), and no audio-session configuration or permission changes. Bound: 300 ms of sample
   clock; every step the handoff adds is at most |a| / 1,024 (|a| ≤ 2).
2. **The renderer boundary is `NormalizedPCMRing.write`** (AudioCore), the one place every normalized
   sample passes before projectM's ring and the analysis tap, on the analysis queue. It sanitizes
   (NaN/±Inf → 0, clamp to ±2 on the capture path, counted) and applies the switch envelope. Clean
   audio at unity is written bit-identically with no copy. The analyzer also replaces non-finite
   samples before level metering and conversion. No audio callback changes, so T063's evidence (no
   allocations or lock waits in audio callbacks) stays valid.
3. **A switch's new session keeps projectM's ring.** The analysis tap is emptied and only then the
   generation advances (ANL-016-R9); projectM's ring keeps its faded tail, which ends at exact 0, so
   a reader that has not caught up never sees the ramp turn into a step. FIFO order puts every old
   frame before every new one.
4. **Label rule.** `CaptureManager.switchingTo` makes the indicator read "Switching source…" from the
   request until the new attempt's first audio is published (published at once, not after the
   250 ms cadence), its state is decided, or it ends. The old label is never shown after the request
   and the new source is not named before its audio flows.
5. **Orchestration stays in `CaptureManager`** (`switchSource(to:)`), serialized with every other
   source command; a newer command supersedes a switch at any point and the gain continues from its
   current value. `select`, `stop`, `restart`, `pause` and `resume` are unchanged.

## Consequences

- One more state on the capture path (the envelope) and one documented exception to R-06.
- The capture path's ring now clamps beyond ±2 (+6 dBFS); audio within ±2 is bit-identical. A ring
  made without a bound (harnesses, RendererLab) replaces only NaN/±Inf.
- Device behavior across real routes and interruptions during a switch is AUD-012-T20 (`{device}`,
  open).

## Alternatives considered

- **True crossfade** (two sources, two sinks, a mixer): breaks FR-001 and IV, needs two audio
  sessions; rejected.
- **Hard cut (as before)**: full-scale steps and projectM frozen on old audio; rejected.
- **Fades and sanitizing in each renderer's read**: three renderers plus the analysis readers, and the
  fade would follow read timing rather than the audio; rejected.
