# ADR-0011: Strobe safety envelope

- **Status**: Accepted 2026-11-13 (decided by Claude under the owner's best-judgement rule, owner
  rule 4; feature FX-019)
- **Date**: 2026-11-13
- **Spec**: `specs/022-fx-019-strobe-safety-envelope/` (research FX-019-D1 to D8)
- **Constitution**: I, VI, VII, X; Privacy

## Context

Spec 001 requires a photosensitivity notice (FR-071) and a Reduce flashing setting (FR-072). Two
limiters implemented FR-072 as rate limits with different constants: `CFlashLimiter` for projectM
frames (0.3 per second, two-sided with a gray lift, T104) and `FlashSafetyLimiter` for native
visuals (0.25 per second, rises only; VIS-001-R10, FX-001-R10). Neither defined a flash, counted
flashes, handled red flashes or local areas, or did anything with the setting off.

## Decisions

1. **Definition** (research FX-019-D1). A transition is an opposing change of at least 0.10 in
   WCAG relative luminance, or of at least 0.0625 in redness max(R − G − B, 0) (WCAG's red-flash
   working definition, 20 / 320), measured with hysteresis from the previous leg's extreme. A flash
   is a pair of transitions. Basis: W3C WCAG 2.x SC 2.3.1 and its general/red flash threshold
   definitions; ITU-R BT.1702 and Ofcom guidance agree (at most three flashes per second). Stricter
   than the guidance: no 0.80 darker-state exemption, no red saturation condition, a lone
   transition counts as a flash.
2. **Limits.** Window 1 s on a frame clock (frame times clamped to 0…0.1 s). Reduce flashing on:
   at most 4 transitions (2 flashes) per window per area and signal, and rises of at most 0.25 per
   second. Off: an always-on cap of 6 transitions (3 flashes, the guidance's limit), no rate limit.
3. **Mechanism** (FX-019-D2). One uniform gain in 0…1 per frame: the envelope only dims, never
   brightens. A rise transition is allowed only while the window holds at most budget − 2
   transitions, so the fall that may follow is always within budget. The old gray lift is removed.
4. **Areas** (FX-019-D3). Whole frame plus a 4 × 4 grid (each tile 6.25 % of the screen; WCAG's
   25 % of a 10° field is about 8 % of an iPhone screen at 30–40 cm; ITU uses a quarter of the
   screen). Known residual: a flash of about 3 % of a large iPad screen that straddles tile borders
   is diluted; ACC-002 and ACC-012 may tighten this.
5. **One definition, two executions** (FX-019-D4). Package `FlashSafety` (pure Swift, Linux-tested)
   is the definition and the native-visual implementation; `CFlashLimiter` runs a GLSL port in the
   same frame on the GPU (a CPU read-back would stall every frame). GPU tests compare the two.
6. **Consumers.** ACC-002 and ACC-012 supply stricter `FlashEnvelopeConfiguration` values (never
   looser than `.alwaysOn`); PERF-003 must never skip the pass. History survives a toggle of the
   setting and size changes; only suspension or a new visual resets it.

## Consequences

- Every projectM frame now runs the post-pass (T104 measured 1.21 ms median on D1 with the old
  passes); re-measuring is a device task. If the pass cannot be created, frames are drawn directly.
- With Reduce flashing on, a single sustained cut to black is shown as a cut (it is one transition)
  instead of a gray fade.
- Native visuals: each bar's own light is placed in the tiles exactly; the glow's added light is
  spread over the tiles its halo box overlaps, in proportion (an estimate: a tile's measured rise
  may exceed the modeled one, by up to 0.016 per frame in the Mac GPU test); the whole-frame area
  keeps FX-001's exact upper bound.
